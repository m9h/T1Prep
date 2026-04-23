# Complete multimodal analysis of DLBS sub-1003 — plan

A single-subject stress test of the full pipeline stack across all DLBS
modalities and all three waves. Serves three purposes at once:

1. **End-to-end infrastructure proof** — every tool, every container,
   every bind-mount exercised on real data before we scale.
2. **Longitudinal multimodal ground truth** — a rich feature set per
   subject-wave that we can use to evaluate the FM.
3. **Sharpest possible FM evaluation frame**: *"how much of what the
   full multimodal stack tells us about this subject can the FM
   recover from T1 alone?"* Strongest lever for the paper if the FM
   wins, clearest honest statement of limits if it doesn't.

## Subject profile

- **sub-1003**: male, 54 / 58 / 63 at MRI (9-yr span), MMSE 28 → 30 →
  28, 15 yr education, right-handed, BMI 31.9 → 33.5.
- Cognitive-change slopes already computed in participants.tsv:
  CogW1→W2 = 3.93, CogW2→W3 = 5.27, CogW1→W3 = 9.21 (larger = more
  decline).
- No tau PET in wave 1 (only wave 2+3).

## Modalities × tools × hosts

Per wave; three waves → 3× this table.

| Modality | Files | Tool (primary) | Tool (baseline) | Host | Status |
|---|---|---|---|---|---|
| T1w MPRAGE | 1 | T1Prep (arm64) | FastSurfer seg (arm64) | Spark | FastSurfer ✓ on w1; T1Prep rebuild in flight |
| T1w + T2w-FLAIR | +1 FLAIR | WMH-SynthSeg or TrueNet | — | Spark | not yet run |
| T1w (MedARC) | same | MedARC pipeline | — | Spark (when FS-arm lands) | blocked on FS-arm |
| fMRI 4-task + rest | 21 files | fMRIPrep + xcp_d | — | **Legion (x86)** | not started |
| DWI DTI | 4 | QSIPrep + QSIRecon | — | Legion (QSIPrep is x86 official) | not started |
| ASL pCASL | 3 | ASLPrep | — | Legion (arm build status unknown) | not started |
| PET AV-45 | 2 | petprep_hmc + SUVR pipeline | — | Legion | not started |
| PET AV-1451 | 2 (w2+) | same | — | Legion | not started |

All derivatives land under
`/data/datasets/smri-fm-cmp/<tool>/ds004856/sub-1003_ses-waveN/`
following BIDS derivatives, so PyBIDS can index across modalities.

## Feature matrix we want

Per subject-wave, a single JSON line / parquet row with:

```
subject, session, age_mri, sex, mmse, cog_slope_w1w2, cog_slope_w2w3,
# T1 morphometry — three tool variants
t1_fastsurfer_aseg_dkt_vol_<ROI>, …,
t1_t1prep_thickness_<ROI>, t1_t1prep_jacobian_<ROI>,
t1_medarc_synthseg_vol_<ROI>, …,
# WMH
wmh_total_volume, wmh_per_region,
# fMRI
rsfmri_connectivity_<network_pair>, rsfmri_alff, rsfmri_reho,
task_activation_scenes_<ROI>, task_activation_words_<ROI>,
# DTI
dti_fa_<tract>, dti_md_<tract>,
# ASL
cbf_mean_gm, cbf_mean_wm, cbf_<ROI>,
# PET
amyloid_suvr_global, amyloid_suvr_<ROI>,
tau_suvr_global, tau_suvr_<ROI>,
# FM (later)
fm_embedding_dim0, …, fm_embedding_dimD
```

## Execution order (cheapest to most expensive)

1. **T1 three-tool ladder** (today → tomorrow).
   - FastSurfer (done on w1; run w2 + w3).
   - T1Prep (all three waves once rebuild with chown lands).
   - MedARC (waits on FS-arm from other agent).
2. **WMH** via WMH-SynthSeg on Spark. Small TF model, arm-compatible.
3. **fMRI preprocessing** via fMRIPrep on Legion. Longest single run
   (~6-10 h per session with 4 tasks + rest). Can we start this
   tonight on Legion while Spark handles T1.
4. **DWI preprocessing** via QSIPrep on Legion. 2-4 h per session.
5. **ASL via ASLPrep** on Legion. 1-2 h per session.
6. **PET SUVR** — petprep_hmc + SPM or FreeSurfer mri_coreg for
   PET→T1 coreg. Legion. 30-60 min per PET per session.
7. **Merge & feature table** — Python script consuming BIDS
   derivatives, PyBIDS indexing, emit parquet.

Wall-clock for all three waves through all modalities: probably
24-48 h elapsed across both hosts running in parallel, well under
one week.

## What this gets us that the smri-fm project doesn't

MedARC smri-fm is strictly structural. A multimodal demo on one
DLBS subject gives us:

- **FM information-content test.** If the FM embedding can predict
  ASL CBF / PET amyloid / DTI FA from T1 alone, that's a very strong
  claim about how much the structural compartment encodes about the
  rest. (It probably can't, but the magnitude of the gap is the
  finding.)
- **Structural-only age vs multimodal age.** Compare brain-age MAE
  using T1 features only (three tools) vs combined-modality features
  (ridge across everything). If multimodal barely beats T1-only,
  supports the FM's design bet. If multimodal crushes T1-only, the
  FM needs multimodality to compete with classical pipelines.
- **Longitudinal stability across modalities.** Vidal-Piñeiro's test
  extended: does ΔBAG track Δ-other-biomarker within subject?

## Host routing summary

- **Spark (arm64)**: T1 arm (FastSurfer, T1Prep, MedARC-when-ready),
  WMH-SynthSeg, any PyTorch / TF feature-extraction on derivatives.
- **Legion (x86_64)**: fMRIPrep, QSIPrep, ASLPrep, PET preprocessing.
  FreeSurfer-native workflows stay here until their arm variants
  mature.

Shared `/data` NFS means either host sees the same derivatives tree.

## Concrete immediate next step

Today/tomorrow:

1. Fix T1Prep (rebuild in flight).
2. Run FastSurfer and T1Prep on sub-1003 all three waves.
3. Start WMH-SynthSeg on same (cheap, arm-compatible).
4. Kick off fMRIPrep + QSIPrep on Legion for wave-1 as an overnight
   job (longest tail).

Week 2:

5. Add ASL + PET.
6. Build the feature-table merger.
7. Run sub-1003 as the first row; then decide whether to scale to
   all ~200 sub-wave-1003-style subjects or keep it as a one-subject
   illustrative figure.
