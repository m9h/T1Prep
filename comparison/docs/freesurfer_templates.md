# FreeSurfer template + atlas reference (with our DLBS context)

A short reference for which template/atlas FreeSurfer ships, where they
live, and how they relate to the OMM-1 + MNI152 templates we're now
using in the integrated pipeline.

## What FreeSurfer ships

All under `$FREESURFER_HOME` (= `/usr/lib/freesurfer` in our `freesurfer-arm:8.2.0`):

### Volumetric templates

| File | Path | What it is |
|---|---|---|
| **MNI152 (FSL flavour, 1 mm + 2 mm)** | `$FSLDIR/data/standard/MNI152_T1_{1,2}mm.nii.gz` (FSL ships these; FreeSurfer references them) | The MNI ICBM152 6th-gen *symmetric* template, FSL packaging. Default registration target for FSL FNIRT/FLIRT and most legacy pipelines. |
| **MNI305** (talairach.gca) | `$FREESURFER_HOME/average/RB_all_2020-01-02.gca` | FreeSurfer's *internal* atlas for `mri_em_register`, used by recon-all to align every subject to the FS atlas space. **Our FS 7.4.1 .deb is missing this — that's why FastSurfer recon_surf failed.** Present in our 8.2.0 .deb. |
| **CVS (Combined Volume + Surface)** | `$FREESURFER_HOME/average/mni152.register.dat` + various .lta + .m3z | Affine + nonlinear bridge between FS subject space and MNI152, computed by Wu et al. 2018 (*Hum Brain Mapp* 39:3793). Used by `mri_vol2vol --mni152reg`. |
| **OMM-1** (Oxford-MultiModal-1) | not bundled with FS — we cloned from FMRIB | Our preferred alternative for multimodal joint warps. See `MMORF_OM-1_plan.md`. |

### Surface templates

| Name | Vertices/hemi | When to use |
|---|---|---|
| `fsaverage` | 163 842 | Default surface atlas, full resolution. Used by `mris_register`, `mri_surf2surf`. |
| `fsaverage6` | 40 962 | Downsampled (~4× fewer vertices). Often used for group fMRI projection (matches typical voxel size). |
| `fsaverage5` | 10 242 | Coarser still. Common for ML/connectivity studies (smaller feature space). |
| `fsaverage4` | 2 562 | Very coarse, rarely used outside teaching. |
| `fsaverage_sym` | 163 842 | Left/right symmetric average. For laterality studies. |

### Subregion atlases (the new+modern stuff)

| Atlas | Tool | Reference | DLBS-relevance |
|---|---|---|---|
| **Brainstem (4 large structures)** | `recon-all -brainstem-structures` (legacy) or `segment_subregions brainstem` (modern, FS 7.3+) | Iglesias 2015 | Already-standard; medulla / pons / midbrain / SCP volumes |
| **AAN (10 nuclei)** ⭐ new | `SegmentAAN.sh` | Olchanyi 2024, *HBM*, doi 10.1002/hbm.70357 | LC + VTA + DR + raphe — the cognitive-aging / arousal nuclei |
| **NextBrain (~300 ROIs/hemi)** ⭐⭐ March 2026 | `mri_histo_atlas_segment_fireants` | Casamitjana 2025 *Nature* + Puonti 2026 *Imaging Neurosci* | Histological atlas; **modality-robust + doesn't need recon-all** — bypasses our current .deb gap |
| Thalamic nuclei (25) | `segment_subregions thalamus` | Iglesias 2018 | Cognitive-aging |
| Hippocampal subfields | `segment_subregions hippo-amygdala` | Iglesias 2015 | AD-relevant; CA1/3/DG/sub |
| March 2025: **subregion atlases now in MNI/ICBM152 space** | direct atlas-to-MNI mapping | FS mailing list 2025 | Lets us apply atlases to MNI-warped scans without per-subject recon-all — useful escape hatch when FS .debs are gappy |

## Coordinate-system bridges

