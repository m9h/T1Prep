# Update for smri-fm meeting — Thu 2026-04-23 11:30 ET

What we have to show this week.

## Shipped

**Two public arm64 container images on GitHub Container Registry:**

- `ghcr.io/m9h/t1prep-arm:v0.3.3-arm.1` — CAT12-lineage T1 preproc,
  works on DGX Spark Blackwell. Patches three upstream bugs blocking
  arm64 ports (deterministic-algorithm fallback, weight-cache perms,
  case-sensitive atlas filenames).
- `ghcr.io/m9h/fastsurfer-arm:6b6b985-arm.1` — seg_only, NGC PyTorch
  base, produces DK+VINN volumes + CerebNet + HypVINN on Grace.

**Three GitHub repos carrying the work:**

- [`m9h/neurocontainers-arm`](https://github.com/m9h/neurocontainers-arm)
  — recipes repo, Actions workflow auto-builds on tag push. `medarc-arm`
  recipe ready (needs local FreeSurfer 8.2.0 arm64 .debs in build context).
- [`m9h/smri-fm` @ `dlbs-morphometry-benchmark`](https://github.com/m9h/smri-fm/tree/dlbs-morphometry-benchmark)
  — our MedARC fork. `experiments/dlbs_morphometry_benchmark/` has the
  four-rung classical baseline implementation (extractors + ridge +
  notebook + tests).
- [`m9h/T1Prep` @ `smri-fm-dlbs-comparison`](https://github.com/m9h/T1Prep/tree/smri-fm-dlbs-comparison)
  — methods notes, paper draft (LaTeX + refs.bib), Dockerfiles.

**Working pipeline on DLBS sub-1003 (ages 54/58/63, all 3 waves):**

- FastSurfer VINN: 164 s / 128 s / 125 s per wave. Full aseg+DKT +
  CerebNet + HypVINN stats.
- T1Prep: 329 s / 328 s / 345 s per wave. Tissue maps + CAT-Surface
  thickness + DK40 parcellation + nonlinear MNI Jacobian.
- Matched-pair concordance notebook executes end-to-end, reports DK ROI
  volume-vs-thickness correlations per wave and longitudinal-slope
  sign-agreement.

**Reproducible ridge baseline, four bias-correction schemes:**

- Dry-run on 2 subjects × FastSurfer DKT: raw MAE 3.1 yr, Cole 1.1 yr.
- Optional wandb logging (`--wandb-project`). Trackio drop-in ready.

## Still in flight as of meeting start

- Overnight sbatch (job 897, submitted 09:30 PT) running
  `smoke_all_subject.sh` on 18 more DLBS subjects. Yesterday's attempt
  silently failed because scripts still referenced pre-rename image
  names (`-grace` vs `-arm`); caught via tests, fixed, resubmitted.
- Two-stage T1Prep longitudinal wrapper (pre-stage cross-sectional
  wave 1 → `--initial-surface` for longitudinal waves 2/3). Works for
  stage 2 (realign) + stage 3 seg; stage 4 per-wave seg had partial
  outputs last night. Re-running.

## What we propose to the project

1. **Four-rung classical morphometry ladder** as the fixed baseline
   table. Each rung adds one axis:
   - Rung 1: SynthSeg volumes + ridge (Nima's baseline).
   - Rung 2: SynthSeg + N4 + ridge (tests Connor's 2026-04-13 proposal).
   - Rung 3: FastSurfer VINN volumes + ridge (higher-quality network).
   - Rung 4: T1Prep thickness + Jacobian + ridge (beyond volumes).
2. **Benchmark against FM arms under identical bias correction** — BrainIAC,
   FOMO25 `mmunetvae`, AnatCL, MedARC's own (when published).
3. **Report `Schulz 2025` effect size** alongside age MAE — simpler
   models beat complex ones on disease detection. If MedARC's FM loses
   both metrics it's a hard conversation; if it loses only one, the
   paper frames the trade-off honestly.
4. **Longitudinal Vidal-Piñeiro test** on DLBS three waves for every
   arm — no FM has published this, DLBS is the right venue.
5. **Expose our arm64 containers as first-class MedARC alternatives**
   for anyone running on Grace. MedARC's own Dockerfile uses
   amd64 `freesurfer/freesurfer:7.4.1`; our `medarc-arm` recipe runs
   the same `preprocessing/pipeline.py` on local arm64 .debs.

## Open asks

- **Dojo's wandb run config/plots** (still pending) — need
  mask-ratio/patch-size/augmentation to decide whether FOMO-defaults
  are sensible for our evaluation.
- **Nima's 71-feature SynthSeg outputs and scripts** — want to
  reproduce her MAE 6.66 yr baseline before adding rungs 2–4.
- **Which FM checkpoint** is the headline comparison for the first
  MedARC release? Whatever the answer, we can run the embedding
  extraction in our harness.
- **Would the project accept** `m9h/neurocontainers-arm` as the
  upstream-referenced arm64 distribution for anyone on Grace? That
  also gives us a landing zone for the three T1Prep upstream patches
  once they're accepted.

## Development process, for the record

Adopting red-green TDD from today onward. Test suite at
`experiments/dlbs_morphometry_benchmark/tests/`. First regressions
captured: image-rename drift, pipeline-failure detection, T1Prep
`--long-data` file-vs-directory semantics, nonexistent-subject
handling.
