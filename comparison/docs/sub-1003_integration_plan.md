# sub-1003 — full multimodal SOTA integration

Canonical pilot subject for the DLBS multimodal pipeline. Once this subject
runs end-to-end through every tool with the file layout below, scaling to
the other 22 subjects is mechanical.

Why sub-1003: complete coverage across T1×3 / T2×3 / DTI×3 / ASL×2 /
Hyp×3 / rest×5 / Scenes×9 / Words×3 / VV×4 / amy-PET×3 / tau-PET×1, and
already pre-processed by FastSurfer / T1Prep / MedARC SynthSeg / BrainIAC.
Longitudinal trajectory: ages 54 → 58 → 63 yr.

## Canonical output tree

```
/data/datasets/smri-fm-cmp/integrated/ds004856/sub-1003/
├── manifest.json                              # tools × sessions × status
├── ses-wave1/
│   ├── anat/
│   │   ├── fastsurfer/                        # already done
│   │   ├── t1prep/                            # already done (cross-sectional)
│   │   ├── synthseg/                          # already done (MedARC pipeline.py)
│   │   ├── brainiac_preproc.nii.gz            # already done
│   │   ├── fsl_anat/                          # NEW: FSL fsl_anat one-shot
│   │   ├── mmorf_om1/                         # NEW: MMORF → OM-1 warp
│   │   └── sienax/                            # NEW: brain volume + atrophy
│   ├── dwi/
│   │   ├── eddy/                              # NEW: topup + eddy (replaces eddy_correct)
│   │   ├── dtifit/                            # already done (re-run on eddy output)
│   │   ├── bedpostx/                          # NEW: crossing-fiber model
│   │   ├── xtract/                            # NEW: standardised tract atlas
│   │   └── tbss/                              # NEW: per-subject FA in standard space
│   ├── func/
│   │   ├── rest/
│   │   │   ├── melodic.ica/                   # already done
│   │   │   ├── fix/                           # NEW: ICA-based denoising
│   │   │   └── networks.tsv                   # 7-network parc time series
│   │   ├── Scenes/{feat_run-1,feat_run-2,feat_run-3}/   # NEW: FEAT GLM
│   │   ├── Words/feat_run-1/                  # NEW
│   │   ├── VentralVisual/{feat_run-1,feat_run-2}/      # NEW
│   │   └── Hypercapnia/
│   │       ├── mc/                            # cvr_vpjax_dlbs.sh pre-stage
│   │       ├── cvr_map.nii.gz                 # OLS β
│   │       └── balloon_params.json            # vpjax inversion
│   ├── perf/
│   │   └── oxford_asl/                        # already done (ses-wave1, ses-wave3 only)
│   └── pet/
│       ├── amyloid_18FAV45/
│       │   ├── coreg/                         # mri_coreg PET → T1
│       │   ├── petsurfer_gtm/                 # gtmseg + mri_gtmpvc + mri_gtmstats
│       │   └── petpvc_{gtm,mg,rbv,iy,rl,mtc,lr}/  # 7 PVC algorithms
│       └── tau_18FAV1451/                     # ses-wave2 + ses-wave3 only
├── ses-wave2/  # same structure
├── ses-wave3/  # same structure
├── features/
│   ├── morphometry.parquet                    # already exists at top level — symlink in
│   ├── diffusion.parquet                      # FA/MD/L1 per FS region + tract metrics
│   ├── perfusion.parquet                      # CBF per region from oxford_asl
│   ├── cvr.parquet                            # %BOLD/Δstim + Balloon params per region
│   ├── fmri_task.parquet                      # zstat per (task, condition, region)
│   ├── fmri_rest.parquet                      # network features (e.g., 7-network FC)
│   ├── pet_amyloid.parquet                    # SUVR per region × PVC method × wave
│   ├── pet_tau.parquet                        # SUVR per region × PVC method × wave
│   └── joint.parquet                          # everything merged on (sub, ses, region)
└── cognition/
    └── sub-1003.parquet                       # behavioural scores + survey + demographics
```

