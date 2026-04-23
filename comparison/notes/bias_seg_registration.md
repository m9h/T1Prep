# Bias-field correction + segmentation: methods and trade-offs

Prep for the MedARC smri-fm Thursday 11:30 meeting (2026-04-23) and as a
background brief for the paper's methods section.

## The core problem

Intensity non-uniformity ("bias field") from receive-coil sensitivity,
gradient imperfections, and B1 inhomogeneity can vary the same tissue's
intensity by 20–40% across the FOV. This breaks intensity-based
segmentation and VBM directly. The naïve pipeline — run N4 on the raw
T1, then segment — leaves residual bias because N4 has no tissue prior.

The field has converged on four distinct strategies.

## 1. Separate N4 then segment (the naïve baseline)

**Tool:** Tustison 2010 N4ITK, available in ANTs, SimpleITK, Nipype.

**How it works:** B-spline surface fit to the log-transform of the image,
iteratively sharpening the histogram via a Wiener-like deconvolution.
Completely tissue-agnostic.

**Failure modes:** Over-corrects when tissue distribution is non-Gaussian
(CSF-heavy elderly scans); under-corrects at brain edges; can eat real
tissue contrast in juvenile brains. Residual bias propagates into every
downstream step.

**Who uses it:** ANTs-based pipelines (`antsCorticalThickness.sh`), nipreps
tools like smriprep (with N4 + FAST), BrainIAC's preprocessing, and the
MedARC pipeline likely will add it (Connor said "we should run n4+rigid
reg first before synthseg" — not yet in code).

## 2. Joint bias + tissue estimation (generative unified models)

**Tools:** SPM Unified Segmentation (Ashburner & Friston 2005), FSL FAST
(Zhang 2001 HMRF-EM with bias), SAMSEG (Puonti 2016), CAT12's AMAP.

**How it works:** Alternate between (a) estimating tissue-class
probabilities given current bias and (b) estimating bias given current
class means. The generative model is:
  intensity = bias_field × sum_k (class_k_mean × class_k_probability) + noise
Maximum-likelihood or MAP over all three latent fields simultaneously.

**Why it's better than N4:** The tissue prior regularises the bias fit —
you can't over-correct CSF into grey matter because the generative model
knows CSF should have ~0 T1 intensity. The bias and segmentation become
mutually consistent.

**CAT12's AMAP variant** (Rajapakse 1997, extended in CAT12):
Hidden Markov Random Field, tissue classes Gaussian per voxel, **local**
(not global) mean/variance adaptation per neighborhood. The "local mean"
is effectively a bias estimate; the "local variance" handles partial
volume. No separate N4 pass needed — AMAP does both jobs.

## 3. Learned bias correction (deep, trained from generative-model labels)

**Tools:** DeepMriPrep (Lüdecke 2026, arxiv 2408.10656), which is what
T1Prep uses under the hood.

**How it works:** A U-Net trained to predict CAT12's bias field + tissue
maps from raw T1 in one forward pass. Training targets come from running
CAT12 on a big cohort, so it inherits CAT12's bias model at inference
time, 37× faster than the iterative optimiser.

**Trade-off:** Domain shift when test scans are far from the training
distribution (paediatrics, pathology, 7 T). Mostly fine for healthy-adult
lifespan data but worth QC.

## 4. Contrast-agnostic training (skip the problem)

**Tools:** SynthSeg (Billot 2023), SynthSR (Iglesias 2021), SynthStrip.

**How it works:** Domain randomisation at training time. Generate
synthetic bias fields, contrasts, resolutions, and artefacts during
training and force the network to produce the same output regardless.
No explicit bias correction at inference — the network is invariant to
bias by construction.

**Why MedARC chose this for seg:** SynthSeg doesn't need N4 upstream.
Their pipeline's "N4-free" default is intentional, not an oversight.
Adding N4 before SynthSeg can even hurt slightly (double-correction).

**Caveat for pretraining:** An SSL pretraining run on raw T1 has to
learn bias invariance from data itself, either by scale (lots of diverse
scans) or by bias augmentation during pretraining. This is an open
design question for smri-fm.

## DARTEL (Diffeomorphic Anatomical Registration Through Exponentiated Lie)

**Tool:** Ashburner 2007, in SPM8+. Successor: Geodesic Shooting /
`spm_shoot_` (Ashburner & Friston 2011).

**What it does:** Groupwise diffeomorphic registration of tissue
probability maps (NOT raw intensities). Parameterises the deformation as
the exponential of a stationary velocity field — guarantees
invertibility, topology preservation, zero Jacobian determinants
essentially impossible inside the brain. The warps are finer than
old-style SN or unified-segmentation's low-order nonlinear fit.

**What DARTEL does NOT do:** It does not correct bias. It consumes
already-segmented tissue-probability maps and aligns them. Bias
correction happened upstream in unified segmentation.

**Why it matters for VBM:** The Jacobian-modulated GM probability map
(GM_warped × det(J)) is the VBM regressor. If the warp has zero/negative
determinants or topology defects, VBM breaks. DARTEL/Shoot make the
Jacobian well-behaved, which is why CAT12/T1Prep can produce
publishable VBM maps.

## CAT12 end-to-end (what actually happens to a T1)

1. **SPM Unified Segmentation** for initial tissue priors + affine +
   first-pass bias.
2. **AMAP refinement** — local HMRF-EM with per-neighbourhood bias and
   variance. Produces the final 3-class tissue probability maps.
3. **Longitudinal realignment** if multi-session (CAT12 10.0+ uses
   symmetric within-subject templates).
4. **Geodesic Shooting** to a group or MNI template.
5. **Jacobian modulation** of GM TPM for VBM.
6. **Surface extraction** via the central-surface method (PBT,
   Dahnke 2012): projection-based thickness between WM and pial.
7. **ROI extraction** over Neuromorphometrics, DKT40, AAL, Hammers,
   etc., in both native and template space.

No separate N4 is ever run.

## T1Prep end-to-end

Python/C port of CAT12. Differences:

1. **Skull strip + bias + initial tissue priors**: single DeepMriPrep
   U-Net forward pass (replaces the iterative SPM/AMAP first pass).
2. **AMAP refinement** (same C code as CAT12, bundled).
3. **CAT-Surface** for pial/white reconstruction + thickness (same C
   code as CAT12).
4. **Nonlinear MNI warp** via CAT12's Shoot path.
5. **Atlas labels** on request.

No N4 here either — DeepMriPrep absorbed it.

## What MedARC's `preprocessing/pipeline.py` actually does

Real code, as of commit `fbdb1a83` (2026-04-21):

1. `nib.as_closest_canonical` — reorient to RAS.
2. `mri_synthstrip` — SynthStrip skull strip. No bias correction.
3. ANTs `resample_image` → 1 mm iso, bSpline.
4. `apply_mask_and_clip` — clip negatives from bSpline overshoot.
5. ANTs rigid registration to `MNI152NLin2009cAsym`.
6. `apply_mask_and_clip` again.
7. Output: preproc volume + mask + .mat transform.
8. Optional: `mri_synthseg --parc --robust` on the preproc volume to
   produce 33 whole-brain + 34×2 DK regions + Bethlehem-aligned
   GMV/WMV/sGMV/VentCSF/TCV summaries.

**No N4 anywhere.** SynthStrip and SynthSeg are trained bias-robust;
that's the whole argument. Discord comment by Connor on 2026-04-13
("we should run n4+rigid reg first before synthseg") suggests N4 may
be added but hasn't been yet.

## Positioning for the paper

The morphometry-baseline ladder becomes:

| Rung | Tool | Bias handling | Seg output | Thickness |
|---|---|---|---|---|
| MedARC baseline | SynthSeg (no N4) | bias-robust training | 33 regions + DK vols | ✗ |
| FastSurfer seg_only | FastSurferVINN | N4 via `orig_nu.mgz` | aseg+DKT + CerebNet + HypVINN | ✗ (no recon-surf on arm64) |
| T1Prep | DeepMriPrep + AMAP | learned (CAT12-style) + joint local | 3-class TPM + DK vols | ✓ CAT-Surface |
| + N4 variant | N4 → SynthSeg | separate N4 | same as MedARC | ✗ |

Adding the "SynthSeg with N4" variant is cheap and lets us empirically
answer Connor's proposal.
