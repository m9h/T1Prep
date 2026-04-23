# smri-fm / T1Prep-DLBS comparison — task board

Updated 2026-04-23. Watch with:
  watch -n 10 cat /home/mhough/dev/T1Prep/comparison/TASKS.md

## In progress right now

- **#15 / job 903 (Slurm, gpu partition)** — overnight fan-out on 18
  DLBS subjects via `smoke_all_subject.sh`. Started 09:35 PT, ETA
  ~15:30 PT. First subject: sub-1149.
- **#24** FOMO25 embedding smoke test. *Blocked: need Legion access
  (amd64-only image).*
- **#11** Align with Nima's merged SynthSeg+ridge (PR #9). She shipped
  the rung-1 baseline upstream 2026-04-23; our role is to re-run
  locally + confirm reproduction + cite.
- **#12** T1Prep longitudinal on sub-1003 + sub-1007. Volumes worked
  (first try); surfaces failed without `--initial-surface`. Fixed
  in `t1prep_longitudinal.sh` with two-stage protocol. Will complete
  when job 903 finishes.

## Pending — publish / distribute

- **#18** Push `medarc-arm` → `ghcr.io/m9h/medarc-arm:…` (blocked on
  build — depends on copying FreeSurfer+ITK .debs into build context)
- **#20** Upstream T1Prep PR: three Blackwell patches
- **#21** Upstream FastSurfer PR: Dockerfile for arm64 (issue #716)
- **#22** NeuroContainers recipes for the -arm images

## Pending — baseline/eval

- **#8** Dojo's wandb run details. *Blocked on share/export.*

## Completed

- #1 Rebuild T1Prep on NGC pytorch:26.03-py3 arm64
- #3 MedARC-arm Dockerfile skeleton
- #5 smoke_all_subject.sh
- #6 Concordance notebook skeleton
- #7 FOMO25 repo / mmunetvae architecture
- #9 DLBS embedding extraction plan
- #13 smoke_all_subject formalised
- #14 FOMO25 mmunetvae embedding extraction script
- #15 Rebuild -arm images after docker prune → NAS-backed store
- #16 Push `t1prep-arm` → `ghcr.io/m9h/t1prep-arm:v0.3.3-arm.1`
- #17 Push `fastsurfer-arm` → `ghcr.io/m9h/fastsurfer-arm:6b6b985-arm.1`
- #19 GitHub Actions workflow for auto-rebuild
- #23 Bootstrap `m9h/neurocontainers-arm` GitHub repo

## Manual asks from you

1. **Legion SSH access** — unblocks FOMO embedding run.
2. **Dojo's wandb config/plots** — unblocks #8.
3. Optional: Review [`m9h/neurocontainers-arm`](https://github.com/m9h/neurocontainers-arm)
   and [`m9h/T1Prep@smri-fm-dlbs-comparison`](https://github.com/m9h/T1Prep/tree/smri-fm-dlbs-comparison)
   for anything you want changed before the upstream PRs go out.
