# Legion-side agent prompt — DLBS Phase 4 (FreeSurfer post-surface + cohort scale-out + FSL CPU)

Copy-paste everything below the line into the Legion-side agent.

---

You are running on `fedora-legion` (16-core x86_64, 8 GB GPU, FreeSurfer
8.2.0 native + podman, FSL native, `/data` NFS-shared with DGX Spark).
You already delivered Phase 1–3 for sub-1003 (cross × 3 + base + long
× 3). Spark side is **stalled** on the post-surface cascade because
the arm container ships without `samseg` (the Python module gtmseg
and `segment_subregions` both need). You have it. Take over.

The DGX Spark side will not be running any FreeSurfer until the
neurodebian agent ships the next .deb rev, so **all FreeSurfer DLBS
work goes through you**. FSL CPU jobs likewise.

## Inputs (all on /data NFS, same paths as Spark)

```
RAW   = /data/raw/openneuro/ds004856/<sub>/<ses>/{anat,dwi,func,fmap,pet}/
FS    = /data/datasets/smri-fm-cmp/freesurfer/ds004856/             # SUBJECTS_DIR
INT   = /data/datasets/smri-fm-cmp/integrated/ds004856/<sub>/<ses>/  # canonical integrated tree
LIC   = /data/mhough/dev/comparison/license.txt                     # FS license
```

23-subject sub-cohort (already filtered for full multimodal coverage):

```
sub-1003 sub-1007 sub-1013 sub-1022 sub-1023 sub-103 sub-1031 sub-1045
sub-1054 sub-1058 sub-1084 sub-1093 sub-1139 sub-1141 sub-1146 sub-1149
sub-1153 sub-1157 sub-1172 sub-1175 sub-1183 sub-1200 sub-1220
```

`sub-1003` is the pilot (Phase 1–3 already done — outputs in
`${FS}/sub-1003_ses-wave{1,2,3}/`, base at `${FS}/sub-1003/`, long at
`${FS}/sub-1003_ses-wave{1,2,3}.long.sub-1003/`).

---

## Phase 4a — sub-1003 post-surface FreeSurfer cascade

Run on the existing cross-sectional outputs (not the longitudinal
.long dirs — those are for atrophy trajectories, the SOTA segmenters
expect cross input). All four sub-tasks are independent, run them in
parallel.

### 4a-1: PETSurfer (4 PET scans)

Pipeline per scan: `gtmseg` (1× per session, idempotent — if
`mri/gtmseg.mgz` exists, skip) → `mri_coreg` PET→T1 → `mri_gtmpvc`
with cerebellum reference + `--psf 6 --rescale 8 47 --auto-mask 0.10
0.01 --default-seg-merge` → `gtmstats2table`.

Scans:
- amyloid `18FAV45`: `ses-wave1`, `ses-wave2`, `ses-wave3`
- tau `18FAV1451`: `ses-wave3` only

Output (NFS, downstream-readable):
```
${INT}/sub-1003/<ses>/pet/<tag>_<tracer>/petsurfer/
  coreg/pet2t1.lta
  pvc/{gtm,mg,rbv}.nii.gz
  pvc/gtm.stats.dat
  suvr.tsv
```
where `<tag>` is `amyloid` or `tau`.

