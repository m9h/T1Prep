# sub-1003 — FreeSurfer SOTA addendum

Companion to `sub-1003_integration_plan.md`. Lists the FreeSurfer-specific
SOTA tools we should run on sub-1003 alongside FSL. FreeSurfer 8.2.0 ships
in our `ghcr.io/m9h/medarc-smri-fm:latest` container plus
`freesurfer-python_8.2.0` for the Synth* family; PETSurfer is in the same
package.

## What FastSurfer's `--seg_only` left on the table

We currently have FastSurfer **VINN segmentation only** (`aseg+DKT.VINN.stats`,
`cerebellum.CerebNet.stats`, `hypothalamus.HypVINN.stats`). That's volumes,
no surfaces. To unlock the rest of the FS ecosystem (curvature, gyrification,
sulcal depth, surface-based stats, hippocampal subfields, surface PET),
we need a full `recon-all` run. FastSurfer can also do this via
`recon_surf.sh` (FreeSurfer 7.4.1 paired in our `fastsurfer-full` arm64
container) — much faster than upstream `recon-all`, ~1-2 hr per scan vs
8-12 hr.

## FS SOTA tool inventory for sub-1003

Grouped by FS subdir / subsystem.

### Anatomical (T1 + T2)

| Tool | What it gives | Container | Runtime / scan |
|---|---|---|---|
| **`recon-all`** (or FastSurfer `recon_surf.sh`) | Full pial/white surfaces, cortical thickness, parcellation, aparc/Destrieux | medarc-smri-fm or fastsurfer-full (FS 7.4.1) | 8-12 hr (recon-all) / 1-2 hr (FS recon_surf) |
| **`recon-all -hires`** | Sub-mm-resolution surfaces if T1 is at higher res — DLBS isn't, so skip | | |
| **`segmentHA_T1`** | Hippocampal subfields (CA1, CA3, DG, ...) | freesurfer-python | 5-10 min |
| **`segmentBS`** | Brainstem nuclei (midbrain, pons, medulla, SCP) | freesurfer-python | 5 min |
| **`segmentThalamicNuclei`** | 25 thalamic nuclei (Iglesias 2018) | freesurfer-python | 5 min |
| **`mri_synthseg --robust --parc`** | 97-region volumetric seg | freesurfer-python | 1 min GPU |
| **`mri_synthstrip`** | Skull-strip | freesurfer-python | 30 s GPU |
| **`mri_WMHsynthseg`** | White-matter hyperintensities on FLAIR | freesurfer-python | 1 min |
| **`mri_synthsr`** | Super-resolution to 1 mm iso (useful for ASL upsampling) | freesurfer-python | 1 min GPU |
| **`mri_easyreg`** | Fast contrast-agnostic registration (any modality) | freesurfer-python | 30 s |
| **`fsr-coreg`** | Multi-modal coregistration (T1/T2/FLAIR/PET → reference) | FS | 2 min |

### Longitudinal stream (THE FS strength for DLBS)

sub-1003 has 3 waves at ages 54/58/63 — perfect for the longitudinal pipeline.

| Tool | What it gives |
|---|---|
| **`mri_robust_register`** | Rigid within-subject alignment across waves (median template) |
| **`mri_robust_template`** | Within-subject template construction |
| **`recon-all -base`** | Build subject-template reconstruction |
| **`recon-all -long`** | Per-time-point reconstruction using base as prior |
| **`long_mris_slopes`** | Per-vertex slope of cortical thickness over time |
| **`mri_concatenate_lta`** | Compose transformations (base→long, long→atlas, etc.) |

Output: per-vertex annual atrophy rate map.

### PET (the headline for our DLBS amyloid + tau)

| Tool | What it gives |
|---|---|
| **`gtmseg`** | Geometry-Thickness-Matched segmentation derived from `recon-all` outputs — required for PVC |
| **`mri_gtmpvc`** | Geometric Transfer Matrix PVC — corrects for spillover between regions |
| **`mri_gtmstats`** | Per-region SUVR stats with PVC-corrected values |
| **`mri_coreg`** | PET → T1 rigid coregistration (better than FLIRT for PET due to lower contrast) |
| **`mri_segstats`** | Generic per-region statistics on a PET volume + segmentation |

For sub-1003: 3 amyloid SUVRs (W1/W2/W3) + 1 tau SUVR (W3) — six PETSurfer
runs total. Pipeline: `recon-all → gtmseg → mri_coreg → mri_gtmpvc → mri_gtmstats`.

### Diffusion

| Tool | What it gives |
|---|---|
| **TRACULA (`trac-all`)** | Probabilistic tractography of 18 named tracts; uses bedpostx + atlas priors |
| **`mri_diff`** | Diffusion-anat coregistration |
| **`mri_concatenate_lta`** | Compose dMRI→T1→atlas transforms |

TRACULA outputs are the FS analogue of FSL's XTRACT — useful to run both
and compare (they use different atlas definitions).

### fMRI surface-based

| Tool | What it gives |
|---|---|
| **`mris_preproc`** | Resample volumetric stat maps onto fsaverage surface |
| **`mri_surf2surf`** | Surface-to-surface resampling (subject ↔ fsaverage) |
| **`mri_glmfit`** | Surface-based GLM (group stats on cortical maps) |
| **`mri_glmfit-sim`** | Cluster-wise correction via Monte Carlo simulation |
| **`mri_fcseed_config`** + **`mri_fcseed`** | Seed-based functional connectivity |
| **FS-FAST** | Full task-fMRI pipeline (alternative to FEAT — runs on surface) |

### White-matter / atlas integration

