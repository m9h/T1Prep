# Switching DLBS to Oxford's MMORF + OM-1 template

## What's wrong with the status quo

We currently register every DLBS T1 to **MNI152NLin2009cAsym** (Fonov 2011),
either inside MedARC's pipeline.py (ANTs SyN rigid + nonlinear) or inside
BrainIAC's preprocessing (SimpleITK rigid → temp_head atlas) or inside
T1Prep (deepmriprep linear → fixed warp). All three target a 2009-vintage
template derived from ~150 young-adult MNI scans.

This biases everything that follows:

- **Cohort mismatch**: DLBS is 21–89 yr, mean ~55. MNI152's 19–48 yr
  mean ~25 distribution under-represents older brains, so warp residuals
  are systematically larger for our cohort.
- **Tissue boundaries**: SyN/FNIRT optimise mutual information on T1
  alone — they ignore T2/FLAIR/DWI even when those modalities are present
  (DLBS has all three).
- **Per-subject inconsistency**: each tool brings its own atlas + warp
  — directly comparing volumes across FastSurfer/SynthSeg/T1Prep is
  noisier than it should be.

## What MMORF + OM-1 buys

**MMORF** (Multimodal Multiscale Registration Framework, Andersson & Smith
2024, FMRIB) is a recent FNIRT replacement that:

- Optimises a **joint** T1 + T2 + FA cost function in one pass.
- Uses a **multi-scale bspline** parameterisation — fewer parameters, better
  regularisation, ~2× faster than ANTs SyN at comparable Dice.
- Has a closed-form Jacobian, which means it slots into JAX/PyTorch
  pipelines cleanly (the source isn't JAX yet, but the API is amenable).

**OM-1** (Oxford-Multimodal-1) is the new template that ships with MMORF:

- Built from **~50 000 UK Biobank scans** via MMORF averaging — much closer
  to DLBS's age distribution than MNI152's young-adult basis.
- Multimodal: includes T1, T2, FA, MD, V1 (DTI primary direction) — so
  DWI registration uses the same target atlas as T1.
- Released under the FSL licence (free for non-commercial; matches our
  current FSL usage at `~/fsl`).

## Concrete improvements to scope for DLBS

| Current | After MMORF/OM-1 |
|---|---|
| MedARC pipeline.py: SynthStrip + ANTs SyN → MNI152NLin2009cAsym | Same SynthStrip + **MMORF nonlinear → OM-1**, joint T1+T2+FA cost |
| FastSurfer's seg in `orig` space | Add an OM-1-warped version of the parcellation for cohort-level stats |
| BrainIAC preprocessing → temp_head | Replace temp_head with **OM-1 1 mm** as the moving target — matches the rest of the pipeline |
| FDT outputs (FA/MD per-subject) | **MMORF FA-driven warp** instead of separate ANTs registration; aligns DWI atlas with T1 atlas |
| Group-level brain-age ridge | Re-fit on OM-1-warped features to test cohort-template effect |

## Scaling claim to verify on DLBS

Andersson & Smith 2024 report MMORF ~2× faster than SyN with ~5–10%
higher Dice on cortical/subcortical labels for older adults. We can
test this directly: re-register a 5-subject pilot to OM-1 vs MNI152,
compare runtime + Dice on FreeSurfer aparc as the gold standard.
~1 hour of compute.

## Implementation cost

- **MMORF binary**: ships with FSL 6.0.7+. Already on host at `~/fsl/bin/mmorf`
  (GPU + `mmorf_cpu` + `mmorf_cuda11.0` variants).
- **arm64**: no special build; FSL conda-aarch64 includes MMORF.
- **OMM-1 template**: ✅ **acquired** (1.2 GB at
  `/home/mhough/fsl/data/standard/oxford-mm-templates/Oxford-MM-1/`).
  Includes T1 brain+head, T2-FLAIR brain+head, full DTI tensor (FA / MD /
  L1-3 / V1-3 / MO / skeleton / masks), QSM, and **bidirectional warps to
  MNI152NLIN6Asym** at `transformations/{MNI152NLIN6Asym_to_OMM-1,OMM-1_to_MNI152NLIN6Asym}_warp.nii.gz`.
  Also `Oxford-MM-0` (the unbiased prequel) for reference.
- **Script changes**: replace template path in MedARC pipeline.py + our
  brainiac_preprocess.py + add an MMORF wrapper. ~1 day of work.
- **Backwards compat**: keep MNI152 outputs alongside OMM-1 outputs so we
  can ablate the template choice in the paper. Pre-computed warps make
  cross-template comparison a single `applywarp` call per scan.

## Why this is a defensible Sophont contribution

MedARC's smri-fm currently locks in MNI152NLin2009cAsym in
`pipeline.py:_get_default_template_brain()`. Switching to OM-1 (a) modernises
the template to a 50K-scan UKB-derived reference, (b) makes downstream
multimodal joint warps possible (T1+T2+FA), (c) lines up with the FOMO26
challenge's expected biobank-scale evaluation distribution. PR-able.

## Open questions before we commit

1. Does OM-1 ship a brain mask + standard atlases (aparc, AAL, Schaefer)?
2. Is MMORF deterministic enough for longitudinal comparisons (within-subject
   warp consistency across waves)?
3. How does it interact with our SynthSeg + ICV-norm pipeline — does the
   cerebellum reference for SUVR shift?
