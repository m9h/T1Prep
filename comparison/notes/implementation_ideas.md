# Implementation ideas for smri-fm

Brainstormed for the Thursday 2026-04-23 meeting. Focus: novel-but-
actionable proposals that are achievable inside the project's scope and
each addresses a specific weakness in the current plan (rigid-only prep,
SynthSeg-volume-only baseline, naive SimCLR-style SSL).

Ordered by **impact × feasibility**, most "bring this" at the top.

---

## 1. Run SSL pretraining in T1Prep's nonlinear MNI space, not rigid MNI

**What**: add a second preprocessing variant to the training corpus —
T1Prep's nonlinear-warped MNI volumes (CAT12 Shoot) — and pretrain a
sibling FM on it. Evaluate whether nonlinear-MNI pretraining helps
downstream brain age beyond rigid-MNI.

**Why it matters**: the BrainIAC-lineage decision to use rigid-only
registration was a compute/simplicity trade-off, not a correctness
decision. Nonlinear warp aligns cortex across subjects, which means
the FM's learned features are no longer confounded by individual
gyrification. Every classical VBM paper since 2001 rests on this.

**Feasibility**: the T1Prep container already exists (once we fix
the perms bug). Piggybacks on existing dataset, just a second
preprocessing pass. Compute cost ≈ one extra training run.

## 2. N4 + SynthSeg as an explicit ablation arm

**What**: actually implement Connor's 04-13 proposal as a dedicated
arm, not just a hypothetical. Run N4 upstream of SynthSeg on a dev
subset (say DLBS wave 1) and compare tissue-volume concordance +
downstream brain-age MAE.

