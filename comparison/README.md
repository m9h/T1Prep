# T1Prep vs. MedARC sMRI-FM / BrainIAC / FOMO25 on the Dallas Lifespan Brain Study

Branch: `smri-fm-dlbs-comparison`
Started: 2026-04-21, active 2026-04-22.

**Quick status (2026-04-22):**

- DLBS + Spreng OpenNeuro syncs complete (243 GB + 111 GB).
- Three reproducible arm64 Docker images built locally:
  `fastsurfer-grace:6b6b985` (seg_only, GB10), `t1prep-grace:v0.3.3`
  (full CAT12-lineage), MedARC `medarc-grace` Dockerfile skeleton
  pending FreeSurfer-arm COPR.
- Smoke test on DLBS sub-1003 ses-wave1: FastSurfer 164 s ✓,
  T1Prep 329 s ✓. Matched-pair concordance analysis now possible.
- Longitudinal fan-out on waves 2 + 3 running in background.
- FOMO25 `mmunetvae` image pulled (`jbanusco/sslmmunetave:1.0.0`,
  amd64-only, routes to Legion). Base image for the FOMO FM arm.
- Fork of `MedARC-AI/smri-fm` at `m9h/smri-fm` branch
  `dlbs-morphometry-benchmark` set up with experiment scaffold at
  `experiments/dlbs_morphometry_benchmark/` (README + notebook
  skeleton + stats parser). Not pushed yet.
- Meeting Thursday 2026-04-23 11:30 eastern. See
  `notes/medarc_meeting_thu.md`.