| Tool | What it gives |
|---|---|
| **`mri_aparc2aseg`** | Combine cortical aparc + aseg subcortical into one segmentation |
| **`mri_label2vol`** | Project surface label → volume |
| **`mri_vol2surf`** | Sample volume → surface |
| **`mris_anatomical_stats`** | Per-region cortical thickness/area/volume from surfaces |

### Quality control

| Tool | What it gives |
|---|---|
| **`recon-all-clinical.sh`** (FS 7.4+) | QC-aware fast recon for clinical scans |
| **`recon-all -qcache`** | Pre-cache surface quality measures (curvature, sulcal depth) for QA |
| **FreeView** | Interactive viewer (skip — we're headless) |

## sub-1003 specific FS plan

1. **`recon-all` (or FastSurfer `recon_surf.sh`) on each of the 3 T1s**
   - Use FastSurfer's full pipeline → `fastsurfer-full:7.4.1-*` container
   - Time: ~6 hr total for 3 sessions (FastSurfer recon_surf, GPU)
2. **Longitudinal recon stream**
   - `recon-all -base sub-1003 -tp ses-wave1 -tp ses-wave2 -tp ses-wave3`
   - `recon-all -long ses-wave{1,2,3} sub-1003 -all` × 3
   - Time: ~4 hr more for the longitudinal pass
3. **Hippocampal subfields per wave**
   - `segmentHA_T1.sh sub-1003_ses-wave{1,2,3}` × 3
4. **Brainstem + thalamic nuclei per wave**
   - `segmentBS.sh` + `segmentThalamicNuclei.sh` × 3
5. **WMH on FLAIRs**
   - `mri_WMHsynthseg --i FLAIR.nii.gz --o wmh.nii.gz` × 3
6. **PETSurfer on the 4 PET scans (3 amyloid + 1 tau)**
   - `gtmseg --s sub-1003_ses-waveN`
   - `mri_coreg --s sub-1003_ses-waveN --mov pet.nii.gz --reg pet2t1.lta`
   - `mri_gtmpvc --i pet.nii.gz --reg pet2t1.lta --psf 6 --seg gtmseg.mgz --o pvc/`
   - `mri_gtmstats --i pvc.nii.gz --seg gtmseg.mgz --o suvr.tsv`
7. **TRACULA on the 3 DTIs** (after eddy correction)
   - `trac-all -prep`, `trac-all -bedp`, `trac-all -path` × 3
8. **Surface-based fMRI**
   - `mris_preproc` for each task FEAT zstat → fsaverage surface
   - `mri_glmfit` per condition (uses sub-1003-only design matrix as a sanity check)

## Integration with the canonical tree

Add under `/data/datasets/smri-fm-cmp/integrated/ds004856/sub-1003/ses-waveN/anat/`:
```
freesurfer/                 # full recon-all output (mri/, surf/, label/, stats/)
freesurfer/hippocampus/     # segmentHA_T1 outputs
freesurfer/brainstem/       # segmentBS outputs
freesurfer/thalamic/        # segmentThalamicNuclei outputs
freesurfer/wmh/             # mri_WMHsynthseg outputs
```

And under `sub-1003/longitudinal/`:
```
freesurfer/sub-1003.base/                                # within-subject template
freesurfer/sub-1003_ses-wave1.long.sub-1003.base/        # per-tp longitudinal recon
freesurfer/sub-1003_ses-wave2.long.sub-1003.base/
freesurfer/sub-1003_ses-wave3.long.sub-1003.base/
freesurfer/long_mris_slopes/                             # annual atrophy rate maps
```

And under `sub-1003/ses-waveN/pet/{amyloid,tau}_18FAVxx/`:
```
petsurfer/coreg/pet2t1.lta
petsurfer/gtm/{gtmseg.mgz, pvc.nii.gz, gtm.stats}
```

And under `sub-1003/ses-waveN/dwi/`:
```
tracula/dmri/                                            # bedpostx + paths
tracula/dpath/                                           # 18 named tracts
```

## Order of operations (incremental, so we can checkpoint)

1. **`recon-all` / FastSurfer `recon_surf.sh`** on sub-1003 ses-wave1 (smoke-test, validate output) → ~1.5 hr
2. **Same for ses-wave2 and ses-wave3** → ~3 more hr (can parallelise)
3. **Longitudinal stream** (base + long × 3) → ~4 hr
4. **Hippocampal + brainstem + thalamic** segmentations × 3 waves → ~1 hr
5. **WMH** on FLAIR × 3 → ~5 min
6. **PETSurfer** on 4 PET scans → ~1 hr (gtmseg is the bottleneck; mri_gtmpvc is fast)
7. **TRACULA** on 3 DTI (after eddy + bedpostx) → ~6 hr (bedpostx is the bottleneck; gpu version helps)
8. **Surface-based fMRI** stats per task → ~30 min

**Total wall time for full sub-1003 FS pipeline**: ~16 hr if serial, ~8 hr if we
parallelise across waves. Doable overnight.

## Why FS surface-based matters for the paper

The smri-fm comparison currently uses *volumes* (FastSurfer aseg+DKT, SynthSeg,
T1Prep). FS surface-based metrics — **per-vertex cortical thickness**,
**gyrification index**, **sulcal depth** — are widely shown to be more
age-sensitive than volumes (Frangou 2022, Tustison 2014). Adding them as a
6th arm in our ridge comparison may close the gap to SynthSeg or — more
likely — show that thinner-feature surface-based ridge is competitive
without TIV normalisation.

For PET, surface-based projection (`mri_vol2surf` then per-vertex SUVR)
gives much higher spatial sensitivity to focal amyloid/tau than 8-region
DK averages.