**Why it matters**: SynthSeg is trained to be bias-robust by domain
randomisation, so adding N4 upstream might hurt (double-correction)
or help (some biases are outside SynthSeg's training distribution).
Nobody has published this specific comparison.

**Feasibility**: one-afternoon experiment. Drops a clean table into
the preprocessing section of the paper.

## 3. Cortical-surface tokenisation for the FM

**What**: instead of (or alongside) tokenising via 3D voxel patches,
sample tokens on the cortical surface — use CAT-Surface / FastSurfer
central-surface mesh, sample intensity and thickness at surface
vertices, flatten to a 1D token sequence per hemisphere.

**Why it matters**: voxels waste capacity on non-brain and on
bulk white matter; the anatomy-dense, variance-dense region is the
cortex ribbon. Surface tokenisation has been done for parcellation
(e.g. SpecFormer 2023) but never for an sMRI foundation model.

**Feasibility**: CAT-Surface already produces `.gii` meshes per
subject. Vertex sampling is standard nibabel. Tokenisation is a
shuffle + pool step. Would need a small surface-MAE variant of the
architecture, but the heavy lifting (decoder, loss) is standard.

## 4. Longitudinal-pair contrastive / flow-matching objective on DLBS waves

**What**: use DLBS's 338 subjects-with-2-waves and 224 subjects-with-
3-waves as **within-subject positive pairs** during SSL pretraining.
Force the FM's embedding to be stable up to age-progression; use
flow matching or velocity-based contrastive to learn the aging
trajectory as a vector field in feature space.

**Why it matters**: every FM to date is trained on cross-sectional
data. Longitudinal data is rare and expensive. DLBS is one of the
few truly longitudinal lifespan sets now publicly available, and it's
already in MedARC's plan as a holdout. Using it for pretraining
(carefully, leaving the age-prediction eval untouched) would be a
genuinely novel contribution.

**Feasibility**: moderate. Requires restricted-pair sampling
scheduler; needs DLBS in training set (currently held out, so this
would require either HCP-A longitudinal pairs or adding a
second longitudinal cohort). Discuss trade-offs.

## 5. Extend AnatCL with Bethlehem + longitudinal supervision

**What**: AnatCL (Barbano et al. 2024, `github.com/EIDOSLAB/AnatCL`)
already does anatomical-metadata-supervised SSL on sMRI — weakly
contrastive on age + DK cortical thickness + GMV + surface area.
2.61 yr MAE on OpenBHB with only 3,984 training subjects. Our
extension: (a) replace AnatCL's raw DK-region anatomical labels
with **Bethlehem 2022 lifespan-chart percentiles** (age-and-sex
conditioned norms, not raw values), (b) add **longitudinal-pair
positives** from DLBS / HCP-A so the FM explicitly learns the aging
trajectory, (c) scale from 4 k to 48 k+ training subjects to match
BrainIAC's budget and see if anatomical supervision scales.

**Why it matters**: Vidal-Piñeiro showed cross-sectional brain-age
gap is a pre-existing-condition marker, not an aging-rate marker.
A normative-chart-anchored + longitudinal-aware FM natively
separates "where on the chart" from "how fast aging" — exactly the
distinction AnatCL+Bethlehem+DLBS supplies.

**Feasibility**: moderate. AnatCL code exists; extending it to
Bethlehem targets is one loss-function change plus a normative-chart
regression head. Longitudinal-pair sampler is a dataloader change.
Scaling to 48 k is the compute-heavy step.

## 6. Multi-modal pretraining with MultiMAE-style masking

**What**: pretrain on T1 + T2 + FLAIR jointly (they're all in the
openneuro curated set — T1w 51k, T2w 9k, FLAIR 3.5k per Connor's
04-13 metadata). Use the MultiMAE recipe: mask one modality, predict
it from the others. Validate against UK Biobank and ADNI multimodal
subsets.

**Why it matters**: most sMRI FMs are T1-only. T2 and FLAIR carry
complementary pathology signals (edema, WMH, iron). Multi-modal
pretraining gives a single backbone that generalises across the three
clinical sequences.

**Feasibility**: MultiMAE is public. The dataset has all three
modalities labelled via SynthSeg's sequence classifier. Main cost
is compute for a larger model.

## 7. Native-space + explicit rigid-transform conditioning

**What**: skip rigid-to-MNI registration during pretraining. Feed
native-space volumes + the 4×4 rigid-to-MNI matrix as a conditioning
token (or as a positional-embedding modifier). The FM sees raw-space
data but knows where it is in standard coordinates.

**Why it matters**: forces the FM to be geometry-aware rather than
assuming template-aligned input. Cleaner mental model of "intrinsic"
vs "pose" features. Also dodges registration-failure modes in
non-standard acquisitions.

**Feasibility**: straightforward — ANTs rigid output already
provides the matrix. Tokenisation of a 4×4 is trivial.

## 8. ConvNeXt-3D or hybrid backbone instead of pure ViT

**What**: benchmark a 3D ConvNeXt (Liu 2022) or a hybrid (CNN stem +
ViT trunk) against a pure 3D ViT on the same SSL objective + dataset.
BrainIAC is ViT-only; nobody has published a head-to-head for brain
MRI.

**Why it matters**: 3D medical data has strong locality priors that
convolutions exploit natively. ViTs make up for it with scale, but
at 50k images the scale advantage of ViT over ConvNeXt is empirically
small. Could save 10× compute for matched performance.

**Feasibility**: ConvNeXt-3D implementations exist (nnU-Net v2 has
one). Drop-in backbone swap within the same training loop.

## 9. Diffusion-pretraining as an alternative SSL objective

**What**: train a 3D latent diffusion model on the same corpus (VQ-
GAN 3D → DDPM). Use the diffusion-model encoder as the foundation
model. Compare to SimCLR / MAE heads.

**Why it matters**: diffusion encoders capture low-level structure
and generate new brains — useful for data augmentation (synthetic
balancing of under-represented age/sex combinations). Riffusion /
MedicalSD-style.

**Feasibility**: high up-front compute but an entire second axis of
downstream utility (generation, inpainting for artefact removal,
counterfactual generation). Probably too ambitious for first
MedARC release but worth naming as a future direction.

## 10. Downstream benchmark expansion

**What**: beyond the 2–3 tasks MedARC is likely to target, curate a
benchmark suite: brain age (DLBS, Spreng), MCI (ADNI), WMH load
(MRI-ISIL), sex classification (UK Biobank), total intracranial
volume, parkinson's (PPMI), autism (ABIDE), schizophrenia (COBRE).
Wrap as a single evaluation script.

**Why it matters**: BrainIAC used 7 tasks; MedARC should aim for 10+
to be the new standard benchmark. A benchmark suite also de-risks
overfitting to brain age (which is mostly GMV-driven and easy).

**Feasibility**: moderate — data acquisition is the bottleneck for
MCI/PD/schizo. Can start with the public ones (age, WMH, sex, ABIDE).

---

## Ranked one-sentence pitches (for the meeting, pick 2–3)

- *"Let me run T1Prep nonlinear-MNI preprocessing on DLBS; we can
  ablate SSL-on-rigid vs SSL-on-nonlinear as a preprocessing arm."*
- *"Here's a four-rung classical morphometry baseline so the FM has
  an ablation ladder: SynthSeg → SynthSeg+N4 → FastSurfer VINN →
  T1Prep thickness+Jacobian."*
- *"DLBS has 224 three-wave subjects — let me prototype a flow-
  matching longitudinal-pair SSL head as a research spike."*
- *"We should condition pretraining on age + Bethlehem normative
  charts so the FM natively separates 'where on the chart' from
  'how fast aging'."*