The Wu 2018 paper (`Accurate nonlinear mapping between MNI volumetric and
FreeSurfer surface coordinate systems`, [PMC6239990](https://pmc.ncbi.nlm.nih.gov/articles/PMC6239990/))
provides the transforms FreeSurfer uses internally to bridge:

```
fsaverage  ←──  CVS / mni152.register.dat  ──→  MNI152NLIN6Asym  (the FSL flavour)
                      │
                      └─ via Wu 2018 nonlinear warp
```

In our DLBS pipeline we now have *three* MNI-family targets:

```
        MedARC pipeline.py
              │
              ▼
        MNI152NLin2009cAsym (Fonov 2011, ~150 young adults)
              │
              │  applywarp via OMM-1's bidirectional warps
              ▼
        OMM-1 (Lange/Andersson 2024, ~50k UKB scans, multimodal)
              │
              │  Wu 2018 atlas
              ▼
        MNI152NLIN6Asym (FSL packaging) ↔ fsaverage (FS surface)
```

The pre-shipped warp files at `~/fsl/data/standard/oxford-mm-templates/Oxford-MM-1/transformations/`
let us round-trip MNI152↔OMM-1 with one `applywarp` call. fsaverage↔MNI152
is handled by `mri_vol2vol --mni152reg` using `$FREESURFER_HOME/average/mni152.register.dat`.

## FastSurfer ≠ FreeSurfer (even though it's a subset of the workflow)

Important taxonomic note before we mix outputs. **FastSurfer is a separate
project that *replaces parts of* FreeSurfer's pipeline with deep-learning
models, not a fork or a rebuild.** Specifically:

| Stage | FreeSurfer canonical | FastSurfer replacement |
|---|---|---|
| Brain extraction | `mri_watershed` / `mri_synthstrip` | `FastSurferCNN` / `mri_synthstrip` (newer FS) |
| Volumetric segmentation + cortical parcellation | `mri_em_register` + `mri_ca_register` + `mri_aparc2aseg` (~6 hr CPU) | `FastSurferVINN` (~1 min GPU), produces `aparc.DKTatlas+aseg.deep.mgz` |
| Surface reconstruction | `mri_tessellate` + `mris_inflate` + `mris_sphere` + `mris_register` | **uses FreeSurfer's surface tools as-is** via `recon_surf.sh` (no DL replacement here) |

Implications for cross-tool concatenation:

- FastSurfer aseg+DKT.VINN volumes use the **same DKT atlas labels** as
  FreeSurfer aparc+aseg, but the underlying segmentations are NOT
  byte-identical (CNN vs Bayesian/atlas-based). Cohen 2024 estimates
  ~95% region-volume correlation between the two on adult cohorts.
- FastSurfer's `recon_surf.sh` (the surface stage) is a **thin wrapper
  around FreeSurfer's classical mris_inflate / mris_register binaries**
  — so it pins to a specific FS version (currently 7.4.1) and inherits
  any FS .deb gaps in atlas data (which is exactly the
  `RB_all_2020-01-02.gca` failure we hit today).
- Containers reflect this: `fastsurfer-arm` (seg-only) is pure FastSurfer +
  PyTorch, no FS binaries; `fastsurfer-full` adds FreeSurfer 7.4.1 because
  surface stage needs it; `freesurfer-arm` is FreeSurfer alone (no FastSurfer).

For ridge-style cross-tool comparisons we treat FastSurfer aseg+DKT and
FreeSurfer aseg+DKT as **distinct rungs** even though they share an atlas,
because the segmentations differ. The 2024-2026 lit consistently does this.

## Implication for our analysis

For every per-region feature we extract (FastSurfer aseg+DKT, SynthSeg,
T1Prep DKT, NextBrain, AAN, hippo subfields, ...), the region label
lives in **one** of these atlas spaces. Cross-tool concatenation
requires we know which space each tool reports in:

| Tool | Atlas space | Notes |
|---|---|---|
| FastSurfer aseg+DKT.VINN | FS native (subject's `mri/`) | resampleable to MNI152 via subject's transformations |
| SynthSeg (MedARC pipeline.py) | MNI152NLin2009cAsym | already in MNI; no further warp |
| T1Prep | MNI152NLin2009cAsym (CAT12 lineage) | matches SynthSeg |
| BrainIAC embeddings | latent (no anatomical mapping) | n/a |
| AAN | FS native (subject's `mri/aparc+aseg`) | needs recon-all output |
| NextBrain | direct on input scan | no recon-all needed |
| OMM-1-warped versions of any of the above | OMM-1 | computable from any of the others via the bridges above |

## Practical recommendation

When we re-extract features after the .deb gap is fixed, do everything in
**MNI152NLin2009cAsym** by default (matches MedARC + T1Prep + most
2024-2026 lit) and emit an OMM-1-warped sidecar via `applywarp` for
groups that prefer it. fsaverage-surface metrics from FreeSurfer's
recon-all output get projected to MNI152 via Wu 2018's mapping in
`mri_vol2vol --mni152reg` for cross-tool joint analyses.
