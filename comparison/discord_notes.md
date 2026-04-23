# MedARC Discord extract — smri-fm project

Source: MedARC Discord `#neuro-fm` + `#looking-for-projects`, April 8–13, 2026.
Lead: **Connor**.

## Core links

- **Notion project page** (auth'd, editable): <https://www.notion.so/Structural-MRI-foundation-model-33c82b7aafbc80debda9cc64203a0095>
- **GitHub**: <https://github.com/MedARC-AI/smri-fm> (cloned to `/home/mhough/dev/smri-fm`)
- **HF dataset**: <https://huggingface.co/datasets/medarc/smri-fm>
  - DLBS mirror: <https://huggingface.co/datasets/medarc/smri-fm/tree/main/datasets/DLBS>
- **First merged PR** (openneuro curation + metadata): <https://github.com/MedARC-AI/smri-fm/pull/1>
- **Data-curation notebook**: <https://github.com/MedARC-AI/smri-fm/blob/main/datasets/openneuro/scripts/data_curation.ipynb>
- **Bethlehem 2022 "Brain charts" + lifespan links gdoc**: <https://www.nature.com/articles/s41586-022-04554-y>
- **Kickoff meeting**: April 9, 2026, 11:30 AM (auto-adjusted), <https://meet.google.com/hys-etkg-dmk>

## Papers shared in-channel

| Source | Paper | Relevance |
|---|---|---|
| Mihir | [npj Digital Medicine — 3D SSL framework](https://www.nature.com/articles/s41746-025-02035-w) | Generalisable 3D SSL for medical imaging |
| Mihir | [arXiv 2509.10620](https://arxiv.org/html/2509.10620v1) | (unread — to review) |
| Paul | [MR-RATE VLM dataset](https://huggingface.co/datasets/Forithmus/MR-RATE) ([tweet](https://x.com/forithmus/status/2034238396944531525)) | Text + brain/spine MRI VLM with HD-BET prep |
| Paul | [Bethlehem 2022, Brain charts for the human lifespan (*Nature*)](https://www.nature.com/articles/s41586-022-04554-y) | **Morphology-baseline reference** |
| Tanishq | [arXiv 2604.08537](https://arxiv.org/abs/2604.08537) — Meta-learning in-context for brain decoding | Cross-subject brain decoding |
| Connor | [Nebius enroot+pyxis docs](https://nebius.com/docs/compute/solutions/running-jobs-in-containers-by-using-enroot-and-pyxis) | Slurm + docker on the MedARC cluster |

## Project-shaping decisions

1. **Pretraining on OpenNeuro.** Connor: "OpenNeuro should have enough for pretraining by itself (~80k images). Using openneuro for pretraining will be neat — very diverse and fully open." **Pretraining is native-space with minimal preprocessing.**
2. **Curated OpenNeuro stats (post-filter):** 939 datasets / **39,143 subjects** / **64,287 images** (T1w 51,591 + T2w 9,159 + FLAIR 3,537).
3. **Filter criteria:** file size 1–60 MB; min voxel ≥ 0.3 mm; in-plane (X, Y) ≤ 1.5 mm; Z ≤ 3 mm; axis length 120–260 mm.
4. **Brain-age eval holdouts:** **ds004856 (DLBS)** and **ds003592 (Spreng "Neurocognitive aging data release")**.
5. **Initial evals beyond openneuro:** HCP-A / AABC and ADNI (Mihir). All others can wait.
6. **Preprocessing pipeline (from `preprocessing/pipeline.py`, actual code):**
   1. Reorient to RAS (nibabel `as_closest_canonical`).
   2. **SynthStrip** skull strip (`mri_synthstrip`) — Connor accepted Mihir's proposal to swap out HD-BET; both remain "on the table."
   3. Resample to 1 mm iso (ANTs, bSpline for image, NN for mask).
   4. `apply_mask_and_clip` (clip negatives from bspline overshoot).
   5. **Rigid registration to `MNI152NLin2009cAsym`** (ANTs, Rigid).
   6. `apply_mask_and_clip` again post-warp.
   7. Save preproc volume + brain mask + `.mat` transform.
7. **N4 bias correction is NOT currently in the pipeline** (Connor said "we should run n4+rigid reg first before synthseg" — either added after the snapshot or still TBD; check notion).
8. **SynthSeg morphology baseline (from `parse_synthseg_volumes`):** the five Bethlehem 2022 headline metrics — **GMV, WMV, sGMV, VentCSF, TCV** — plus DK-parcellation ROI volumes (34 regions × L/R aggregated), plus QC scores per structure. Explicit comment: *"VentralDC deliberately excluded from sGMV per Bethlehem 2022."*
9. **Compute stack:** Slurm cluster with enroot + pyxis for Docker. GPU for SynthStrip + SynthSeg; CPU-only path for registration.
10. **The thesis Connor stated explicitly:** *"you have to compare any FM with simple brain morphology baselines. Features like total gray matter volume are highly correlated with age."* SynthSeg regional volumes are the planned baseline.
11. **Connor's aspirational deliverable:** "UMAP embedding of all available human brains."

## Task assignments (as of 2026-04-13)

| Owner | Task | Status |
|---|---|---|
| Connor | OpenNeuro curation + metadata, pipeline scaffolding | PR #1 merged |
| Rohit (Ahmed Anas?) | Minimal preprocessing pipeline, SynthSeg docker/slurm | SynthSeg working on 1 sample; batch + PR pending |
| Mihir | HCP-A / AABC and ADNI pull; SynthSeg on HCPA | HCPA synthseg done (pre-QC); ADNI upload in progress |
| asharya | 2 lit-review papers | Will post to Notion, travelling |
| Jeremy | BraTS 2023 (UKBB was closed-access) | New to project |
| Chris Liu | (NeurIPS submission; returning) | — |

## What this means for our branch

MedARC's baseline is **SynthSeg regional volumes → ridge brain age**. That's exactly the Bethlehem-flavoured morphology baseline Connor says the FM has to beat. Two things SynthSeg *doesn't* give them, both of which **T1Prep does**:

1. **Cortical thickness** (per DK region, from CAT-Surface pial/white reconstruction). Thickness is an independent axis of age-related change; volume+thickness models routinely beat volume-only.
2. **Voxel-wise VBM Jacobian from nonlinear MNI warp** (whereas the MedARC pipeline stops at rigid). The literature has decades of evidence that nonlinear-warp-Jacobians add brain-age signal over regional volumes.

Our repositioned pitch: **T1Prep supplies the "strong" morphology baseline** (SynthSeg volumes + thickness + Jacobian + ROI thickness) that the FM actually needs to beat to justify itself. If it does, FM wins. If it doesn't, we've sharpened the benchmark for the whole sMRI-FM community.

Tertiary value: T1Prep's full nonlinear MNI output could also serve as an **input variant** for FM pretraining (closer to what BrainIAC uses) as a preprocessing ablation.

## Additional Discord activity 2026-04-21 → 2026-04-22

- **PR #3 — "Add registration preprocessing" by @clane9** merged to
  `MedARC-AI/smri-fm`. Key finding: **naive SimpleITK rigid
  registration is unreliable, ANTs rigid works.** Our MedARC-grace
  Dockerfile already uses ANTs — consistent.
  Contribution pattern: fork → `experiments/<name>/` → PR.
- **Nima preprocessed 100 DLBS images with BrainIAC pipeline.**
  Inference predictions concentrate in a narrow younger age band —
  **BrainIAC underpredicts age on DLBS elderly cohort.** First
  sign of domain-shift issue with BrainIAC on DLBS.
- **Nima ran ridge on Mihir's SynthSeg outputs** (71 ICV-normalised
  features) — **MAE 6.66 yr, RMSE 8.27, R² 0.779, r 0.883, bias
  −0.10 yr on 100 DLBS**. No bias-correction applied. This is
  rung 1 of our four-rung ladder, already done.
- **Mihir flagged bias-correction question** to Nima — Cole / Zhang
  age-level is the standard fix, we've already written this up.
- **Dojo completed FOMO-defaults pretraining**. Connor wants
  embeddings from Dojo's checkpoint + FOMO25 pretrained baseline
  computed on all DLBS, coordinated with Nima for age eval.
  Embedding save format: `sub-XXX_ses-waveN_acq-MPRAGE_run-1_embeds.npy`
  or HF arrow.

## FOMO25 architecture (from jbanusco/fomo25 repo)

- `MultiModalUNetVAE` (mmunetvae), 3D U-Net + VAE on Yucca framework.
- Input: 96×96×96 patches (divisible by 8), 4×4×4 MAE mask unit.
- Preprocessing: skull-strip → RAS → 1 mm iso → **z-norm per volume**
  → bounding-box crop.
- Trained on FOMO-60K (11,187 subjects, 100 epochs).
- Public Docker: `jbanusco/sslmmunetave:1.0.0`.
- Paper: Gordaliza, Banus et al. arxiv 2601.13166 — *Won MICCAI 2025
  SSL3D + FOMO25*. U-Net CNN 10× smaller and 1-2 orders faster than
  transformer competitors.

**Key implication for MedARC:** their Cortex-MAE heritage is
transformer-based; FOMO25 shows U-Net MAE wins on the current
challenges. Worth raising Thursday.

## Immediate next steps (our side)

- [x] Finish DLBS sync (2026-04-22).
- [x] Finish Spreng sync (2026-04-22).
- [ ] Fix T1Prep case-sensitivity bug (rebuild in flight).
- [ ] Smoke-test T1Prep on sub-1003 ses-wave1 once rebuild lands.
- [ ] Reproduce Nima's 71-feature SynthSeg + ridge baseline locally —
      this is rung 1 of our four-rung ladder.
- [ ] Build FastSurfer VINN rung on DLBS (rung 3).
- [ ] Build T1Prep thickness+Jacobian rung on DLBS (rung 4).
- [ ] Pull `jbanusco/sslmmunetave:1.0.0`, write embedding-extraction
      script compatible with their expected preprocessing.
- [ ] Write matched embedding-extraction for BrainIAC (Nima's
      pipeline so we can reproduce her predict-young finding).
- [ ] Get Dojo's checkpoint URL.
- [ ] Plan embedding save format: decide `.npy` per subject vs HF
      arrow. Probably HF arrow for MedARC consistency + smaller
      index.
- [ ] Plan contribution back to `MedARC-AI/smri-fm` as
      `experiments/multi-fm-dlbs-morphometry-benchmark/` PR.

## User's arm64 neuroimaging stack (mhough/neurofedora COPR)

Confirmed 2026-04-22. The user maintains
[`mhough/neurofedora`](https://copr.fedorainfracloud.org/coprs/mhough/neurofedora/)
— a 68-package arm64 + x86_64 fedora-43 neuroimaging stack. Most
relevant packages for this project:

| Package | Purpose | Useful for |
|---|---|---|
| `freesurfer` | FreeSurfer 8.2.0-7.fc43 (building 2026-04-22) | MedARC-arm Dockerfile unblock, FastSurfer recon-surf on Spark |
| `ANTs` / `ANTs3` | Registration | MedARC pipeline rigid MNI, T1Prep deps |
| `afni` | fMRI suite | Arm-side fMRI QC |
| `mrtrix3` | Diffusion | DWI if we expand to multimodal |
| `niftyreg`, `elastix`, `greedy`, `c3d`, `cmtk`, `plastimatch` | Classical registration variants | Tier-3 benchmark (multiple reg tools) |
| `InsightToolkit5`, `InsightToolkit6` | ITK | base for all of the above |
| `python-samseg` | Bayesian joint bias+seg | Tier-1 rung 5 candidate |
| `python-surfa`, `python-simpleitk`, `python-nilearn`, `python-fmm3dpy` | Python deps | our evaluation notebooks |
| `simnibs`, `python-charm-gems` | TMS/TES head-modelling | future-work |
| `bart` | MRI reconstruction | future-work |
| `laynii` | laminar analysis | future-work |

**Parallel distribution paths.** The user maintains **both** arm64
stacks:

1. **Fedora / RPMs** via `mhough/neurofedora` COPR (above).
2. **Debian / .debs** for NeuroDebian — arm64 .debs visible under
   `/home/mhough/dev/debian/` (ITK 5.4.5, mcx, drviewer,
   caterpillar, fmm3dpy, ANTs source, …).

Both are proof-of-concept demonstrations that the stack builds on
arm64; we consume them via containers rather than host-native
installs. Container base choice determines which path:

- **`FROM fedora:43` → COPR** (`dnf copr enable mhough/neurofedora`).
- **`FROM ubuntu:24.04` or NGC** → NeuroDebian arm64 .debs (matches
  MedARC's original base lineage more closely — their upstream
  Dockerfile is ubuntu-under-freesurfer/freesurfer:7.4.1).

Dockerfile.medarc-grace is currently fedora-base; we can swap to
ubuntu+NeuroDebian if we prefer to stay closer to MedARC's published
base image without losing reproducibility.
