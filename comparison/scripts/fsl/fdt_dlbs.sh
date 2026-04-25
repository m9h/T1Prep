#!/usr/bin/env bash
# FDT pipeline (FSL diffusion toolbox) for DLBS T1-cohort subjects.
# Per-scan workflow:
#   1. eddy_correct  (no fieldmap available — uses simpler eddy_correct, not eddy_openmp)
#   2. dtifit        (FA, MD, V1 etc.)
#
# DLBS DTI = single-shell b=1000 with 30 dirs + 1 b=0; 1.75x1.75x3 mm; TR 4.41 s.
# Single-shell precludes NODDI/QSI; we report tensor metrics only.
#
# Output:
#   ${OUT_ROOT}/dwi/<sub>_<ses>/{eddy_corrected,FA,MD,L1,L2,L3,V1,V2,V3}.nii.gz
#
# Usage:
#   fdt_dlbs.sh                      # all 23 subjects, all sessions
#   fdt_dlbs.sh sub-1003 sub-1007    # specific subjects
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/common.sh"

SUBJECTS=("$@")
[ ${#SUBJECTS[@]} -eq 0 ] && SUBJECTS=("${DLBS_SUBJECTS[@]}")

run_one() {
    local sub="$1" ses="$2" dwi_path="$3"
    local stem out_dir
    stem="$(basename "${dwi_path}" .nii.gz)"
    out_dir="${OUT_ROOT}/dwi/${sub}_${ses}"
    mkdir -p "${out_dir}"

    if [ -s "${out_dir}/${stem}_FA.nii.gz" ]; then
        log "skip ${sub} ${ses} (${stem}_FA exists)"
        return 0
    fi

    log "fdt ${sub} ${ses} (${stem})"

    # Sidecars
    local bval bvec
    bval="${dwi_path%.nii.gz}.bval"
    bvec="${dwi_path%.nii.gz}.bvec"
    if [ ! -f "${bval}" ] || [ ! -f "${bvec}" ]; then
        log "  ERROR: missing bval/bvec sidecars"
        return 1
    fi

    # Brain mask from b=0 (volume 0)
    local b0="${out_dir}/${stem}_b0.nii.gz"
    local b0_brain="${out_dir}/${stem}_b0_brain.nii.gz"
    "${FSLDIR}/bin/fslroi" "${dwi_path}" "${b0}" 0 1
    "${FSLDIR}/bin/bet" "${b0}" "${b0_brain}" -m -f 0.25 >/dev/null

    # Eddy correct (legacy — no fieldmap or topup-style data in DLBS DTI)
    local eddy_out="${out_dir}/${stem}_eddy"
    if [ ! -s "${eddy_out}.nii.gz" ]; then
        "${FSLDIR}/bin/eddy_correct" "${dwi_path}" "${eddy_out}" 0 >/dev/null 2>&1
    fi

    # Tensor fit
    "${FSLDIR}/bin/dtifit" \
        --data="${eddy_out}.nii.gz" \
        --out="${out_dir}/${stem}" \
        --mask="${b0_brain%.nii.gz}_mask.nii.gz" \
        --bvecs="${bvec}" \
        --bvals="${bval}" >/dev/null

    # Quick QC log
    local fa_mean
    fa_mean=$("${FSLDIR}/bin/fslstats" "${out_dir}/${stem}_FA" -k "${b0_brain%.nii.gz}_mask" -M 2>/dev/null || echo "NA")
    log "  ${sub} ${ses} done — mean FA in mask = ${fa_mean}"
}

for sub in "${SUBJECTS[@]}"; do
    for ses in $(list_sessions "${sub}"); do
        while IFS= read -r dwi; do
            [ -n "${dwi}" ] && run_one "${sub}" "${ses}" "${dwi}"
        done < <(list_runs "${sub}" "${ses}" dwi '*_acq-DTI_*_dwi.nii.gz')
    done
done

log "FDT done. Outputs under ${OUT_ROOT}/dwi/"