## Per-tool SOTA targets (FSL where applicable, our existing pipelines otherwise)

| Domain | Tool | Status | Notes |
|---|---|---|---|
| **T1 morph (deep)** | FastSurfer VINN | ✅ done | aseg+DKT.VINN.stats |
| | T1Prep | ✅ done | thickness/area/tissue parquets |
| | SynthSeg via MedARC pipeline.py | ✅ done | 60-row volumes parquet |
| | BrainIAC | ✅ done | 768-d embeddings parquet |
| **T1 morph (FSL)** | `fsl_anat` | ❌ todo | BET + FAST + FIRST + FNIRT one-shot; FSL-native baseline |
| | **SIENAX** + **SIENA** | ❌ todo | per-wave brain vol + longitudinal atrophy |
| **Multimodal warp** | **MMORF → OM-1** | ❌ todo | replaces ANTs SyN; multimodal cost (T1 + T2 + FA) |
| **Diffusion** | `eddy` + `topup` (NO topup data: PE single-direction → use `eddy --data_is_shelled`) | ❌ todo | replaces our current `eddy_correct` |
| | DTIFit (re-run on `eddy` output) | ⚠️ partial | currently from `eddy_correct` → re-run |
| | **bedpostx_gpu** | ❌ todo | crossing fibers |
| | **xtract** | ❌ todo | standardised tract atlas via probtrackx2 |
| | **TBSS** | ❌ todo | per-subject skeleton FA in standard space |
| **fMRI rest** | MELODIC (single-subj ICA) | ✅ done | 81 ICs |
| | **FIX** | ❌ todo | needs a trained classifier (.RData); pulled from `~/fsl/data/fix/` |
| | Network parcellation | ❌ todo | dual_regression vs Yeo-7 ROI mean time series |
| **fMRI task** | FEAT GLM (per task × run) | ⚠️ scaffold | `tcsh` now installed; need to fix `.fsf` template error |
| | randomise (group, but per-subject useful for permutation null) | ❌ todo | |
| **ASL** | oxford_asl + fabber Bayesian | ✅ done | sub-1003 ses-wave1 + ses-wave3 (no wave2) |
| | + `--fslanat` GM partial-volume correction | ⚠️ partial | will be cleaner once `fsl_anat` is done |
| **CVR** | mcflirt + bet + OLS β | ⚠️ scaffold | `cvr_vpjax_dlbs.sh` pre-stage written; need to run |
| | vpjax Balloon-Windkessel inversion | ⚠️ scaffold | `cvr_vpjax_invert.py` written; need vpjax `pip install -e .` |
| **PET amyloid** | mri_coreg + gtmseg + mri_gtmpvc + mri_gtmstats (PETSurfer) | ❌ todo | uses our medarc-smri-fm container's freesurfer-python |
| | PETPVC (7 algorithms) | ❌ todo | |
| **PET tau** | same | ❌ todo | ses-wave3 only |
| **Cognition + surveys** | pandas → parquet | ❌ todo | flatten the XLSX files into a per-subject row |

## File-management rules

1. **No tool writes outside its own subdir under the canonical tree.** Scripts read
   from raw `/data/raw/openneuro/ds004856/sub-1003/...` and from upstream tool
   outputs they explicitly depend on (e.g., PETSurfer needs FastSurfer).
2. **Existing outputs symlink in, not copy.** FastSurfer/T1Prep/SynthSeg/BrainIAC
   already live at `/data/datasets/smri-fm-cmp/{fastsurfer,t1prep,medarc-smri-fm,brainiac-preproc}/`;
   the canonical tree symlinks rather than duplicates GB-scale outputs.
3. **Every tool emits a parquet feature file** under `features/<modality>.parquet`.
   Schema: `subject, session, acq, run, tool, region, value` (long format,
   matches our existing `fastsurfer_features.parquet`).
4. **Joint parquet** is the merge of all feature parquets on (subject, session, region).
   Used by ridge/concat/multivariate analyses.
