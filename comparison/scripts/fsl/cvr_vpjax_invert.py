"""CVR estimation from DLBS Hypercapnia BOLD using vpjax.

Two outputs per scan:

1. **CVR map** (numpy/sklearn, deterministic):
   For each voxel, fit %BOLD ~ stimulus + nuisance via OLS. Stimulus is
   data-driven (Liu 2017): standardised whole-brain mean signal serves
   as the implicit CO2 proxy when no etCO2 trace is available, which is
   our case — DLBS does not publish capnograph data alongside its
   Hypercapnia BOLD scans.

   Output: cvr_map.nii.gz (units: %BOLD per stimulus SD)

2. **Balloon-Windkessel parameter inversion** (vpjax, JAX-autodiff):
   Region-averaged BOLD inside the FastSurfer-derived GM mask is fed to
   `vpjax.hemodynamics.inversion.fit_balloon_bold` with the same
   data-driven stimulus. Returns posterior estimates of κ, γ, τ, α, E0
   per region — the biophysical CVR characterisation.

   Output: balloon_params.json (per-region kappa/gamma/tau/alpha/E0 + loss)

The two outputs are complementary: (1) gives a voxel-wise CVR map for QC
and group statistics; (2) gives subject-region biophysical parameters
that feed downstream multimodal joint models with PET, ASL, and morphometry.

Usage:
    python cvr_vpjax_invert.py --cvr-root /data/datasets/smri-fm-cmp/fsl/ds004856/cvr
    python cvr_vpjax_invert.py --cvr-root ... --subject sub-1003_ses-wave1_run-1
"""
from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path

import numpy as np

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s",
                    datefmt="%H:%M:%S")
log = logging.getLogger("cvr-vpjax")


def load_nii(path: Path):
    import nibabel as nib
    img = nib.load(str(path))
    return img.get_fdata(dtype=np.float32), img.affine


def save_nii(data: np.ndarray, affine: np.ndarray, path: Path):
    import nibabel as nib
    nib.save(nib.Nifti1Image(np.asarray(data, dtype=np.float32), affine), str(path))


def cvr_map_ols(bold_4d: np.ndarray, mask: np.ndarray,
                motion_par: np.ndarray | None = None) -> np.ndarray:
    """Voxel-wise %BOLD ~ stimulus + nuisance OLS, returns per-voxel β."""
    nx, ny, nz, nt = bold_4d.shape
    assert mask.shape == bold_4d.shape[:3]

    # Whole-brain mean as data-driven stimulus
    in_brain = bold_4d.reshape(-1, nt)[mask.flatten() > 0.5]      # (n_vox, nt)
    stim = in_brain.mean(axis=0)
    stim = (stim - stim.mean()) / (stim.std() + 1e-9)

    # Design matrix: stim + intercept + (optional motion)
    cols = [stim, np.ones(nt)]
    if motion_par is not None and motion_par.shape[0] == nt:
        cols += [motion_par[:, k] for k in range(motion_par.shape[1])]
    X = np.stack(cols, axis=1)               # (nt, k)

    # OLS one-shot for masked voxels
    Y = bold_4d.reshape(-1, nt).T            # (nt, n_vox_total)
    beta = np.zeros(Y.shape[1], dtype=np.float32)
    msk = mask.flatten() > 0.5
    Yin = Y[:, msk]
    # Per-voxel percent change normalisation
    bsl = Yin.mean(axis=0)
    Ypct = 100.0 * (Yin - bsl) / np.where(bsl > 1, bsl, 1.0)
    XtX_inv = np.linalg.pinv(X.T @ X)
    coefs = XtX_inv @ X.T @ Ypct             # (k, n_vox)
    beta[msk] = coefs[0]                      # stim regressor
    return beta.reshape(nx, ny, nz)


