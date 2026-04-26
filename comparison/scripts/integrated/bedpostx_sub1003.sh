#!/usr/bin/env bash
# bedpostx_gpu — Bayesian crossing-fiber model on DLBS DTI.
#
# Required input dir layout (FSL convention):
#   bedpostx_in/
#     data.nii.gz            <- eddy-corrected 4D DTI
#     bvals, bvecs           <- as supplied
#     nodif_brain_mask.nii.gz <- from BET on b=0
#
# We assemble these from existing FDT outputs at
#   /data/datasets/smri-fm-cmp/fsl/ds004856/dwi/<sub>_<ses>/...
#
# Output:
#   ${OUT_ROOT}/dwi/<sub>_<ses>.bedpostX/
#     mean_d{1,2,3}samples.nii.gz   (diffusivity along each fiber)
#     mean_f{1,2,3}samples.nii.gz   (volume fraction of each fiber)
#     dyads{1,2,3}.nii.gz           (mean orientation of each fiber)
#     ...
#
# Time: ~4-8 hr CPU bedpostx, ~30-60 min bedpostx_gpu (CUDA build).
# Per-session, single-subject; this script runs ses-wave1 by default to
# checkpoint before fanning out.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/../fsl/common.sh"

SUBJECT="${SUBJECT:-sub-1003}"
SES="${SES:-ses-wave1}"
USE_GPU="${USE_GPU:-1}"

stem_dir="${OUT_ROOT}/dwi/${SUBJECT}_${SES}"
[ -d "${stem_dir}" ] || { log "no FDT outputs at ${stem_dir} — run fdt_dlbs.sh first"; exit 1; }

# Find the canonical eddy-corrected file (we wrote this as <stem>_eddy.nii.gz)
eddy=$(ls "${stem_dir}"/*_eddy.nii.gz 2>/dev/null | head -1)
[ -z "${eddy}" ] && { log "no _eddy.nii.gz in ${stem_dir}"; exit 1; }
stem=$(basename "${eddy}" _eddy.nii.gz)

# Bedpostx input dir
in_dir="${OUT_ROOT}/dwi/${SUBJECT}_${SES}.bedpostx_in"
mkdir -p "${in_dir}"
ln -sf "${eddy}" "${in_dir}/data.nii.gz"
# bvals/bvecs from raw — bedpostx wants them named exactly bvals + bvecs
raw_bval="${RAW_ROOT}/${SUBJECT}/${SES}/dwi/${stem}.bval"
raw_bvec="${RAW_ROOT}/${SUBJECT}/${SES}/dwi/${stem}.bvec"
ln -sf "${raw_bval}" "${in_dir}/bvals"
ln -sf "${raw_bvec}" "${in_dir}/bvecs"
# Brain mask from FDT b0 step
mask=$(ls "${stem_dir}"/*_b0_brain_mask.nii.gz 2>/dev/null | head -1)
[ -z "${mask}" ] && { log "no brain mask"; exit 1; }
ln -sf "${mask}" "${in_dir}/nodif_brain_mask.nii.gz"

log "bedpostx input ready at ${in_dir}"
ls -la "${in_dir}/"

# Choose GPU vs CPU
if [ "${USE_GPU}" = "1" ] && [ -x "${FSLDIR}/bin/bedpostx_gpu" ]; then
    cmd="${FSLDIR}/bin/bedpostx_gpu"
    log "using ${cmd} (GPU)"
else
    cmd="${FSLDIR}/bin/bedpostx"
    log "using ${cmd} (CPU — slow!)"
fi

log "launching bedpostx on ${SUBJECT} ${SES} (~30-60 min GPU / ~6 hr CPU)"
"${cmd}" "${in_dir}" 2>&1 | tail -10
log "bedpostx done. Outputs at ${in_dir}.bedpostX/"