5. **One manifest.json at subject root** records per-tool × per-session status:
   `{started_at, finished_at, exit_code, output_paths[]}`. Idempotency check.
6. **Per-tool runner is a single shell script** under
   `comparison/scripts/integrated/`, e.g. `eddy_topup_sub1003.sh`. The
   orchestrator `run_sub1003_full.sh` calls them in dependency order.

## Dependency order (determines what we can run when)

```
raw T1 → fastsurfer / t1prep / synthseg / brainiac_preproc / fsl_anat
              ↓                                                ↓
              + brain mask                                 fast tissue seg
                                                                ↓
fmt:  raw T2  → fsl_anat (T2 channel)                                         
                                                                ↓
raw DTI → eddy_correct/eddy → dtifit → bedpostx → xtract → TBSS
                              ↓
                              MMORF (uses FA + T1 jointly)
raw rest BOLD → melodic → FIX → networks
raw task BOLD → mcflirt → FEAT (per task)
raw Hyp BOLD → mcflirt → CVR-OLS + vpjax Balloon inversion
raw ASL → oxford_asl (with fsl_anat GM mask)
raw PET → mri_coreg(→T1) → PETSurfer + PETPVC (per algorithm)

cognition/surveys/demographics XLSX → pandas → cognition parquet
```

## Validation gates per tool (before scaling)

- **FA mean in mask** ∈ [0.18, 0.35] for healthy adults — sub-1003 already passes (0.27, 0.26, 0.25 across waves).
- **CBF mean in cortex** ∈ [40, 70] mL/100g/min — to be checked from oxford_asl output.
- **MELODIC IC count** > 30 (auto-dim) — sub-1003 ses-wave1 has 81. ✓
- **PETSurfer global SUVR**: amyloid global SUVR ∈ [0.9, 1.4] for healthy older adults; tau temporal-meta SUVR ∈ [1.0, 1.5].
- **CVR map**: median %BOLD/Δstim ∈ [0.05, 0.30] in GM.
- **Balloon params**: κ ∈ [0.3, 2.0], γ ∈ [0.1, 1.0] (vpjax bounds).

## What I will NOT do

- Run any of the missing tools at scale across other subjects until all of
  the above lands cleanly for sub-1003 and you've reviewed the output tree
  + parquets.
- Touch existing outputs that already work (FastSurfer / T1Prep / SynthSeg /
  BrainIAC / oxford_asl / MELODIC / FDT). They symlink in as-is.

## Next concrete steps (one at a time, with checkpoint)

1. Create `comparison/scripts/integrated/` + the canonical tree for sub-1003.
2. Write `manifest_helpers.py` (read/write per-subject manifest).
3. Wire the existing 6 outputs (FastSurfer, T1Prep, SynthSeg, BrainIAC,
   oxford_asl, MELODIC, FDT) as symlinks into the canonical tree + populate
   manifest.
4. Write the missing per-tool runners in dependency order:
   a. `fsl_anat_sub1003.sh`     (gates everything FSL-anat-dependent)
   b. `eddy_sub1003.sh`         (replaces eddy_correct in dwi/)
   c. `mmorf_om1_sub1003.sh`    (after fetching OM-1 template)
   d. `feat_sub1003.sh`         (fix tcsh .fsf template)
   e. `cvr_sub1003.sh`          (run our existing scaffold)
   f. `petsurfer_sub1003.sh`    (PET amyloid + tau)
   g. `petpvc_sub1003.sh`       (7-algorithm PVC ablation)
   h. `bedpostx_xtract_sub1003.sh`
   i. `tbss_sub1003.sh`
   j. `fix_sub1003.sh`          (needs trained classifier — fetch first)
   k. `sienax_siena_sub1003.sh`
5. Per-tool feature extractor: `extract_<modality>_features.py` → parquet.
6. `joint_features_sub1003.py` → merge all into `joint.parquet`.
7. **Checkpoint**: review tree + parquets together before any scale-out.
