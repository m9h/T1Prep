#!/usr/bin/env bash
# CVR (cerebrovascular reactivity) processing for DLBS Hypercapnia BOLD,
# using FSL for motion-correction + masking and vpjax for the optional
# Balloon-Windkessel parameter inversion.
#
# Pipeline per scan:
#   1. mcflirt motion correction
#   2. brain mask via bet on the mean func
#   3. (optional) coregister to FastSurfer T1; pull GM mask if available
#   4. Save the cleaned 4D BOLD + GM mask + motion params to ${OUT_ROOT}/cvr/
#   5. Hand off to cvr_vpjax_invert.py for the actual CVR estimation.
#
# DLBS Hypercapnia paradigm: 10-min block-design with CO2 challenges. The
# README does NOT describe block timing and there is no events.tsv for
# Hypercapnia — we rely on a data-driven paradigm extracted from the
# whole-brain signal mean (cf. Liu et al. 2017, "Cerebrovascular reactivity
# (CVR) MRI with CO2 challenge: a technical review", NeuroImage 187:104-115).
#
# Output:
#   ${OUT_ROOT}/cvr/<sub>_<ses>_<run>/{
#       mc.nii.gz, mc_params.par,
#       brain_mask.nii.gz, mean_func.nii.gz,
#       gm_mask.nii.gz       (if FastSurfer T1 cohereg succeeded)
#   }
#
# vpjax inversion runs separately (Python, JAX) — see cvr_vpjax_invert.py.
#
# Usage:
#   cvr_vpjax_dlbs.sh                    # all subjects
#   cvr_vpjax_dlbs.sh sub-1003 sub-1007  # specific subjects
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/common.sh"

SUBJECTS=("$@")
[ ${#SUBJECTS[@]} -eq 0 ] && SUBJECTS=("${DLBS_SUBJECTS[@]}")

run_one() {
    local sub="$1" ses="$2" bold="$3"
    local stem out_dir
    stem="$(basename "${bold}" .nii.gz)"
    local run; run=$(echo "${stem}" | grep -oE 'run-[0-9]+' || echo run-1)
    out_dir="${OUT_ROOT}/cvr/${sub}_${ses}_${run}"

    if [ -s "${out_dir}/mc.nii.gz" ] && [ -s "${out_dir}/brain_mask.nii.gz" ]; then
        log "skip ${sub} ${ses} ${run} (CVR pre-stage already done)"
        return 0
    fi
    mkdir -p "${out_dir}"

    log "cvr-pre ${sub} ${ses} ${run}"

    # 1. motion correction
    "${FSLDIR}/bin/mcflirt" \
        -in "${bold}" -out "${out_dir}/mc" -refvol 0 \
        -plots -mats >/dev/null

    # 2. mean func + brain mask
    "${FSLDIR}/bin/fslmaths" "${out_dir}/mc" -Tmean "${out_dir}/mean_func"
    "${FSLDIR}/bin/bet" "${out_dir}/mean_func" "${out_dir}/mean_func_brain" \
        -m -f 0.3 >/dev/null
    mv "${out_dir}/mean_func_brain_mask.nii.gz" "${out_dir}/brain_mask.nii.gz"

    # 3. coreg to FastSurfer T1 if available — gives us a per-tissue mask later
    local fs_mri="${FS_ROOT}/${sub}_${ses}/mri"
    if [ -f "${fs_mri}/orig.mgz" ]; then
        local t1nii="${out_dir}/t1_native.nii.gz"
        "${FSLDIR}/bin/mri_convert" "${fs_mri}/orig.mgz" "${t1nii}" >/dev/null 2>&1 || \
            "${FREESURFER_HOME:-/usr/lib/freesurfer}/bin/mri_convert" \
                "${fs_mri}/orig.mgz" "${t1nii}" >/dev/null 2>&1 || \
            log "  WARN no mri_convert; skipping coreg (T1 mgz→nii)"

        if [ -f "${t1nii}" ]; then
            "${FSLDIR}/bin/flirt" \
                -in "${out_dir}/mean_func_brain" -ref "${t1nii}" \
                -out "${out_dir}/func_in_t1" \
                -omat "${out_dir}/func2t1.mat" \
                -dof 6 >/dev/null 2>&1
        fi
    else
        log "  no FastSurfer mri/orig.mgz for ${sub}_${ses} — skipping coreg"
    fi

    log "  ${sub} ${ses} ${run} pre-stage done"
}

for sub in "${SUBJECTS[@]}"; do
    for ses in $(list_sessions "${sub}"); do
        while IFS= read -r bold; do
            [ -n "${bold}" ] && run_one "${sub}" "${ses}" "${bold}"
        done < <(list_runs "${sub}" "${ses}" func '*_task-Hypercapnia_*_bold.nii.gz')
    done
done

log "CVR pre-stage done. Outputs under ${OUT_ROOT}/cvr/"
log "Next: python ${SCRIPT_DIR}/cvr_vpjax_invert.py --cvr-root ${OUT_ROOT}/cvr"
