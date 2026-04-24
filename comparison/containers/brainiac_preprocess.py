"""BrainIAC-style preprocessing for a single T1w.

Replicates BrainIAC/src/preprocessing/mri_preprocess_3d_simple.py but:
- Takes a single input file instead of a directory (one scan per container).
- Writes `<out_dir>/<pat_id>.nii.gz` — the filename layout BrainAgeDataset
  expects, without the HD-BET `_0000` or `_bet` suffixes that the upstream
  script leaves behind.
- Exits 0 on success, 2 if HD-BET fails, 3 if registration fails.

Pipeline:
    1. N4 bias correction (SimpleITK)
    2. Rigid register to temp_head.nii.gz at 1mm iso (Mattes MI + Euler3D)
    3. HD-BET skull-strip

Usage:
    brainiac_preprocess.py \\
        --input /data/raw/.../sub-1003_ses-wave1_acq-MPRAGE_run-1_T1w.nii.gz \\
        --pat_id sub-1003_ses-wave1 \\
        --out_dir /output \\
        --temp_img /opt/brainiac_preproc/temp_head.nii.gz
"""
from __future__ import annotations

import argparse
import os
import shutil
import sys
import tempfile
from pathlib import Path

import SimpleITK as sitk
import torch


def register(fixed_img: sitk.Image, moving_path: Path, out_path: Path) -> None:
    moving_img = sitk.ReadImage(str(moving_path), sitk.sitkFloat32)
    moving_img = sitk.N4BiasFieldCorrection(moving_img)

    # Resample fixed to 1mm iso matching moving geometry
    old_size = fixed_img.GetSize()
    old_spacing = fixed_img.GetSpacing()
    new_spacing = (1.0, 1.0, 1.0)
    new_size = [
        int(round((old_size[i] * old_spacing[i]) / new_spacing[i]))
        for i in range(3)
    ]
    resample = sitk.ResampleImageFilter()
    resample.SetOutputSpacing(new_spacing)
    resample.SetSize(new_size)
    resample.SetOutputOrigin(fixed_img.GetOrigin())
    resample.SetOutputDirection(fixed_img.GetDirection())
    resample.SetInterpolator(sitk.sitkLinear)
    resample.SetOutputPixelType(sitk.sitkFloat32)
    fixed_1mm = resample.Execute(fixed_img)

    init_tf = sitk.CenteredTransformInitializer(
        fixed_1mm, moving_img, sitk.Euler3DTransform(),
        sitk.CenteredTransformInitializerFilter.GEOMETRY,
    )
    reg = sitk.ImageRegistrationMethod()
    reg.SetMetricAsMattesMutualInformation(numberOfHistogramBins=50)
    reg.SetMetricSamplingStrategy(reg.RANDOM)
    reg.SetMetricSamplingPercentage(0.01)
    reg.SetInterpolator(sitk.sitkLinear)
    reg.SetOptimizerAsGradientDescent(
        learningRate=1.0, numberOfIterations=100,
        convergenceMinimumValue=1e-6, convergenceWindowSize=10,
    )
    reg.SetOptimizerScalesFromPhysicalShift()
    reg.SetShrinkFactorsPerLevel(shrinkFactors=[4, 2, 1])
    reg.SetSmoothingSigmasPerLevel(smoothingSigmas=[2, 1, 0])
    reg.SmoothingSigmasAreSpecifiedInPhysicalUnitsOn()
    reg.SetInitialTransform(init_tf)
    final_tf = reg.Execute(fixed_1mm, moving_img)

    out_img = sitk.Resample(
        moving_img, fixed_1mm, final_tf, sitk.sitkLinear, 0.0,
        moving_img.GetPixelID(),
    )
    sitk.WriteImage(out_img, str(out_path))


def run_hdbet(in_path: Path, out_path: Path, device: str) -> None:
    import torch as _torch
    from HD_BET.hd_bet_prediction import get_hdbet_predictor, hdbet_predict
    dev = _torch.device(f"cuda:{device}" if device != "cpu" else "cpu")
    predictor = get_hdbet_predictor(use_tta=False, device=dev, verbose=False)
    hdbet_predict(
        str(in_path), str(out_path), predictor,
        keep_brain_mask=False, compute_brain_extracted_image=True,
    )


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--input", type=Path, required=True)
    p.add_argument("--pat_id", required=True, help="output stem, e.g. sub-1003_ses-wave1")
    p.add_argument("--out_dir", type=Path, required=True)
    p.add_argument("--temp_img", type=Path, required=True)
    args = p.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    final_path = args.out_dir / f"{args.pat_id}.nii.gz"
    if final_path.exists():
        print(f"already done: {final_path}")
        return 0

    device = "0" if torch.cuda.is_available() else "cpu"
    fixed_img = sitk.ReadImage(str(args.temp_img), sitk.sitkFloat32)

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        # HD-BET v2 expects BIDS-ish filename ending with _0000.nii.gz
        reg_path = tmp / f"{args.pat_id}_0000.nii.gz"
        try:
            register(fixed_img, args.input, reg_path)
        except Exception as e:
            print(f"registration failed: {e}", file=sys.stderr)
            return 3

        # HD-BET v2 writes the brain-extracted image at the output path and
        # a _bet.nii.gz sidecar mask alongside.
        bet_path = tmp / f"{args.pat_id}.nii.gz"
        try:
            run_hdbet(reg_path, bet_path, device=device)
        except Exception as e:
            print(f"HD-BET failed: {e}", file=sys.stderr)
            return 2

        if not bet_path.exists():
            print(
                f"HD-BET output missing; tmp dir: {os.listdir(tmp)}",
                file=sys.stderr,
            )
            return 2

        shutil.move(str(bet_path), str(final_path))

    print(f"wrote {final_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
