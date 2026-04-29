# sub-1007 readiness — what fires the moment Legion delivers recon-all

User confirmed 2026-04-28 that **sub-1007 is the next subject Legion
will recon-all**. Phase 4b ordering in
`legion_dlbs_phase4_prompt.md` updated accordingly.

This doc captures everything Spark side needs to do automatically
once Legion's outputs land, plus what's *already done* and what's
running in parallel right now.

## Already done on Spark for sub-1007

| Pipeline | Status | Where |
|---|---|---|
| BrainIAC preproc | ✅ 3 sessions | `/data/datasets/smri-fm-cmp/brainiac-preproc/ds004856/sub-1007_ses-wave{1,2,3}.nii.gz` |
| FastSurfer --seg_only | ✅ 3 sessions | `/data/datasets/smri-fm-cmp/fastsurfer/ds004856/sub-1007_ses-wave*/` |
| T1Prep | ✅ 3 sessions | `/data/datasets/smri-fm-cmp/t1prep/ds004856/sub-1007/ses-wave*/` |
| MedARC SynthSeg | ✅ at least partial | `/data/datasets/smri-fm-cmp/medarc-smri-fm/ds004856/sub-1007/` |
| FOMO25 AMAES embedding | ✅ via brainiac-preproc input | in the `fomo25_embeddings.parquet` row for sub-1007_* |

## Running in parallel right now (independent of Legion)

These don't need Legion's recon-all output:

| Pipeline | What | Triggered by |
|---|---|---|
| FSL completion for sub-1003 | dtifit / bedpostx W2+W3 / xtract / TBSS / oxford_asl | Already running (PID 925650) |
| Cohort extension on Spark | 22 new subjects' BrainIAC/SynthSeg/T1Prep/FastSurfer/FOMO25 | Already running (PID 605879 → currently sub-12 smoke) |

When sub-1007 FSL gaps need to be filled (same pattern as sub-1003):

```bash
SUBJECT=sub-1007 bash /home/mhough/dev/T1Prep/comparison/scripts/fsl/complete_subject_fsl.sh
```

## Waiting on Legion for sub-1007

Phase 4b deliverables Legion produces:

```
/data/datasets/smri-fm-cmp/freesurfer/ds004856/
  sub-1007_ses-wave1/{mri,surf,label,stats,scripts}/    # cross W1
  sub-1007_ses-wave2/...                                  # cross W2
  sub-1007_ses-wave3/...                                  # cross W3
  sub-1007/...                                            # base template
  sub-1007_ses-wave1.long.sub-1007/...                    # long W1
  sub-1007_ses-wave2.long.sub-1007/...                    # long W2
  sub-1007_ses-wave3.long.sub-1007/...                    # long W3
```

**Expected wallclock**: ~12 hr per subject at Legion's 16-core
topology (3 cross @ ~6 hr in parallel, then 1 base @ ~3 hr, then 3
long @ ~1 hr in parallel). Should land within a single day after
Legion picks up sub-1007.

## Auto-trigger — what fires once those markers exist

Detection: `${FS}/sub-1007/scripts/recon-all.done` exists AND all
three `${FS}/sub-1007_ses-waveN.long.sub-1007/surf/lh.pial` files
exist.

Fire (in order, can be parallelized within each):

### 1. Post-surface FreeSurfer cascade (Legion-side, per phase 4a-2)
Already in the Phase 4 prompt — Legion runs:

```bash
SUBJECT=sub-1007 bash segment_subregions_sub1003.sh    # parameterized
SUBJECT=sub-1007 bash petsurfer_sub1003.sh             # parameterized; 4 PET scans for sub-1007
```

Both scripts already accept `SUBJECT="${SUBJECT:-sub-1003}"` — no
changes needed, just env override. PETSurfer covers amyloid
W1/W2/W3 + tau W3 (same modality coverage as sub-1003).

### 2. Spark-side post-recon-all wire-up + ridge feature extraction

```bash
SUBJECT=sub-1007 bash wire_existing_outputs.sh          # symlinks into integrated/sub-1007/
# Then re-run ridge with sub-1007 morphometry features added to the matrix
```

### 3. Spark-side FSL completion (DTI/TBSS/ASL gaps)

```bash
SUBJECT=sub-1007 bash complete_subject_fsl.sh
```

Independent of Legion — could run now or after.

## Summary table for the team thread when sub-1007 lands

Once everything fires, the deliverable is "second subject through the
full multimodal pipeline", same shape as sub-1003. We'll have brain-age
ridge updates for the 24-subject sub-cohort (sub-1003 + sub-1007 +
22 already-done others), and the multimodal integrated tree for two
fully-processed subjects to compare longitudinal trajectories.

## Pointers

- This doc: `comparison/docs/sub1007_ready_when_legion_delivers.md`
- Legion phase-4 prompt: `comparison/docs/legion_dlbs_phase4_prompt.md` (sub-1007 prioritized in §4b)
- Templates that work for any subject:
  - `comparison/scripts/integrated/petsurfer_sub1003.sh` (use `SUBJECT=sub-XXXX`)
  - `comparison/scripts/integrated/segment_subregions_sub1003.sh` (use `SUBJECT=sub-XXXX`)
  - `comparison/scripts/fsl/complete_subject_fsl.sh` (use `SUBJECT=sub-XXXX`)
  - `comparison/scripts/integrated/wire_existing_outputs.sh` (sub-1003 hardcoded — needs parameterization too; flagged)