This sub-project evaluates where [T1Prep](https://github.com/ChristianGaser/T1Prep)
— the Python/C successor to CAT12 — fits in the preprocessing stack that the
new generation of structural-MRI foundation models are being built on, using
the [Dallas Lifespan Brain Study (DLBS)](https://openneuro.org/datasets/ds004856)
as the benchmark cohort.

## Context

- **MedARC `smri-fm`** is a community sMRI foundation-model project, kicked
  off April 9, 2026 by Connor and collaborators. Active
  [GitHub repo](https://github.com/MedARC-AI/smri-fm) (cloned locally to
  `/home/mhough/dev/smri-fm`), [HF dataset](https://huggingface.co/datasets/medarc/smri-fm),
  [Notion tracker](https://www.notion.so/Structural-MRI-foundation-model-33c82b7aafbc80debda9cc64203a0095).
  Curated OpenNeuro training corpus is **939 datasets / 39,143 subjects /
  64,287 images** (T1w 51,591 + T2w 9,159 + FLAIR 3,537).
  See [`discord_notes.md`](discord_notes.md) for the full extract of
  decisions, assignments, and links.
- **MedARC's actual preprocessing pipeline** (from
  `smri-fm/preprocessing/pipeline.py`):
  RAS reorient → SynthStrip (with HD-BET as an alternative) → 1 mm iso
  resample → rigid ANTs register to `MNI152NLin2009cAsym` → clip. Then
  SynthSeg (`--parc --robust`) on the preprocessed output, yielding 33
  whole-brain regions + 34 DK cortical regions per hemisphere and five
  Bethlehem-aligned summary metrics **(GMV, WMV, sGMV, VentCSF, TCV)**.
  N4 bias correction currently not in the code (may be added).
- **Brain-age holdouts** selected by the project: **ds004856 (DLBS)** and
  **ds003592 (Spreng "Neurocognitive aging")**. Both flagged because of
  clean age-distribution coverage.
- **BrainIAC** (AIM-KannLab, *Nat. Neurosci.* 2026;
  [repo](https://github.com/AIM-KannLab/BrainIAC)): SimCLR ViT pretrained on
  ~48.5 k scans across 35 datasets (**DLBS is included**). Minimal prep:
  dcm2nii → N4 (SimpleITK) → 1 mm iso → **rigid** MNI → HD-BET → crop 128³.
  Closely parallels the MedARC pipeline; MedARC swaps HD-BET → SynthStrip
  and adds SynthSeg-derived volume baselines.
- **DLBS** (Park et al., *Sci. Data* 2025): 464 → 338 → 224 subjects over
  three waves (≈ 4–5 yr spacing), Philips 3T Achieva, T1 + fMRI + ASL + DTI,
  plus AV-45 and AV-1451 PET. Released on OpenNeuro 2025.
- **T1Prep**: DeepMriPrep skull-strip + bias correction, AMAP tissue
  segmentation, CAT-Surface cortex + thickness, nonlinear MNI152
  registration, BIDS-compatible outputs.

## Why T1Prep, specifically, against this backdrop

Connor has stated the project's explicit position: *"you have to compare any
FM with simple brain morphology baselines — features like total gray matter
volume are highly correlated with age."* Their planned baseline is
**SynthSeg regional volumes → ridge brain age**, using the Bethlehem 2022
five-metric summary.

Two things SynthSeg volumes do *not* capture, both of which T1Prep
supplies natively:

1. **Cortical thickness** per DK region (from CAT-Surface pial/white
   reconstruction). Thickness is an independent axis of age-related change
   from volume; thickness + volume models consistently beat volume-only on
   brain age \citep{vidalpineiro2021,more2023}.
2. **Voxel-wise VBM Jacobian from nonlinear MNI warp.** The MedARC
   pipeline stops at rigid registration. A nonlinear-warp Jacobian map
   encodes local volume change that categorical segmentations cannot.

The re-scoped contribution of this branch is therefore:

> **T1Prep supplies the strong morphology baseline the MedARC sMRI-FM must
> beat.** If the FM beats volume + thickness + Jacobian, that is a
> meaningful win. If it only beats volume alone (SynthSeg), the field has
> not actually learned whether the FM captures anything beyond well-known
> morphology.

A secondary angle: T1Prep's nonlinear MNI output could serve as an
alternative preprocessing input for FM pretraining, as a preprocessing
ablation.

## The question we actually want to answer

The sMRI-FM effort rides on a decade-old debate: **do we actually need deep
networks on raw T1 volumes, or does ridge regression on classical
morphometric features match them for brain-age prediction?** The debate has
never been fully settled — and it is the right lens to judge whether a
foundation model trained on minimally-processed volumes adds value over a
T1Prep-feature + ridge baseline.

See [`paper/brain_age_history.tex`](paper/brain_age_history.tex) for the
longer-form history; the short version follows.

## A brief history of brain-age prediction

### 1. Origins (Franke 2010, Cole 2010s)

Brain age started with Katja Franke and Christian Gaser's 2010 paper
(*NeuroImage*) using relevance vector regression on VBM-preprocessed T1s —
i.e. on **CAT12-style features**, the same family T1Prep emits. Error on
healthy adults sat around 5 years MAE. James Cole et al. then popularised
the paradigm through the 2010s: Gaussian Process Regression on grey-matter
volumes ([brainageR](https://github.com/james-cole/brainageR)), and later a
3D CNN on raw T1s (Cole et al. 2017, *NeuroImage*) that pushed UKBiobank MAE
toward 4 years. The narrative hook — "brain-predicted age difference" (BAG,
also PAD / brain-PAD) as a biomarker of accelerated aging — was set by Cole
and colleagues and drove the field's growth.

### 2. The deep-learning plateau (Peng 2021, SFCN)

Peng et al.'s SFCN (*MedIA* 2021) is the canonical result: a lightweight 3D
fully-convolutional net with **soft-label KL-divergence loss** (Gaussian-
smoothed age targets) achieved **2.14 yr MAE on UKB** and won the 2019
Predictive Analysis Challenge. Crucially, the paper itself admits that
**linear regression post-hoc bias correction maintains state-of-the-art
performance**, and that with only ~50 training subjects the deep model only
narrowly beats classical regression. The ceiling for deep models on single-
site healthy cohorts has not meaningfully moved since.

### 3. The ridge-regression counter-narrative

A parallel literature has kept showing that **ridge / kernel ridge /
elastic-net on morphometric features is surprisingly hard to beat**:

- **Lombardi et al. (2021)**: ridge regression on FreeSurfer features,
  2.7 yr MAE — within noise of the best CNNs of the era.
- **More et al. (2023, *NeuroImage*)**: systematic comparison across
  algorithms — kernel ridge / Gaussian process regression on
  morphometric summaries was competitive with, and more reproducible than,
  deep learning across datasets.
- **Dular & Špiclin / Bashyam et al. / Couvy-Duchesne et al.**: similar
  conclusions in multi-site / transfer settings.

The consistent finding: **on healthy adult cross-sectional data, the
ceiling is set by label noise and site effects, not by model capacity**.
Classical features win on compute, interpretability, and often on
generalisation.

### 4. The bias / regression-dilution problem

A regression-to-the-mean artefact — **over-prediction of young subjects,
under-prediction of old ones** — has dogged every brain-age model ever
published. Whether this is "real bias" or the correct Bayesian behaviour
of a regressor under noisy labels is philosophically contested, but the
practical corrections cluster into three families:

- **Cole correction** (Smith et al. 2019; de Lange & Cole 2020):
  regress predicted age ŷ on chronological age y, then apply
  ŷ_corr = (ŷ − β) / α.
- **Beheshti correction**: regress PAD = ŷ − y directly on y.
- **Zhang et al. 2023 "age-level bias correction"**: local z-scoring at
  each age, PAD_ac = (PAD − μ_a) / σ_a, because global linear corrections
  leave systematic within-age residuals.
- **Smith et al. (UKBiobank lifestyle paper)**: include age and age² as
  covariates in every downstream association.
- **Treder et al.**: correlation-constrained loss at training time.

de Lange, Cole et al.'s **"Mind the gap"** (*HBM* 2022) is the canonical
review — and warns that if BAG is used naively as a regressor/response
without a correction, *any* association with a phenotype can arise purely
from the age-dependence of the residual.

### 5. The longitudinal challenge (Vidal-Piñeiro 2021)

Vidal-Piñeiro et al. (*eLife* 2021) deliver the most uncomfortable finding
in the field: **cross-sectional BAG is essentially uncorrelated with the
rate of within-subject brain change over time**. A "high BAG" mostly
indexes early-life/developmental differences (birth weight, PGS),
not accelerated aging. This is precisely why a **longitudinal** dataset
like DLBS — three waves per returning subject — is the right place to
stress-test any new FM-derived brain-age.

### 6. The foundation-model era (2024–2026)

- **BrainIAC** (*Nat. Neurosci.* 2026): SimCLR on 32 k scans, validated on
  seven downstream tasks including brain age, MCI classification, IDH
  mutation, and survival. Brain-age MAE comparable to supervised 3D CNNs
  but with one-shot transfer to the other six tasks — the first credible
  "generalist" argument for sMRI.
- **MedARC `smri-fm`**: evidently a community replication / extension.
  Test-set release first.
- Open questions the field has *not* yet settled for the FM generation:
  1. Does FM-embedding + ridge beat T1Prep-feature + ridge on brain age?
     If not, the FM value proposition is elsewhere (transfer, rare tasks).
  2. Does the FM inherit the same regression-dilution bias? Early signs
     say yes — the bias is baked into the label distribution, not the
     representation.
  3. Is the FM longitudinally stable? No published longitudinal
     evaluation exists at the time of writing.

## What we are doing here

Four arms on DLBS (+ ds003592 for external generalisation):

1. **MedARC baseline — SynthSeg volumes + ridge.** Run
   `smri-fm/preprocessing/pipeline.py` on DLBS T1s, extract the
   Bethlehem-style five metrics (GMV/WMV/sGMV/VentCSF/TCV) and the 34×2 DK
   ROI volumes, fit ridge brain age. This is the project's stated baseline.
2. **T1Prep morphology+ — volumes + thickness + Jacobian + ridge.** Run
   T1Prep on the same T1s. Features: SynthSeg-style tissue volumes (from
   T1Prep's own AMAP segmentation), DK ROI cortical thickness, coarse
   Jacobian summary, intracranial volume. Same ridge head.
3. **FM + ridge.** Whatever foundation-model checkpoint MedARC publishes
   (or BrainIAC if sooner), frozen backbone, ridge head on the embeddings.
4. **Longitudinal stability (Vidal-Piñeiro test).** For every arm, test
   whether ΔBAG across DLBS waves correlates with ΔT1Prep features within
   subject. This is the experiment the FM literature has not yet run.

All arms use identical bias correction (Cole/Smith, Beheshti, Zhang
age-level) so MAE comparisons are apples-to-apples. External validation
on ds003592 (Spreng).

## Layout

```
comparison/
  README.md                    # this file
  discord_notes.md             # MedARC Discord extract (tasks, links, decisions)
  paper/
    main.tex                   # eventual paper draft
    refs.bib                   # BibTeX
  scripts/                     # (TBD) fetchers, T1Prep + MedARC pipeline wrappers
  slurm/                       # (TBD) DGX Spark sbatch wrappers (enroot+pyxis)
  notebooks/                   # (TBD) eval notebooks
  logs/
    dlbs_sync.log              # OpenNeuro → /data/raw/openneuro/ds004856
  results/                     # (TBD) metrics tables only, no raw data
```

Sibling reference repo (read-only, upstream MedARC): `/home/mhough/dev/smri-fm/`.

Raw DLBS lives under `/data/raw/openneuro/ds004856/` (sync in progress,
~243 GB, 29 k objects). Only code and aggregated results go in this repo.
Second holdout `ds003592` (Spreng) to be synced separately.