def vpjax_balloon_invert(bold_region_means: dict[str, np.ndarray], tr: float):
    """Run vpjax.hemodynamics.inversion.fit_balloon_bold on each region.

    bold_region_means: {region_label: 1-d BOLD time series (% change)}
    Returns: {region_label: {kappa, gamma, tau, alpha, E0, loss}}
    """
    try:
        import jax.numpy as jnp
        from vpjax.hemodynamics.inversion import fit_balloon_bold
    except ImportError as e:
        raise SystemExit(f"vpjax not importable: {e}")

    out: dict[str, dict] = {}
    for region, bold in bold_region_means.items():
        # Same data-driven stimulus = whole-brain mean in % change form
        stim = (bold - bold.mean()) / (bold.std() + 1e-9)
        result = fit_balloon_bold(
            jnp.asarray(bold, dtype=jnp.float32),
            jnp.asarray(stim, dtype=jnp.float32),
            tr=tr, dt=0.05, n_steps=200, learning_rate=2.0,
        )
        # result keys depend on vpjax — store everything that's a python scalar
        out[region] = {
            k: float(v) for k, v in result.items()
            if isinstance(v, (int, float)) or hasattr(v, "item")
        }
    return out


def process_one(sub_dir: Path, run_balloon: bool) -> dict:
    """Run CVR for one <sub>_<ses>_<run> dir prepared by cvr_vpjax_dlbs.sh."""
    bold_path = sub_dir / "mc.nii.gz"
    mask_path = sub_dir / "brain_mask.nii.gz"
    if not bold_path.exists() or not mask_path.exists():
        log.warning("skip %s (missing mc or brain mask)", sub_dir.name)
        return {"status": "skipped", "reason": "missing input"}

    bold_4d, affine = load_nii(bold_path)
    mask, _ = load_nii(mask_path)

    motion = None
    par_path = sub_dir / "mc.par"
    if par_path.exists():
        motion = np.loadtxt(par_path)

    log.info("CVR-OLS %s (BOLD %s)", sub_dir.name, bold_4d.shape)
    cvr_map = cvr_map_ols(bold_4d, mask, motion)
    save_nii(cvr_map, affine, sub_dir / "cvr_map.nii.gz")

    summary: dict = {"sub": sub_dir.name, "n_vox": int((mask > 0.5).sum()),
                     "cvr_mean": float(cvr_map[mask > 0.5].mean()),
                     "cvr_p95": float(np.percentile(cvr_map[mask > 0.5], 95))}

    if run_balloon:
        # Region-averaged BOLD = whole brain (single region; refine later
        # with FastSurfer aparc once coreg is wired up end-to-end).
        in_brain = bold_4d.reshape(-1, bold_4d.shape[-1])[mask.flatten() > 0.5]
        bsl = in_brain.mean(axis=1, keepdims=True)
        bold_pct = 100.0 * (in_brain - bsl) / np.where(bsl > 1, bsl, 1.0)
        wb_mean = bold_pct.mean(axis=0)
        # TR in seconds
        import nibabel as nib
        tr = float(nib.load(str(bold_path)).header.get_zooms()[3])
        balloon = vpjax_balloon_invert({"whole_brain": wb_mean}, tr=tr)
        (sub_dir / "balloon_params.json").write_text(json.dumps(balloon, indent=2))
        summary["balloon_params"] = balloon["whole_brain"]

    return summary


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--cvr-root", type=Path, required=True)
    p.add_argument("--subject", default=None,
                   help='restrict to one <sub>_<ses>_<run> dir')
    p.add_argument("--no-balloon", action="store_true",
                   help='skip the vpjax Balloon-Windkessel inversion')
    args = p.parse_args()

    if args.subject:
        sub_dirs = [args.cvr_root / args.subject]
    else:
        sub_dirs = sorted(d for d in args.cvr_root.iterdir() if d.is_dir())

    out: list[dict] = []
    for d in sub_dirs:
        try:
            out.append(process_one(d, run_balloon=not args.no_balloon))
        except Exception as e:
            log.exception("FAIL %s", d.name)
            out.append({"sub": d.name, "status": "error", "msg": str(e)})

    summary = args.cvr_root / "summary.json"
    summary.write_text(json.dumps(out, indent=2))
    log.info("Wrote %s (%d entries)", summary, len(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
