# Experiment tracking: wandb vs trackio

Decision as of 2026-04-22: **wandb for now.** Trackio is a drop-in
replacement with real advantages worth revisiting once it leaves pre-release
or once we want local-first artifacts.

## Short summary of each

| | wandb | trackio (HF, 2025) |
|---|---|---|
| API | the original | `import trackio as wandb` — compatible with `init` / `log` / `finish` |
| Status | production, widely adopted | pre-release, expect breaking SQLite-schema changes |
| Hosting | wandb cloud (free tier for academic) | local SQLite by default + optional HF Spaces for sharing |
| Artifact store | wandb Artifacts | local FS + HF Datasets / Hub |
| Reach | every ML paper, every MedARC repo | new; adoption growing |
| Source | closed dashboard, open SDK | ~1000 LOC, all open source |
| Lock-in | data behind proprietary API | not locked; SQLite readable directly |
| GPU energy | not native | native logging + exportable to model cards |
| Cost | free for academic, paid for org features | free, self-hostable |

## Why wandb for this project

1. **MedARC already tracks Dojo's FOMO-pretraining + their existing
   fmri-fm MAE runs on wandb.** Our brain-age baseline runs land
   alongside theirs for direct comparison on the same dashboard.
2. **Connor's Discord request** for Dojo's run details includes wandb
   plots — the ecosystem assumption is wandb.
3. **Zero-risk** — production-stable, one `wandb login` away.

## When to switch to trackio

- **After trackio 1.0** (breaking-change freedom).
- **If we want local-first for privacy / offline scenarios** — trackio
  runs entirely without network if desired.
- **For publication-quality reproducibility** — trackio's data can
  travel with the paper as a SQLite file; wandb's API dependence means
  the dashboard only lives as long as wandb exists.
- **For GPU-energy disclosure** — trackio native, wandb needs a plugin.

## Current integration

`experiments/dlbs_morphometry_benchmark/scripts/fit_ridge_baseline.py`
now accepts:

```bash
--wandb-project <name>
--wandb-entity <name>
--wandb-run-name <label>
```

Absence of `--wandb-project` skips tracking and runs as before. Metrics
logged per run: MAE / RMSE / R² / Pearson r / bias / n, under each of
the four bias-correction schemes (raw / Cole / Beheshti / Zhang).

## If we flip to trackio later

One-line change at the top of scripts:

```python
# wandb version
import wandb

# trackio version (drop-in)
import trackio as wandb
```

All `wandb.init` / `wandb.log` / `wandb.finish` call sites unchanged.

## Decision re-review trigger

Revisit if:
- trackio tags a 1.0 release (no more schema breakage).
- MedARC project votes to standardise on trackio.
- We want to publish a dataset + run artifacts together via HF Hub
  (trackio's native integration simplifies this vs wandb + HF separate
  pushes).
