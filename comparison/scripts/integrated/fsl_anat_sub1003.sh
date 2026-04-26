#!/usr/bin/env bash
# fsl_anat — FSL's structural-T1 one-shot pipeline for sub-1003.
#
# Per-session output (~30-60 min/scan):
#   - reorient + crop
#   - bias-field correction (FAST)
#   - registration to MNI152 (FNIRT/FLIRT)
#   - brain extraction (BET)
#   - tissue segmentation (FAST: GM, WM, CSF probability maps)
#   - subcortical segmentation (FIRST)
#
# Output: ${OUT_ROOT}/anat/<sub>_<ses>.anat/
#   T1.nii.gz, T1_biascorr.nii.gz, T1_biascorr_brain.nii.gz, T1_biascorr_brain_mask.nii.gz
#   T1_fast_pve_{0,1,2}.nii.gz   (CSF, GM, WM)
#   T1_fast_seg.nii.gz            (3-class hard seg)
#   first_results/                (FIRST subcortical)
#   T1_to_MNI_nonlin_field.nii.gz, T1_to_MNI_lin.mat
#
# This is the FSL-native counterpart to FastSurfer/T1Prep/SynthSeg. We get:
#   - FAST tissue PVE maps for ASL partial-volume correction
#   - FIRST subcortical seg as a 5th comparison column for ridge
#   - MNI registration (T1_to_MNI_*) reusable by downstream tools
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/../fsl/common.sh"

SUBJECT="${SUBJECT:-sub-1003}"

for ses in $(list_sessions "${SUBJECT}"); do
    t1=$(find "${RAW_ROOT}/${SUBJECT}/${ses}/anat" -name "*_acq-MPRAGE_run-1_T1w.nii.gz" 2>/dev/null | head -1)
    [ -z "${t1}" ] && { log "no T1 for ${SUBJECT} ${ses}"; continue; }

    out_dir="${OUT_ROOT}/anat/${SUBJECT}_${ses}.anat"
    if [ -s "${out_dir}/T1_biascorr_brain.nii.gz" ]; then
        log "skip ${SUBJECT} ${ses} (fsl_anat done)"
        continue
    fi
    rm -rf "${out_dir}"  # fsl_anat refuses to clobber

    log "fsl_anat ${SUBJECT} ${ses} (${t1##*/})"
    "${FSLDIR}/bin/fsl_anat" \
        -i "${t1}" -o "${out_dir%.anat}" \
        --nocleanup --nosubcortseg 2>&1 | tail -3
    # Note: --nosubcortseg skips FIRST initially (FIRST is slow ~15 min;
    # add it back for the final SOTA run). Drop the flag to enable.

    log "  ${SUBJECT} ${ses} fsl_anat done"
done

log "fsl_anat finished. Outputs under ${OUT_ROOT}/anat/${SUBJECT}_*.anat/"
