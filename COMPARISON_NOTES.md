# T1Prep vs. MedARC sMRI-FM / BrainIAC preprocessing on DLBS

Branch: `smri-fm-dlbs-comparison`
Date started: 2026-04-21

## What we are comparing

MedARC has published a structural-MRI foundation-model dataset at
[medarc/smri-fm](https://huggingface.co/datasets/medarc/smri-fm) (NIfTI, 32.1 GB,
test split only as of April 2026). The effort tracks BrainIAC
(AIM-KannLab, Nature Neuroscience 2026) — a SimCLR-pretrained ViT foundation
model for generalized brain MRI trained on ~48.5k scans across 35 datasets,
including DLBS.

We want to see where **T1Prep** (this repo) could slot into — or replace parts
of — that pipeline, and whether T1Prep-derived morphometric features provide a
meaningful baseline against the FM embeddings on the
[Dallas Lifespan Brain Study](https://www.nature.com/articles/s41597-025-04847-7)
longitudinal cohort (464 → 338 → 224 subjects, Philips 3T Achieva, 3 epochs,
released on OpenNeuro 2025).

## Pipelines side by side

| Step | BrainIAC / sMRI-FM input prep | T1Prep |
|---|---|---|
| DICOM→NIfTI | dcm2nii | (upstream) |
| Bias field | N4 (SimpleITK) | DeepMriPrep |
| Resample | linear → 1 mm iso | native + template |
| Registration | **rigid** to MNI | **nonlinear** to MNI152 |
| Skull strip | HD-BET | DeepMriPrep brain extraction |
| Tissue seg | — | AMAP (CAT12) initialised from DeepMriPrep |
| Cortical surfaces | — | CAT-Surface (pial/white, thickness) |
| Atlas labels | — | optional |
| Final volume | 128³, 1 mm | TPMs + surfaces + MNI warp |

BrainIAC's prep is intentionally minimal — just enough to feed a 3D CNN.
T1Prep is a full morphometric pipeline in the CAT12 lineage.

## Candidate comparisons on DLBS

1. **FM embedding vs. classical morphometric features.** Run smri-fm (or
   a BrainIAC clone) on DLBS T1s. Run T1Prep to get TPMs / cortical thickness
   / Jacobian / atlas ROIs. Predict age, epoch-to-epoch change, and whichever
   cognitive scores are released. Compare held-out R² / MAE.
2. **Replace BrainIAC input prep with T1Prep skull-strip + nonlinear MNI.**
   Does a better-registered, segmented input change FM fine-tune performance?
3. **Longitudinal consistency.** DLBS has 3 epochs per returning subject —
   compare within-subject variance of FM embeddings vs. T1Prep thickness/TPM
   summaries.

Start with (1) — cleanest independent-baseline story, smallest compute.

## Open questions / to-confirm

- smri-fm dataset card is currently empty on HF (nibabel import error on
  viewer). Need to pull the parquet/NIfTI shards and inspect: which datasets
  contributed, what preprocessing was applied, is DLBS actually in the test
  split, is there a matching trained FM checkpoint.
- BrainIAC repo ([AIM-KannLab/BrainIAC](https://github.com/AIM-KannLab/BrainIAC))
  ships the preprocessing notebook — mirror that locally so our T1Prep
  outputs can be resampled/cropped to their 128³ grid for apples-to-apples.
- Does DLBS release on OpenNeuro include defaced T1s only? Check whether
  BrainIAC prep was run pre- or post-deface.
- T1Prep's `--bids` mode should handle DLBS as-is; confirm on one subject
  before scaling.

## Layout

Work under `comparison/` (to be created):

```
comparison/
  README.md              # this file (once expanded)
  env/                   # conda/uv env pins, container recipe
  scripts/               # DLBS fetch, T1Prep launcher, BrainIAC prep mirror
  slurm/                 # sbatch wrappers for DGX Spark
  notebooks/             # eval notebooks, plots
  results/               # metrics tables, no raw data
```

Raw DLBS stays under `/data/raw/` or `/data/datasets/`; only code +
aggregated results go in the repo.
