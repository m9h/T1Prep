# Containers — reproducibility plan

Everything in this comparison runs inside pinned Docker images so that we
(and reviewers) can reproduce the results end-to-end from the same input
T1s. The two arms each have their own upstream-provided Dockerfile; we
don't fork those definitions — we only pin versions, record digests, and
wrap them in Slurm sbatch scripts.

## Target hosts

- **Primary:** `gx10-dgx-spark` — single-node Slurm cluster, NVIDIA GB10
  (Blackwell), **aarch64**. Docker available, partition `gpu` with
  `--gres=gpu:gb10:1`.
- **Fallback:** Legion workstation, 16-core x86_64 + 8 GB GPU, podman,
  FreeSurfer 8.2.0 already containerised — see
  `reference_legion_freesurfer.md` in memory.

## What gets pinned

For each arm we record, in `IMAGE_DIGESTS.md`:

1. Source-repo commit SHA (smri-fm or T1Prep release tag).
2. Base-image digest (e.g. `freesurfer/freesurfer@sha256:…`).
3. Resulting local image tag + digest after `docker build`.
4. `templateflow` cache snapshot used (for MNI152NLin2009cAsym@res=1).
5. FreeSurfer license path (required by freesurfer base image).

Tags are never trusted; only digests are. `build_*.sh` scripts fail if
the recorded upstream digest does not match, so an upstream retag cannot
silently change the build.

## The two arms

### Arm A — MedARC `smri-fm` preprocessing

- Upstream: `github.com/MedARC-AI/smri-fm` @
  `fbdb1a83a83ec420f1ea6932d36070d89790b055` (pinned 2026-04-21).
- Base: `freesurfer/freesurfer:7.4.1` **(linux/amd64 only)**.
- Pipeline: SynthStrip → 1 mm iso → rigid ANTs to MNI152NLin2009cAsym →
  optional SynthSeg.
- Image entrypoint: `/opt/venv/bin/python /app/preprocessing/pipeline.py`.

**Platform caveat.** The FreeSurfer base image is amd64-only. Three ways
to run this on the aarch64 DGX Spark:

1. **QEMU emulation.** Install `qemu-user-static` binfmt, then `docker
   run --platform=linux/amd64`. Works, but mri_synthseg TF inference is
   ~10–30× slower under emulation — tolerable for a smoke test on one
   subject, unacceptable for 1000 scans.
2. **Native arm64 rebuild.** Rebuild FreeSurfer 7.4.1 from source on
   arm64 (official source ships with arm64 support since ~7.4.0), then
   rebuild the MedARC image `FROM` that base. ~1–2 hr build, one time.
3. **Factored alternative.** Replace FreeSurfer base with a minimal
   container that ships only the `mri_synthstrip` and `mri_synthseg`
   Python entrypoints + weights (both are self-contained TF models) +
   ANTs. All three tools have arm64-compatible source.

Default plan: **(1) for smoke test**, then **(2) for production**.

### Arm B — T1Prep

- Upstream: `github.com/ChristianGaser/T1Prep` @ `v0.3.0` (pinned by
  `T1PREP_VERSION` build arg; `T1PREP_SOURCE=release` is the default).
- Base: `python:3.12-slim` — **multi-arch, native arm64 works.**
- Pipeline: DeepMriPrep skull strip + bias correction, AMAP tissue seg,
  CAT-Surface cortex + thickness, nonlinear MNI152 warp.
- Image entrypoint: `/opt/T1Prep/scripts/T1Prep`.

No platform issue on DGX Spark.

## Building

```bash
# from comparison/containers/
./build_t1prep.sh         # builds smri-fm-cmp-t1prep:<tag>
./build_medarc.sh         # builds smri-fm-cmp-medarc:<tag>
cat IMAGE_DIGESTS.md       # all digests recorded after build
```

Both scripts are idempotent and write provenance to
`IMAGE_DIGESTS.md` on success. If the upstream base digest has drifted,
the build fails loudly with a digest-mismatch error — re-pin
consciously, don't silently rebuild against a moving base.

## Running (Slurm)

See `../slurm/`. One sbatch per arm per dataset:

```bash
sbatch ../slurm/run_medarc.sbatch /data/raw/openneuro/ds004856
sbatch ../slurm/run_t1prep.sbatch /data/raw/openneuro/ds004856
```

Each sbatch script pulls the image tag from `IMAGE_DIGESTS.md`, mounts
the BIDS input read-only, and writes derivatives to
`/data/datasets/smri-fm-cmp/<arm>/<dataset>/`.

## Required licence

The MedARC arm uses FreeSurfer's SynthStrip/SynthSeg via the official
FreeSurfer base image, which requires a `license.txt`. Obtain free from
<https://surfer.nmr.mgh.harvard.edu/registration.html> and place at
`~/.freesurfer/license.txt`; the sbatch wrappers bind-mount it into the
container at `/opt/freesurfer/license.txt`.

T1Prep has no licence requirement beyond Apache 2.0.