Reference scaffold the Spark side wrote (just couldn't run): see
`/data/mhough/dev/comparison/scripts/integrated/petsurfer_sub1003.sh`
— same flags, just swap `docker` → `podman` and the FS image path
for whatever you have local.

### 4a-2: segment_subregions

Per session, 3 structures sequential per session, 3 sessions in parallel:

```bash
segment_subregions hippo-amygdala --cross sub-1003_ses-waveN
segment_subregions brainstem      --cross sub-1003_ses-waveN
segment_subregions thalamus       --cross sub-1003_ses-waveN
```

(FS 7.3+ unified rewrite; replaces the legacy
`segmentHA_T1`/`-brainstem-structures`/`segmentThalamicNuclei` trio.)

Outputs land under `${FS}/sub-1003_ses-waveN/mri/`:
- `lh.hippoSfLabels-T1.v22.mgz`, `rh.hippoSfLabels-T1.v22.mgz`,
  `lh.amygNucVolumes-T1.v22.mgz`, `rh.amygNucVolumes-T1.v22.mgz`
- `brainstemSsLabels.v13.mgz`
- `ThalamicNuclei.v13.T1.mgz`
+ stats tables under `stats/`.

Reference scaffold:
`/data/mhough/dev/comparison/scripts/integrated/segment_subregions_sub1003.sh`

### 4a-3: AANSegment (Olchanyi 2024, 10 brainstem nuclei)

Tool: `SegmentAAN.sh` if it ships in your FS 8.2.0 install (check
`/usr/local/freesurfer/8.2.0-1/bin/SegmentAAN.sh`). If absent, skip
and report — we'll get it from the upstream repo separately.

Per session:
```bash
SegmentAAN.sh sub-1003_ses-waveN
```
Output: `${FS}/sub-1003_ses-waveN/mri/AAN.mgz` + per-nucleus stats.

### 4a-4: NextBrain (Casamitjana/Puonti, ~300 ROIs/hemi histological)

Tool: `mri_histo_atlas_segment_fireants` if shipped (check
`/usr/local/freesurfer/8.2.0-1/bin/`). If absent, fetch via
`hub.docker.com/r/freesurfer/synthseg:nextbrain` or the upstream
NextBrain repo and run there. Per session, GPU-preferred but CPU
fallback exists.

Output: `${FS}/sub-1003_ses-waveN/mri/nextbrain_seg.mgz` + label LUT.

---

## Phase 4b — recon-all + base + long for remaining 22 subjects

Same shape as the sub-1003 pipeline you already ran. **sub-1007 is
the priority next subject** — confirmed by the user 2026-04-28; do
this one first and signal completion before continuing through the
remaining 21. Spark side will fire the post-surface cascade
(`petsurfer_sub1007.sh`, `segment_subregions_sub1007.sh`) the moment
sub-1007's `surf/lh.pial` + `rh.pial` + base + long markers land.

Modality context for sub-1007 (drives downstream cascade priority):
- amyloid AV45 PET × 3 sessions, tau AV1451 PET × W3 — full PETSurfer fan-out
- ASL × W1 + W3 (perf/) — independent vpjax pipeline
- DWI × 3 — independent FSL pipeline (Spark-side, already partial)

Subject queue (process top-down, signal each completion to NFS):

```
sub-1007  ← priority first
sub-1013 sub-1022 sub-1023 sub-103 sub-1031 sub-1045 sub-1054
sub-1058 sub-1084 sub-1093 sub-1139 sub-1141 sub-1146 sub-1149 sub-1153
sub-1157 sub-1172 sub-1175 sub-1183 sub-1200 sub-1220
```

Phases per subject:

1. **Cross-sectional × 3 sessions** — `recon-all -i T1.nii.gz -s
   sub-XXXX_ses-waveN -all -openmp 4 -3T` (or `-openmp 5` if you can
   afford 3 parallel × 5 = 15 cores). T1 path:
   `${RAW}/sub-XXXX/ses-waveN/anat/sub-XXXX_ses-waveN_acq-MPRAGE_run-1_T1w.nii.gz`
2. **Base template** — `recon-all -base sub-XXXX -tp sub-XXXX_ses-wave1
   -tp sub-XXXX_ses-wave2 -tp sub-XXXX_ses-wave3 -all -openmp 8`
3. **Long × 3 sessions** — `recon-all -long sub-XXXX_ses-waveN sub-XXXX
   -all -openmp 4` (parallelizable)

**Idempotence**: skip if `${FS}/sub-XXXX_ses-waveN/surf/lh.pial` +
`rh.pial` exist for cross, `${FS}/sub-XXXX/surf/lh.pial` for base,
`${FS}/sub-XXXX_ses-waveN.long.sub-XXXX/surf/lh.pial` for long.

**Throughput target**: at ~6 hr / cross + ~3 hr / base + ~1 hr each
long, that's ~12 hr per subject single-threaded × 22 ≈ 11 days serial,
or ~3.5 days at 3-way concurrency. Cohort-level parallelism: queue
3 subjects' cross-sectionals at a time, then move to base+long when
each completes. Track in a simple per-subject status file under
`${FS}/_logs/<sub>.status` (`cross-done`, `base-done`, `long-done`).

**Concurrency budget**: 16 cores. Pick the topology that maximises
wall-clock, but a sane default is:
- 3 subjects × 3 sessions × `-openmp 1` = 9 jobs, 9 cores → too slow
- 3 subjects × 1 session × `-openmp 4` rolling = 12 cores → ~6 hr/round
- After cross done, 2 bases × `-openmp 8` parallel = 16 cores → ~3 hr each round

Once cross-sectional is done for all 22, do all 22 bases (one or two
at a time), then all 66 longs (3-way concurrent).

After the 22 are done, run **Phase 4a-2 (segment_subregions)** for
each of them too — hippocampal-subfield + brainstem + thalamus
volumes are the most-requested DLBS targets and trivially fast on
top of recon-all.

(PETSurfer 4a-1 only applies to subjects with PET — the others may
or may not; check `${RAW}/sub-XXXX/ses-waveN/pet/` for tracers.)

---

## Phase 5 — FSL CPU pipelines (cohort × 23)

The Spark-side scripts are at `/data/mhough/dev/comparison/scripts/fsl/`
— `common.sh` already forces `FSLSUB_CONF` to method:shell so jobs
run inline. Just run them on Legion (FSL native, no container needed):

- **`fdt_dlbs.sh`** — topup + eddy + dtifit + bedpostx + xtract + tbss
  (per subject + cohort-level TBSS aggregation at the end)
- **`oxford_asl_dlbs.sh`** — pCASL processing → CBF maps for ses-wave1
  and ses-wave2 (only those have ASL)
- **`melodic_dlbs.sh`** — single-session ICA on rest runs (5 per session)
- **`feat_dlbs.sh`** — task GLM on Scenes/Words/VV/Hyp (event files
  pre-generated under `${INT}/<sub>/<ses>/func/<task>/feat_run-N/design.fsf`)

Outputs: `${INT}/sub-XXXX/ses-waveN/{dwi,func,perf}/<tool>/`.

Run order (cheap → expensive): `oxford_asl` → `melodic` → `feat` → `fdt`.
`fdt` is the long pole (bedpostx is ~6 hr/scan, ~70 scans = 18 days
serial) — chunk into 3-way parallel and let it ride. Or, for the
phase-4 deadline, defer bedpostx/xtract and ship `dtifit` only.

---

## Reporting cadence

- Every ~6 hr or at phase boundaries: write a one-line status to
  `${FS}/_logs/legion_status.log` (timestamped). Spark-side periodically
  tails this.
- On any non-zero exit: dump the failing recon-all log path + last 30
  lines into `${FS}/_logs/_failures.log` and continue with the next
  job. Don't bring down the whole queue for one bad scan.
- When Phase 4a is done for sub-1003: post a one-line "Phase 4a done"
  with the `find ${FS}/sub-1003_ses-wave*/mri -name '*.mgz' -newer …`
  output so Spark side can verify and start the QC notebook.

## Hand-back signal

When Phase 4a is done and Phase 4b is queued, leave `${FS}/_logs/PHASE4A_DONE`
as an empty marker file. Spark side polls for it.

## What's *not* on you

- Brain-age ridge / smri-fm benchmarking — Spark
- BrainIAC embeddings — Spark (already done)
- vpjax CVR / kinetic models — separate agent (`vpjax_dlbs_agent_prompt.md`)
- Container builds — neurodebian agent

---

Ack with: which podman tag you'll use, your read of the 16-core
topology you'll run with for Phase 4b, and the ETA for Phase 4a-1 +
4a-2 (the PETSurfer-only and segment_subregions-only critical path).
