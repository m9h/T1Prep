# Legion-side agent prompt — full FreeSurfer recon-all for DLBS sub-1003

Copy-paste everything below the line into the Legion-side agent.

---

You are running on `fedora-legion` (16-core x86_64, 8 GB GPU,
`/data` NFS-mounted from the same TrueNAS that DGX Spark uses,
FreeSurfer 8.2.0 available via podman). Your job: produce full
FreeSurfer recon-all output for **DLBS subject sub-1003 across 3
longitudinal sessions** so that downstream tools (PETSurfer,
AANSegment, NextBrain, hippocampal subfields, longitudinal stream)
on the Spark side can resume.

## Inputs (already on /data, NFS-shared)

```
/data/raw/openneuro/ds004856/sub-1003/ses-wave1/anat/sub-1003_ses-wave1_acq-MPRAGE_run-1_T1w.nii.gz
/data/raw/openneuro/ds004856/sub-1003/ses-wave2/anat/sub-1003_ses-wave2_acq-MPRAGE_run-1_T1w.nii.gz
/data/raw/openneuro/ds004856/sub-1003/ses-wave3/anat/sub-1003_ses-wave3_acq-MPRAGE_run-1_T1w.nii.gz
```

FreeSurfer license: `~/license.txt` on Legion.

## Output destination (write to NFS so Spark can read)

```
SUBJECTS_DIR=/data/datasets/smri-fm-cmp/freesurfer/ds004856
```

You will create `${SUBJECTS_DIR}/sub-1003_ses-wave{1,2,3}/{mri,surf,label,stats,scripts}/`.

## Phase 1: cross-sectional recon-all × 3, in parallel (~6 hr wall)

For each of the 3 sessions, run:

```bash
podman run --rm \
  -v /data/raw/openneuro/ds004856:/raw:ro \
  -v /data/datasets/smri-fm-cmp/freesurfer/ds004856:/subjects:rw \
  -v ~/license.txt:/usr/local/freesurfer/license.txt:ro \
  -e SUBJECTS_DIR=/subjects \
  -e FS_LICENSE=/usr/local/freesurfer/license.txt \
  <freesurfer-image-tag> \
  recon-all \
    -i /raw/sub-1003/${ses}/anat/sub-1003_${ses}_acq-MPRAGE_run-1_T1w.nii.gz \
    -s sub-1003_${ses} \
    -all -openmp 4 -3T
```

Replace `<freesurfer-image-tag>` with whatever local podman tag you have
(e.g. `freesurfer:8.2.0` or `nipreps/freesurfer:8.2.0`). Run all 3
sessions concurrently as background jobs; `-openmp 4` × 3 = 12 cores
out of 16.

**Success criterion per session**: `${SUBJECTS_DIR}/sub-1003_${ses}/surf/lh.pial`
and `rh.pial` exist and are non-zero.

## Phase 2: longitudinal base template (sequential, ~2-3 hr)

Once all 3 cross-sectional reconstructions finish:

```bash
podman run --rm \
  -v /data/datasets/smri-fm-cmp/freesurfer/ds004856:/subjects:rw \
  -v ~/license.txt:/usr/local/freesurfer/license.txt:ro \
  -e SUBJECTS_DIR=/subjects \
  -e FS_LICENSE=/usr/local/freesurfer/license.txt \
  <freesurfer-image-tag> \
  recon-all -base sub-1003 \
    -tp sub-1003_ses-wave1 \
    -tp sub-1003_ses-wave2 \
    -tp sub-1003_ses-wave3 \
    -all -openmp 8
```

Output: `${SUBJECTS_DIR}/sub-1003/` (the within-subject unbiased template).

## Phase 3: longitudinal per-timepoint × 3, in parallel (~1.5 hr wall)

```bash
for ses in ses-wave1 ses-wave2 ses-wave3; do
    podman run --rm \
      -v /data/datasets/smri-fm-cmp/freesurfer/ds004856:/subjects:rw \
      -v ~/license.txt:/usr/local/freesurfer/license.txt:ro \
      -e SUBJECTS_DIR=/subjects \
      -e FS_LICENSE=/usr/local/freesurfer/license.txt \
      <freesurfer-image-tag> \
      recon-all -long sub-1003_${ses} sub-1003 -all -openmp 4 &
done
wait
```

Outputs: `${SUBJECTS_DIR}/sub-1003_${ses}.long.sub-1003/` × 3.

## Total wall time

~10-11 hours (Phase 1 ~6 hr + Phase 2 ~3 hr + Phase 3 ~1.5 hr). Run
as one overnight batch.

## When done, report back

- Per-session: cross-sectional `lh.pial` mtime + mean cortical thickness
  from `awk '/StructName/,0' ${SUBJECTS_DIR}/sub-1003_${ses}/stats/lh.aparc.DKTatlas.stats | awk '{sum+=$5; n++} END {print sum/n}'`
- Longitudinal: confirm `${SUBJECTS_DIR}/sub-1003.base/` and
  `${SUBJECTS_DIR}/sub-1003_ses-wave{1,2,3}.long.sub-1003/` all exist
- Total wall time, any failures or stderr blocks of note

## Constraints

- **Do not** copy data — read from NFS, write to NFS, no scratch
  staging needed.
- **Do not** use `--gpus`. FreeSurfer's modern stages
  (mri_synthstrip / mri_synthseg) will fall back to CPU. SynthSeg on
  CPU adds ~5-10 min per scan, acceptable.
- **Do not** modify the existing FastSurfer outputs at
  `/data/datasets/smri-fm-cmp/fastsurfer/ds004856/sub-1003_*` — those
  are a separate pipeline and the FreeSurfer outputs go in a sibling
  directory at `/data/datasets/smri-fm-cmp/freesurfer/ds004856/`.
- If your local FreeSurfer container is named differently
  (`nipreps/fmriprep`, `freesurfer:7.4.1`, etc.), use that. Just confirm
  8.x or 7.4.x is fine — both produce DKTatlas surfaces compatible with
  downstream tools.
