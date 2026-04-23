# Brain-age foundation-model landscape as of 2026-04-21

Compiled for Thursday MedARC meeting. Short answer to "does James Cole or
anyone else have another FM for brain age?":

**Cole himself — no new FM.** `brainageR` (Gaussian Process regression on
VBM features) and `PyBrainAge` (Python port) are his current public
releases. He's a UCL professor and still publishes clinical-application
papers but has not released his own foundation-model-sized system.

**Others, yes — at least four serious contenders besides BrainIAC.**

## Foundation-model-scale systems (2025–2026)

### 1. BrainIAC (AIM-KannLab, *Nat. Neurosci.* 2026)

- SimCLR contrastive SSL, 3D ViT backbone.
- 32,000 MRIs pretraining / 48,519 validation across 35 datasets.
- 7 downstream tasks including brain age.
- Preprocessing: N4 + 1 mm iso + rigid MNI + HD-BET + crop to 128³.
- Weights on Dropbox, non-commercial academic licence.
- No MedARC comparison in the paper.

### 2. AnatCL (Barbano et al. 2024, arxiv 2408.07079)

**This one is directly relevant to our meeting positioning.**

- Weakly-supervised contrastive SSL with **anatomical metadata
  as supervision**: cortical thickness + GMV + surface area per
  DK region, plus age (y-Aware loss).
