# smri-fm / T1Prep-DLBS comparison — task board

Updated 2026-04-22. Snapshot of the in-agent task list. Watch with:
  watch -n 10 cat /home/mhough/dev/T1Prep/comparison/TASKS.md

## Active / in-progress

- **#10** FOMO25 embedding smoke. *Blocked: need Legion access (amd64-only)*
- **#12** T1Prep longitudinal on sub-1003 + sub-1007. *Wrapper rewritten with two-stage protocol; pending image rebuild*

## Pending — publish / distribute layer

Naming locked in 2026-04-22:  `m9h/neurocontainers-arm` single repo,
images `t1prep-arm` / `fastsurfer-arm` / `medarc-arm`, tag scheme
`<upstream-version>-arm.<patch-rev>`.

- **#23** Bootstrap `m9h/neurocontainers-arm` GitHub repo + layout
- **#15** Rebuild `t1prep-arm` + `fastsurfer-arm` (into NAS-backed build contexts)
- **#16** Push `t1prep-arm` → `ghcr.io/m9h/t1prep-arm:v0.3.3-arm.1`
- **#17** Push `fastsurfer-arm` → `ghcr.io/m9h/fastsurfer-arm:6b6b985-arm.1`
- **#18** Push `medarc-arm` → `ghcr.io/m9h/medarc-arm:…` (after docker data-root relocated)
- **#19** GitHub Actions workflow for auto-rebuild on tag
- **#20** Upstream PR: T1Prep three Blackwell patches
- **#21** Upstream PR: FastSurfer Dockerfile for arm64 (issue #716)
- **#22** NeuroContainers recipes for the -arm images

## Pending — baseline/eval

- **#8** Dojo's wandb run details. *Blocked: need access or export*
- **#11** Reproduce Nima's 71-feature SynthSeg + ridge. *Blocked: arm64 .deb ships no mri_synthseg CLI; pip synthseg module is a workaround*

## Completed

- #1 Rebuild T1Prep on NGC pytorch:26.03-py3 arm64
- #3 MedARC-arm Dockerfile skeleton
- #5 smoke_all_subject.sh
- #6 Concordance notebook skeleton
- #7 FOMO25 repo / mmunetvae architecture
- #9 DLBS embedding extraction plan
- #13 smoke_all_subject formalised
- #14 FOMO25 mmunetvae embedding extraction script

## Manual asks from you

1. **Run** `/home/mhough/dev/T1Prep/comparison/scripts/relocate_docker_data_root.sh`
   — requires sudo, one-off, relocates docker images+cache to
   `/data/mhough/docker` so rebuilds never fill root again.
2. **Legion SSH access** — unblocks FOMO embedding runs (amd64-only image).
3. **Dojo's wandb config/plots** — unblocks task #8.

Everything in the publish layer is staged and ready once (1) lands. Once
docker data-root is relocated and we rebuild cleanly, #15 → #19 can run
in sequence overnight.
