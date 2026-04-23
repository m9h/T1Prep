# T1/T2 structural-MRI pipeline benchmark on DLBS sub-1003

**Goal.** Run every credible T1-weighted (and T1+T2-FLAIR) structural
preprocessing / segmentation / morphometry pipeline on the same single
DLBS subject and produce a side-by-side concordance table. Both as an
infrastructure shakedown and as the paper's "how do these tools actually
compare?" methods table.

sub-1003 ses-wave1: MPRAGE T1w + FLAIR T2w already on disk. ses-wave2
and ses-wave3 add longitudinal stability checks.

## Four tiers of pipeline

### Tier 1 — Full segmentation + morphometry pipelines

The "run the whole thing, collect volumes + thickness + registration"
tools.

| # | Pipeline | Arch | Host | Key outputs | Status |
|---|---|---|---|---|---|
| 1 | **FastSurfer seg_only** | arm64 | Spark | aseg+DKT vols, CerebNet, HypVINN | ✓ done on w1 |
| 2 | **FastSurfer recon-surf** | amd64 | **Legion** | + cortical surfaces + thickness | pending |
| 3 | **FreeSurfer 7.x recon-all** | amd64 | **Legion** | classical reference: aparc+aseg, thickness, curv, area | pending |
| 4 | **T1Prep** (DeepMriPrep + AMAP + CAT-Surface) | arm64 | Spark | AMAP tissue, CAT-thickness, Jacobian, MNI warp | rebuild done, rerunning |
| 5 | **CAT12 standalone** | Matlab Runtime | **Legion** | classical CAT12 reference | needs MCR install |
| 6 | **ANTs cortical thickness** | arm64 (user's deb build) | Spark | ANTs-KK thickness, priors-based seg | pending |
| 7 | **MedARC preprocessing** | arm64 (fedora) | Spark | SynthStrip + rigid MNI + SynthSeg vols | waits on FS-arm |
| 8 | **smriPrep (niPreps)** | amd64 | **Legion** | BIDS-standard T1 preproc | pending |
| 9 | **SAMSEG** | amd64 | **Legion** | Bayesian joint bias+seg | pending |
| 10 | **deepmriprep standalone** (without T1Prep) | arm64 | Spark | DL-only: brain mask, tissue, reg | pending |

### Tier 2 — Skull stripping alone

Feed the same T1, collect brain masks, compare Dice overlaps.

| # | Tool | Arch | Host | Notes |
|---|---|---|---|---|
| S1 | **SynthStrip** | arm64 | Spark | via fastsurfer-grace `mri_synthstrip` |
| S2 | **HD-BET** | arm64 | Spark | pip-installable, DL |
| S3 | **DeepBET** | arm64 | Spark | pip-installable, DL (T1Prep uses it) |
| S4 | **FSL BET** | amd64 | **Legion** | classical threshold-based |
| S5 | **ROBEX** | amd64 | **Legion** | classical robust |
| S6 | **antsBrainExtraction** | arm64 | Spark | classical ANTs |

### Tier 3 — Nonlinear registration to MNI

Feed the same skull-stripped T1, collect warped volumes + Jacobians.
Compare smoothness of warp, tissue-probability overlap post-warp.

| # | Tool | Arch | Host |
|---|---|---|---|
| R1 | **ANTs SyN** | arm64 | Spark |
| R2 | **FSL FNIRT** | amd64 | **Legion** |
| R3 | **SPM DARTEL / Geodesic Shoot** | Matlab | **Legion** |
| R4 | **SynthMorph** | arm64 | Spark (FreeSurfer DL reg) |
| R5 | **EasyReg** | arm64 | Spark (FreeSurfer DL reg) |
| R6 | **DeepMriPrep reg** | arm64 | Spark |
| R7 | **NiftyReg** | amd64 | Legion |

### Tier 4 — WMH detection (T1 + T2-FLAIR)

sub-1003 has FLAIR in wave 1. Skip this tier if the other waves
don't have FLAIR on every session.

| # | Tool | Arch | Host |
|---|---|---|---|
| W1 | **WMH-SynthSeg** | arm64 | Spark |
| W2 | **TrueNet** | arm64? | already in user's OMNI derivatives — has it built |
| W3 | **LST-LPA (SPM)** | Matlab | Legion |
| W4 | **LST-LGA (SPM)** | Matlab | Legion |

## Output structure

Everything writes under BIDS derivatives so PyBIDS can index:

```
/data/datasets/smri-fm-cmp/
  <pipeline-name>/
    ds004856/
      sub-1003_ses-wave1/
      sub-1003_ses-wave2/
      sub-1003_ses-wave3/
```

## Concordance metrics

For each pair of tools that produce comparable outputs:

- **Segmentation**: DK ROI volume correlation (Pearson), total GMV/WMV/
  CSF/ICV agreement (mean diff, abs diff), voxel-wise tissue-map Dice.
- **Cortical thickness**: DK ROI thickness correlation vs FreeSurfer
  recon-all reference; vertex-wise thickness Dice for tools that
  output mesh-based thickness.
- **Skull stripping**: pairwise brain-mask Dice, volume ratios.
- **Registration**: warp smoothness (log-determinant of Jacobian: mean,
  variance, min, max), tissue overlap after template warp.
- **WMH**: pairwise lesion-mask Dice, total WMH volume agreement.

## Concrete 3-day plan

**Day 1 (Spark, arm64 native):**
- FastSurfer seg_only × 3 waves
- T1Prep × 3 waves (once smoke test passes)
- SynthStrip + HD-BET + DeepBET + antsBrainExtraction on wave-1 T1
- SynthMorph + EasyReg + ANTs SyN + DeepMriPrep reg on wave-1 T1
- WMH-SynthSeg on wave-1

**Day 2 (Legion, amd64):**
- FreeSurfer 7.x recon-all on wave-1 (longest: ~6-8h)
- FastSurfer recon-surf on same
- smriPrep wave-1
- SAMSEG wave-1
- BET + ROBEX (minutes)
- FNIRT + NiftyReg
- LST-LPA and LST-LGA (if Matlab available)

**Day 3:**
- Aggregate all BIDS derivatives → parquet feature table
- Compute concordance metrics
- Generate scatter-matrix + heat-map figure
- Decide which tools make the paper and which get appendix-only
  mentions

Plus wave-2 and wave-3 runs in background as bandwidth allows, for
the longitudinal subset.

## Why this matters for the paper

Right now there's **no published head-to-head** for T1-structural
pipelines at this scale of tool coverage. Existing comparisons (e.g.
Huhdanpää 2018, Johnson 2024) cover maybe 3-4 tools. Doing 10+ on a
single well-characterised subject is a novel methods contribution in
its own right, even before we bring the FM into it.

Positions us to say in the paper: *"Across 10 T1-structural pipelines,
the four features the FM struggles to match most are X / Y / Z."*
That's much harder to dismiss than *"FM vs SynthSeg."*