- Two variants: local (per-region) and global (whole-brain).
- 3D ResNet-18 backbone (ResNet-50 doesn't improve).
- Training: OpenBHB 3,984 HC images, much smaller than BrainIAC.
- Brain age MAE **2.61 years** on OpenBHB — competitive with
  supervised SOTA despite the small pretraining set.
- 12 diagnostic + 10 phenotype downstream tasks.
- Code + weights: `github.com/EIDOSLAB/AnatCL`.

**Why relevant:** my "idea 6 — age-conditioned pretraining with
normative-chart anchors" partially reimplements what AnatCL already
does. To be a real contribution we'd need to extend AnatCL with:
(a) Bethlehem lifespan chart percentiles as the anatomical anchor
(vs. raw DK thickness/GMV in AnatCL), (b) longitudinal-pair positives
from DLBS, or (c) scale to 48k+ images to match BrainIAC's training
budget and see if AnatCL's anatomical supervision wins at scale.

### 3. OpenMAP-BrainAge (Kan, Jones, Oishi — JHU, arxiv 2506.17597)

- Transformer with stem-and-trunk design, pseudo-3D multiview
  (sag/cor/ax) + volumetric features from 280 brain regions.
- **Trunk pretrained on 52 robotic-proprioception/vision datasets**
  (NOT a brain-specific SSL corpus — they use a general-purpose
  pretrained vision trunk). Unusual choice that works.
- Training: 2,064 CN subjects from ADNI2&3 + OASIS3 (4,630 scans).
- MAE **3.65 yr** on ADNI+OASIS, **3.54 yr** on AIBL external.
- BAG correlates with MoCA/MMSE in MCI/AD groups.
- Code `github.com/pkan2/OpenMAP-BrainAge`; **no pretrained weights
  released**.

**Why relevant:** their "use a non-brain pretrained trunk" result
is a useful data point for MedARC. If a robotic-vision trunk works
this well, does an ImageNet-scale 3D ViT trunk pretrained on any 3D
medical data beat it?

### 4. MedARC `smri-fm` itself (the project we're joining)

- Currently in preprocessing / data-curation phase
- Plans to train an open sMRI FM on 64 k openneuro images + HCPA +
  ADNI + others
- Brain age is on the downstream list
- Architecture / SSL objective not yet decided (that's Thursday's
  fourth-and-later meeting agenda)

### 5. Brain Harmony (MedARC collaborators, NeurIPS 2025)

- Multimodal FM unifying morphology + function into 1D tokens
- sMRI + fMRI both
- This is the MedARC group's prior published work
- Brain age is one of the evaluated tasks but not the headline

### 6. MultiModalUNetVAE / mmunetvae (Gordaliza, Banus et al., MICCAI 2025)

- Arxiv 2601.13166 (Jan 2026). Won FIRST PLACE in both
  MICCAI 2025 **SSL3D** and **FOMO25** brain-MRI FM challenges.
- Architecture: **3D U-Net + VAE** (not a transformer).
- Pretraining: MAE-style on **FOMO-60K** (11,187 subjects, 100 epochs).
- Input: 96×96×96 patches, 4×4×4 mask unit, z-normalised per volume,
  bounding-box cropped post-skull-strip.
- **10× smaller and 1-2 orders of magnitude faster than competing
  transformer-based entries.**
- Public release: [`jbanusco/fomo25` v1.0.0](https://github.com/jbanusco/fomo25/releases/tag/v1.0.0),
  Docker `jbanusco/sslmmunetave:1.0.0`.
- Built on the [Yucca](https://github.com/Sllambias/yucca) framework.

**Why it shifts the MedARC conversation:** MedARC's prior
Cortex-MAE is transformer-based. FOMO25 demonstrates a U-Net MAE at
similar or better performance, much cheaper. The default sMRI-FM
architecture choice should not be assumed-ViT; a U-Net ablation is
cheap and has a strong prior now.

## Not foundation models, but the canonical supervised benchmarks

- **SFCN (Peng 2021)** — 2.14 yr UKB MAE, the supervised high-water
  mark with ~50M params on 3D T1. Still the reference everyone
  compares to.
- **brainageR (Cole)** — GPR on VBM features, MAE ~4 yr.
- **Bashyam 2020** — DenseNet-based, 14k subjects, wide cohort.
- **Lombardi 2021** — ridge on FreeSurfer features, 2.7 yr MAE.
  The canonical "classical beats deep" data point.
- **brain-PAD DeepLabV3 variants** for localised brain age.

## Architecture comparisons — "Do Transformers and CNNs Learn Different Concepts of Brain Age?"

Gijsen et al. 2024, *Human Brain Mapping* 10.1002/hbm.70243
(PMC12147945). ResNet50 vs SwinT vs sViT on **46,381 UK Biobank T1s**:

- ResNet50: **2.66 yr** MAE on held-out.
- SwinT: **2.67 yr** MAE — essentially identical.
- SwinT degrades faster with small training sets, but **power-law
  extrapolation predicts SwinT surpasses ResNet above ~25 k samples.**
- Open question whether CNN and transformer features represent
  *different* age-relevant concepts (title).

Implication for MedARC: below 25 k, CNN is as good and more
data-efficient; above 25 k, the scaling argument favours ViT/Swin.
MedARC's 64 k-image pretraining corpus sits above the crossover.

## The accuracy-vs-disease-detection paradox — Schulz, Siegel & Ritter 2025, *PLOS Biology*

**"Brain-age models with lower age prediction accuracy have higher
sensitivity for disease detection"** (pbio.3003451).

- Ridge regression (1,400 params) beats CNN (46.2M) and SwinT
  (10.1M) on **patient-vs-control effect size**, despite being
  worse at age MAE.
- Accuracy-optimised models pick features with "high SNR for age
  and low residual variability" — the wrong features for disease.
- Over-regularised models default to global measures (total GM
  volume, ICV) — which happen to track widespread pathology.
- Held across training-set sizes, random seeds, training epochs.

**This reframes the entire FM value proposition.** If brain age is
the North Star and an FM beats ridge on age MAE, Schulz says the FM
is *worse* for disease detection. The FM's only honest value
proposition is:
- Transfer to **rare / low-label** tasks (what BrainIAC actually
  demonstrated across 7 tasks).
- Harder-to-predict phenotypes (cognitive scores, clinical
  trajectories, genetics).
- **NOT** beating classical baselines on brain age.

## Bringing to Thursday

- *"Schulz et al. (2025, PLOS Biol) show Ridge-on-morphometry beats
  deep networks on disease-detection effect size even when it loses
  on age MAE. Our benchmark should include disease effect-size
  alongside MAE, otherwise we're optimising the wrong thing."*
- *"Beyond BrainIAC, AnatCL (OpenBHB, 2.61 yr) is the direct
  competitor for anatomical-supervision SSL. We should benchmark
  against it, and the natural extension is Bethlehem-chart +
  longitudinal-pair supervision."*
- *"OpenMAP-BrainAge got 3.65 yr MAE from a robotic-vision
  pretrained trunk. DINOv3 or SAM-3D as our backbone initialiser
  is a cheap win."*
- *"Gijsen et al. 2024 HBM: ResNet50 and SwinT tie at ~2.66 yr on
  46 k UKB, SwinT scales better above 25 k. Our 64 k corpus is
  past the crossover; ViT/Swin is defensible but ResNet is the
  data-efficient fallback for ablations."*

## Cortex MAE — MedARC's prior art

"Next steps post cortex-MAE" in the 2026-04-02 meeting agenda refers
to MedARC's own prior model, published in
[`MedARC-AI/fmri-fm`](https://github.com/MedARC-AI/fmri-fm):
- ViT-B MAE, 89M params, patch sizes 16×16 and 16×2.
- Pretrained on HCP-YA + NSD cortex-flattened fMRI
  (`medarc/hcp-flat-wds`, `medarc/nsd-flat-wds` on HF).
- "Cortex MAE" = cortical-flat-map MAE for fMRI.

**Implication**: `smri-fm` is very likely going to be an **MAE**
(not SimCLR or contrastive) — Connor's group has muscle memory on
MAE. That's a strong prior when proposing architectures.

## What this means for the meeting

1. **BrainIAC is not the only game.** AnatCL specifically pushes the
   "anatomical supervision makes the FM better" thesis — close to
   what I was about to propose as novel. Frame our idea as
   "extend AnatCL with Bethlehem + longitudinal," not "invent
   anatomical-supervision SSL."
2. **OpenMAP shows a non-brain pretrained trunk can be competitive.**
   Strong argument for starting MedARC from a pretrained vision
   backbone (DINOv3 or SAM-3D) rather than from scratch.
3. **MedARC has a ready story beyond BrainIAC.** Brain Harmony is
   theirs; smri-fm is the unimodal continuation. Positioning should
   emphasise "we benchmark against AnatCL and OpenMAP, not just
   BrainIAC," otherwise reviewers will ask.
4. **Classical still competitive.** Lombardi ridge-on-FreeSurfer at
   2.7 yr and AnatCL at 2.61 yr are in the same range as supervised
   SFCN (2.14 yr). The FM value add has to be in rare tasks or
   low-label transfer, not brain-age ceiling.

## Bringing to Thursday

- *"Beyond BrainIAC, AnatCL (OpenBHB, 2.61 yr brain age MAE) is the
  direct competitor for anatomical-supervision SSL. We should
  benchmark against it, and the natural extension is Bethlehem-chart
  + longitudinal-pair supervision."*
- *"OpenMAP-BrainAge got 3.65 yr MAE from a robotic-vision
  pretrained trunk. If they can do that, using DINOv3 or SAM-3D as
  our backbone initialiser is a cheap win."*
