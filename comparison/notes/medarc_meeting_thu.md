# MedARC smri-fm meeting — Thu 2026-04-23, 11:30

Anticipated discussion items based on Discord activity since kickoff
(2026-04-09), plus what's new from our side since last week.

## Likely agenda from their side

From Connor's 2026-04-13 update ("this week: lit review, datasets,
preprocessing") and Rohit + Mihir's in-progress tasks, the meeting
probably tracks:

1. **Preprocessing pipeline status**
   - Is the PR merged for Rohit's SynthSeg Docker+Slurm runner?
   - Has N4+rigid-reg been added before SynthSeg? (Connor flagged on
     04-13 but the 04-21 code doesn't have N4 yet.)
   - SynthStrip vs HD-BET — decision pending, both "on the table."
2. **Dataset status**
   - Mihir: HCP-A/AABC SynthSeg QC done? ADNI upload to R2 complete?
   - Does the curated openneuro file list still look right (939 / 39k
     / 64k images after filters)?
3. **Lit review outputs** (asharya + others, posted to Notion)
4. **Holdouts confirmed:** DLBS (ds004856) + ds003592 (Spreng).
5. **Start of model-architecture discussion?** Mihir floated scaling
   laws on structural MRI being cleaner — this is the gateway
   conversation to backbone choice.

## Questions they'll almost certainly raise

### Pipeline & preprocessing

- **Add N4 before SynthSeg or not?** SynthSeg's whole design is
  bias-robust by training; N4 may not help and can double-correct.
  Empirical decision — run both on a dev subset and compare
  downstream.
- **T2w/FLAIR multimodal handling.** SynthSeg is contrast-agnostic so
  T1+T2+FLAIR can all be fed. Registration: per-modality to MNI, or
  T1 → MNI + T2/FLAIR → T1 → MNI? Affects channel-count decisions
  for the FM backbone.
- **Intensity normalisation for FM input.** After rigid + skull strip,
  what's the intensity normalisation? Z-score per image, percentile
  clip, min-max, or none? Matters a lot for MAE/contrastive SSL.
- **Native vs template space for pretraining.** Connor wants "native
  space with minimal preprocessing" (04-08). But rigid-to-MNI-only is
  already template space at 1 mm iso. Truly native would skip the
  registration. Decide and document.
- **Crop / pad to fixed size.** BrainIAC uses 128³. The rigid-only
  MedARC output is larger (MNI full-FOV). Will the FM resample or
  crop? Affects Jacobian sensitivity.

### Modelling

- **Backbone choice.** 3D ViT (à la BrainIAC)? 3D ConvNeXt?
  SFCN-style lightweight conv? Masked 3D autoencoder vs SimCLR
  contrastive vs DINO-style teacher-student?
- **Scale target.** Mihir's scaling-law framing implies a compute-vs-
  loss plot. What's the flop budget for the "main" model? What tokens-
  equivalent is 64k 3D volumes at 128³?
- **Pretraining objective.**  
  - Masked voxel / patch reconstruction.
  - Contrastive with random augmentations (bias, intensity,
    rotation).
  - Hybrid (SimCLR + MAE).  
  BrainIAC went SimCLR. MAE is the "more visual" choice; contrastive
  keeps global coherence.
- **Augmentation strategy.** If pretraining is on rigid-only output,
  we need to bake back bias/rotation/scale into augmentations so the
  model learns robustness the preprocessing didn't provide.

### Evaluation

- **Downstream tasks beyond brain age.** BrainIAC uses 7 (age, MCI,
  IDH, stroke-time, survival, MR-sequence, tumor-seg). MedARC
  probably narrows to 2–3 for the first release.
- **Morphology baseline implementation.** Connor is firm: "you have
  to compare any FM with simple brain morphology baselines."
  SynthSeg volumes + ridge is the planned baseline. Our pitch:
  **also** include T1Prep thickness+VBM and FastSurfer DK as
  stronger baselines. Frame as "well-calibrated baseline set".
- **Bias correction of brain-age predictions.** Cole / Beheshti /
  Zhang age-level — which does the project standardise on?
  Vidal-Piñeiro longitudinal test for FM-derived BAG — proposed
  for DLBS three-wave.
- **Site / scanner confound handling.** ComBat on features, or site
  as covariate? Only matters for the downstream ridge, not the FM.

### Engineering

- **Compute budget and backend.** Their Slurm cluster, enroot+pyxis
  for Docker; our side (DGX Spark arm64) — different stacks. Who
  reproduces whose pipeline?
- **Release plan.** HF dataset + model checkpoints + training config
  + preprocessing Dockerfile. When?
- **Licensing.** OpenNeuro data is CC0 (most) but specific datasets
  have secondary DUAs. ADNI has a specific restriction on
  re-distribution.

## What we bring to the meeting (our side)

From work since last week:

1. **FastSurfer seg_only running on DGX Spark arm64.** `fastsurfer-
   grace` image built from `nvcr.io/nvidia/pytorch:24.12-py3`, 164 s
   per subject. Produces aseg+DKT + CerebNet + HypVINN, a richer
   morphometry baseline than SynthSeg volumes alone.
2. **T1Prep arm64 build on NGC PyTorch 26.03.** Thickness + VBM
   Jacobian + CAT12-lineage morphometry — the missing features
   SynthSeg doesn't give you.
3. **FreeSurfer arm64** being built via fedora COPR
   (`mhough/neurodefora`-ish — name pending) — will let the full
   MedARC pipeline run natively on arm64 once ready.
4. **DLBS + Spreng raw data sync in progress** to `/data/raw/openneuro/`.
5. **Pre-registered comparison plan** including three arms of
   classical morphometry (SynthSeg / FastSurfer / T1Prep) vs FM,
   under identical bias-correction regimes (Cole/Beheshti/Zhang).

## One specific offer for the meeting

> *"We have FastSurfer and T1Prep running on ARM64 Grace. If you want,
> we can produce the 'strong morphometry baseline' on DLBS in parallel
> with your SynthSeg baseline — four sets of features, identical bias
> correction, one ridge head per arm. This gives the FM a ladder to
> climb rather than a single floor to beat."*

Worth floating explicitly, gives the project a concrete contribution
from our end without scope overlap with what Connor/Rohit/Mihir are
doing.

## Questions we should ask them

1. **N4 decision timeline.** If they're not adding N4, that's fine;
   just want it in writing before we align baselines.
2. **Intensity normalisation for the FM input.** Affects every
   comparison.
3. **Which FM checkpoint are we benchmarking?** MedARC's own (when
   released) or BrainIAC as an interim proxy?
4. **Are they open to contributions from ARM64 side** (preprocessing
   dockerfile for arm, FastSurfer/T1Prep variants)?
5. **What's the planned release scope** — weights only, or
   weights + preprocessed features + evaluation code?
