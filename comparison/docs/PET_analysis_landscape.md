# DLBS PET analysis — tool landscape and recommended pipeline

DLBS PET inventory: **551 amyloid scans (18F-AV45 / florbetapir)** across all 3 waves
plus **184 tau scans (18F-AV1451 / flortaucipir)** at waves 2–3. Reference region
for SUVR is whole cerebellum (per the DLBS README).

The dataset already ships pre-computed SUVRs in `derivatives/brainsummary/`:
`Template17_Amyloid.xlsx` (8 cortical regions averaged into a global SUVR)
and `Template18_Tau.xlsx` (Jack 2018 temporal meta-ROI). Those are useful
baselines but use only 8–6 regions of a manual atlas. Our re-processing
goal is **per-FreeSurfer-region SUVR with partial volume correction**, plus
joint biophysical modelling against ASL/CVR (vpjax-augmented).

## Tool review

### Tier 1 — segmentation-PVC pipelines

| Tool | Affil. | Status | Strength | Weakness |
|---|---|---|---|---|
| **PETSurfer** (`mri_gtmpvc`, `mri_gtmstats`) | FreeSurfer (Greve) | shipped in our `medarc-smri-fm:latest` container via `freesurfer-python_8.2.0` | One-shot from `recon-all`, GTM matched to FS aparc, default for many ADNI sites | Only GTM PVC; tied to FS atlas |
| **PETPVC** (Thomas 2016) | Inst. of Nuclear Medicine, UCL | open BSD | **7 PVC algorithms** (GTM, Müller-Gärtner, RBV, IY, RL, MTC, LR); cross-validated | Needs manual ROI mask + coreg upstream |
| **PETPrep** (BIDS app) | Stanford/Levitas | alpha @ 2026 | BIDS-native, wraps ANTs + PETPVC + FS | Alpha; pinned versions |

### Tier 2 — kinetic / Bayesian (beyond static SUVR)

| Tool | Strength | Use for DLBS |
|---|---|---|
| **niftypet** (Markiewicz) | Differentiable Bayesian kinetic models in Python+CUDA — natural upstream of vpjax | Bridge to `vpjax.metabolism` (CMRO2-coupled SUVR). |
| **OpenMIAKAT** | SRTM/Logan for AV1451 + AV45 reference-tissue modelling | Tau Logan-plot for waves 2/3. |
| **AmyPET** (Markiewicz 2024) | Centiloid-aligned amyloid pipeline | Cross-cohort amyloid harmonisation if we ever join DLBS to ADNI/A4. |

### Tier 3 — harmonisation / cross-cohort

| Tool | Use |
|---|---|
| **Centiloid project** (Klunk 2015) | Convert AV45 SUVR → 0–100 Centiloid scale. Useful for any future ADNI/A4 comparison. |

## Recommended DLBS pipeline (composing strengths)

```
1. FastSurfer/SynthSeg parcellation (we have this for 23 subj)
2. PETSurfer gtmseg → GTM segmentation matched to FS atlas
3. mri_coreg: PET → T1 (rigid, within-subject)
4. PETPVC --pvc all → run all 7 PVC algorithms, save under -pvc-{gtm,mg,rbv,...}
5. SUVR per FS region (cerebellum reference) → wide parquet
6. niftypet: Bayesian Logan plot for tau (AV1451), uses ASL-derived CBF as prior
7. (vpjax) joint amyloid+CMRO2 model (Fick's principle): SUVR_AV45 ~ f(CMRO2, age, APOE)
```

This gives:
- a **per-region SUVR parquet** (same schema as our morphometry parquets) for ridge/concat experiments
- **PVC-method ablation** (7 algorithms × 23 subjects × 3 waves = ~480 scan-method outputs)
- **vpjax biophysical readout** for the methodology paper

## Why vpjax matters for PET (not just CVR)

PET SUVR is a static measurement that hides three vascular dependencies:

1. **Tracer delivery is rate-limited by CBF**. High-CBF regions (DMN, motor strip)
   receive more tracer per unit time. Standard PVC corrects for tissue volume but
   not delivery flux. A `vpjax.perfusion`-derived per-region CBF map lets us
   scale the GTM kernel by delivery, not just by anatomy.
2. **AV1451 (tau) off-target binding** to vascular neuromelanin is a known
   confound. CVR maps from Hypercapnia BOLD (`vpjax.hemodynamics.inversion`)
   disambiguate true tau signal from vascular signal.
3. **Amyloid–CMRO2 coupling** (Vaishnavi 2010, Sperling 2009): the default-mode
   network's high baseline metabolism predicts amyloid deposition. With ASL-CBF
   + Hypercapnia-OEF → CMRO2 (`vpjax.metabolism.fick`), we can fit
   `SUVR_AV45 ~ CMRO2_baseline + age + APOE` as a *biophysical* model rather than
   a regression.

## Practical next step

Add a `petsurfer_dlbs.sh` script (PETSurfer wrapper) — uses our existing
medarc-smri-fm image since it ships freesurfer-python — and a sibling
`petpvc_dlbs.sh` (containerised PETPVC) so both pipelines run on the same
23 subjects and we can compare PVC-method effects on the downstream ridge.
