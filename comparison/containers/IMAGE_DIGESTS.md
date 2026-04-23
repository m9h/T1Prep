# Image digest manifest

Updated by `build_*.sh` on every successful build. Do not hand-edit the
digests below — use the build scripts so upstream drift is detected.

## Source commits (pinned)

| Repo | Commit / tag | Pinned |
|---|---|---|
| `MedARC-AI/smri-fm` | `fbdb1a83a83ec420f1ea6932d36070d89790b055` | 2026-04-21 |
| `ChristianGaser/T1Prep` | release tag `v0.3.0` (commit `8dc71bf50f680dc9ec2aebac0ee197ab803ee917` on main at pin time) | 2026-04-21 |

## Expected upstream base-image digests

| Image | Expected digest | Platform |
|---|---|---|
| `freesurfer/freesurfer:7.4.1` | _(run `build_medarc.sh --inspect` to populate)_ | linux/amd64 |
| `python:3.12-slim` | _(run `build_t1prep.sh --inspect` to populate)_ | linux/arm64, linux/amd64 |
| `ghcr.io/astral-sh/uv:latest` | _(run `build_medarc.sh --inspect` to populate)_ | multi-arch |

## Built images

_(populated by build scripts; one row per successful build)_

| Tag | Digest | Platform | Built | Source SHA |
|---|---|---|---|---|

## TemplateFlow cache

MedARC arm uses `MNI152NLin2009cAsym` at 1 mm resolution. Templateflow
normally downloads on demand; for reproducibility the build scripts
snapshot the resolved files and hash them:

| Template file | SHA-256 |
|---|---|

## FreeSurfer licence

`~/.freesurfer/license.txt` must exist on the host. Not tracked here
because it's user-bound — the Slurm scripts fail with a clear error if
it's missing.
