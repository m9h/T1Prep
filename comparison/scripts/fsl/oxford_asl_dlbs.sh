#!/usr/bin/env bash
# Oxford ASL pipeline (FSL fabber wrapper) for DLBS pCASL.
#
# DLBS ASL JSON (sub-1003 ses-wave1):
#   ArterialSpinLabelingType: PCASL
#   PostLabelingDelay:         1.525 s
#   LabelingDuration:          1.65 s
#   M0Type:                    Absent       (estimate from control via --casl --slicedt)
#   TotalAcquiredPairs:        30           (60 volumes total: label, control, ...)
#   AcquisitionVoxelSize:      [3, 3, 5] mm
#
# aslcontext.tsv shape: 60 rows alternating label/control.
#
# oxford_asl invokes fabber under the hood for the Bayesian Buxton kinetic
# fit — same model vpjax.perfusion.kinetic implements (just a non-differentiable
# inversion), so this gives us a numerical reference to validate vpjax later.
#
# Output:
#   ${OUT_ROOT}/asl/<sub>_<ses>/{perfusion_calib,arrival,native_space/}
#
# Usage:
#   oxford_asl_dlbs.sh                    # all 23 subjects
#   oxford_asl_dlbs.sh sub-1003 sub-1007  # specific subjects
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/common.sh"

SUBJECTS=("$@")
[ ${#SUBJECTS[@]} -eq 0 ] && SUBJECTS=("${DLBS_SUBJECTS[@]}")

# DLBS pCASL constants (from sidecar JSON; same across subjects/sessions)
PLD="1.525"      # post-labeling delay (s)
BOLUS="1.65"     # labeling duration (s)
TR="4.150847"    # asl repetition time (s)
SLICEDT="0.045"  # slice timing increment (s, 27 slices, ~1.2s per readout)

run_one() {
    local sub="$1" ses="$2" asl_path="$3"
    local stem out_dir
    stem="$(basename "${asl_path}" .nii.gz)"
    out_dir="${OUT_ROOT}/asl/${sub}_${ses}_$(echo "${stem}" | grep -oE 'run-[0-9]+' || echo run-1)"

    if [ -s "${out_dir}/native_space/perfusion_calib.nii.gz" ] || \
       [ -s "${out_dir}/native_space/perfusion.nii.gz" ]; then
        log "skip ${sub} ${ses} (oxford_asl output exists)"
        return 0
    fi
    mkdir -p "${out_dir}"

    log "oxford_asl ${sub} ${ses} (${stem})"

    # FastSurfer-derived T1 brain extraction would be ideal; oxford_asl can use
    # its own simple BET on the ASL itself in a pinch, which is what we do here
    # to keep the pipeline self-contained. Per-subject T1 hookup is in --fslanat.
    "${FSLDIR}/bin/oxford_asl" \
        -i "${asl_path}" \
        -o "${out_dir}" \
        --casl --iaf=tc --ibf=rpt \
        --bolus="${BOLUS}" --tis=$(echo "${PLD} + ${BOLUS}" | bc -l) \
        --slicedt="${SLICEDT}" \
        --fixbolus --bat=1.3 --t1=1.3 --t1b=1.65 \
        --spatial=1 --wp 2>&1 | tail -5

    log "  ${sub} ${ses} oxford_asl done"
}

for sub in "${SUBJECTS[@]}"; do
    for ses in $(list_sessions "${sub}"); do
        while IFS= read -r asl; do
            [ -n "${asl}" ] && run_one "${sub}" "${ses}" "${asl}"
        done < <(list_runs "${sub}" "${ses}" perf '*_acq-ASL_*_asl.nii.gz')
    done
done

log "oxford_asl done. Outputs under ${OUT_ROOT}/asl/"
