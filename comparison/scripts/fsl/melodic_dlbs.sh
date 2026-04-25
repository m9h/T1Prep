#!/usr/bin/env bash
# MELODIC ICA on DLBS resting-state fMRI.
#
# DLBS resting BOLD: 64x64x43, TR=2 s, ~187-211 vols (varies by wave).
#
# Per-scan workflow (single-subject ICA):
#   1. mcflirt motion correction
#   2. brain mask via bet (mean func)
#   3. high-pass filter (Nyquist-aware, 100 s)
#   4. melodic --varnorm --report (auto-dimensionality estimate)
#
# Output:
#   ${OUT_ROOT}/melodic/<sub>_<ses>_<run>.ica/
#       filtered_func_data.nii.gz
#       melodic_IC.nii.gz, melodic_mix
#       report/
#
# Usage:
#   melodic_dlbs.sh                    # all 23 subjects, all rest runs
#   melodic_dlbs.sh sub-1003           # one subject
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/common.sh"

SUBJECTS=("$@")
[ ${#SUBJECTS[@]} -eq 0 ] && SUBJECTS=("${DLBS_SUBJECTS[@]}")

run_one() {
    local sub="$1" ses="$2" bold_path="$3"
    local stem out_dir
    stem="$(basename "${bold_path}" .nii.gz)"
    local run
    run=$(echo "${stem}" | grep -oE 'run-[0-9]+' || echo run-1)
    out_dir="${OUT_ROOT}/melodic/${sub}_${ses}_${run}.ica"

    if [ -s "${out_dir}/melodic_IC.nii.gz" ]; then
        log "skip ${sub} ${ses} ${run} (MELODIC done)"
        return 0
    fi
    mkdir -p "${out_dir}"

    log "melodic ${sub} ${ses} ${run} (${stem})"
    local tmp; tmp=$(mktemp -d)
    trap "rm -rf ${tmp}" RETURN

    # 1. motion-correct
    "${FSLDIR}/bin/mcflirt" -in "${bold_path}" -out "${tmp}/mc" -refvol 0 -plots >/dev/null

    # 2. brain mask
    "${FSLDIR}/bin/fslmaths" "${tmp}/mc" -Tmean "${tmp}/meanfunc"
    "${FSLDIR}/bin/bet" "${tmp}/meanfunc" "${tmp}/meanfunc_brain" -m -f 0.3 >/dev/null

    # 3. apply mask + high-pass filter (sigma in vols; HP=100s, TR=2s → cutoff=50 vols → sigma=25)
    "${FSLDIR}/bin/fslmaths" "${tmp}/mc" -mas "${tmp}/meanfunc_brain_mask" "${tmp}/mc_brain"
    "${FSLDIR}/bin/fslmaths" "${tmp}/mc_brain" -bptf 25 -1 "${tmp}/mc_brain_hp"

    # 4. melodic
    "${FSLDIR}/bin/melodic" \
        -i "${tmp}/mc_brain_hp" -o "${out_dir}" \
        --mask="${tmp}/meanfunc_brain_mask" \
        --nobet --varnorm --report --tr=2 >/dev/null 2>&1 || \
        log "  WARN melodic returned non-zero (still produced outputs?)"

    if [ -s "${out_dir}/melodic_IC.nii.gz" ]; then
        local n_ics
        n_ics=$("${FSLDIR}/bin/fslval" "${out_dir}/melodic_IC.nii.gz" dim4 2>/dev/null || echo "?")
        log "  ${sub} ${ses} ${run} done — ${n_ics} ICs"
    else
        log "  ERR ${sub} ${ses} ${run}: no melodic_IC.nii.gz produced"
    fi
}

for sub in "${SUBJECTS[@]}"; do
    for ses in $(list_sessions "${sub}"); do
        while IFS= read -r bold; do
            [ -n "${bold}" ] && run_one "${sub}" "${ses}" "${bold}"
        done < <(list_runs "${sub}" "${ses}" func '*_task-rest_*_bold.nii.gz')
    done
done

log "MELODIC done. Outputs under ${OUT_ROOT}/melodic/"
