#!/usr/bin/env bash
# Wire all existing per-tool outputs for sub-1003 into the canonical integrated
# tree under /data/datasets/smri-fm-cmp/integrated/ds004856/sub-1003/. Symlinks
# rather than copies — keeps the GBs of FastSurfer/T1Prep/SynthSeg/etc. in
# their canonical per-tool location and just provides one tree to navigate.
#
# Idempotent: existing symlinks are replaced. New tools that haven't run yet
# leave their slot empty (and the manifest reports MISSING).
set -euo pipefail
SUBJECT="${SUBJECT:-sub-1003}"
DATASET="${DATASET:-ds004856}"
INT_ROOT="/data/datasets/smri-fm-cmp/integrated/${DATASET}/${SUBJECT}"
SRC_ROOT="/data/datasets/smri-fm-cmp"
RAW_ROOT="/data/raw/openneuro/${DATASET}/${SUBJECT}"

mkdir -p "${INT_ROOT}"

link_if_exists() {
    # link_if_exists <source> <dest>; returns 0 if linked, 1 if source missing.
    # Caller bumps `linked` on success and tracks missing via a separate
    # if-test. We deliberately don't combine the counters with `||` because
    # arithmetic-expansion `linked=$((linked+1))` always succeeds and would
    # mask the failure.
    local src="$1" dst="$2"
    if [ ! -e "${src}" ]; then
        missing=$((missing+1))
        return 1
    fi
    rm -f "${dst}"
    ln -s "${src}" "${dst}"
    return 0
}

linked=0
missing=0

for ses in ses-wave1 ses-wave2 ses-wave3; do
    ses_dir="${INT_ROOT}/${ses}"
    mkdir -p "${ses_dir}"/{anat,dwi,func/rest,func/Hypercapnia,func/Scenes,func/Words,func/VentralVisual,perf,pet/amyloid_18FAV45,pet/tau_18FAV1451}

    # --- anat: per-tool morphometry outputs
    link_if_exists "${SRC_ROOT}/fastsurfer/${DATASET}/${SUBJECT}_${ses}" \
                   "${ses_dir}/anat/fastsurfer" && linked=$((linked+1))
    link_if_exists "${SRC_ROOT}/t1prep/${DATASET}/${SUBJECT}_${ses}" \
                   "${ses_dir}/anat/t1prep" && linked=$((linked+1))
    # MedARC SynthSeg lives at <sub>/<sub>/<ses>/anat/* — link the per-session anat dir
    if [ -d "${SRC_ROOT}/medarc-smri-fm/${DATASET}/${SUBJECT}/${SUBJECT}/${ses}/anat" ]; then
        link_if_exists "${SRC_ROOT}/medarc-smri-fm/${DATASET}/${SUBJECT}/${SUBJECT}/${ses}/anat" \
                       "${ses_dir}/anat/medarc_preproc" && linked=$((linked+1))
        # Find synthseg subdir for this ses
        synthseg_anat="$(find "${SRC_ROOT}/medarc-smri-fm/${DATASET}/${SUBJECT}/synthseg" -path "*${ses}/anat" 2>/dev/null | head -1)"
        if [ -n "${synthseg_anat}" ]; then
            link_if_exists "${synthseg_anat}" "${ses_dir}/anat/synthseg" && linked=$((linked+1))
        fi
    fi
    # BrainIAC preproc is one .nii.gz per session
    link_if_exists "${SRC_ROOT}/brainiac-preproc/${DATASET}/${SUBJECT}_${ses}.nii.gz" \
                   "${ses_dir}/anat/brainiac_preproc.nii.gz" && linked=$((linked+1))

    # --- dwi: FSL FDT
    link_if_exists "${SRC_ROOT}/fsl/${DATASET}/dwi/${SUBJECT}_${ses}" \
                   "${ses_dir}/dwi/fsl_fdt" && linked=$((linked+1))

    # --- perf: FSL oxford_asl (only ses-wave1 + ses-wave3 for sub-1003)
    asl_dir="${SRC_ROOT}/fsl/${DATASET}/asl/${SUBJECT}_${ses}_run-1"
    link_if_exists "${asl_dir}" "${ses_dir}/perf/oxford_asl" && linked=$((linked+1))

    # --- func/rest: MELODIC ICA outputs (one per run; aggregate as melodic_run-N)
    for melodic in "${SRC_ROOT}/fsl/${DATASET}/melodic/${SUBJECT}_${ses}_run-"*.ica; do
        if [ -d "${melodic}" ]; then
            run=$(basename "${melodic}" | grep -oE 'run-[0-9]+')
            link_if_exists "${melodic}" "${ses_dir}/func/rest/melodic_${run}.ica" && \
                linked=$((linked+1))
        fi
    done

    # --- func/<task>: FEAT first-level outputs per run
    for task in Scenes Words VentralVisual Hypercapnia; do
        for feat in "${SRC_ROOT}/fsl/${DATASET}/feat/${SUBJECT}_${ses}_${task}_run-"*.feat; do
            if [ -d "${feat}" ]; then
                run=$(basename "${feat}" .feat | grep -oE 'run-[0-9]+')
                link_if_exists "${feat}" "${ses_dir}/func/${task}/feat_${run}.feat" && \
                    linked=$((linked+1))
            fi
        done
    done

    # --- func/Hypercapnia: vpjax CVR pre-stage (separate from FEAT)
    cvr_dir="${SRC_ROOT}/fsl/${DATASET}/cvr/${SUBJECT}_${ses}_run-1"
    link_if_exists "${cvr_dir}" "${ses_dir}/func/Hypercapnia/cvr_vpjax" || true

    # --- pet: not yet processed; placeholder for amyloid + tau
done

# --- raw symlinks for downstream tools that want to read from BIDS
mkdir -p "${INT_ROOT}/raw"
ln -sfn "${RAW_ROOT}" "${INT_ROOT}/raw/bids" 2>/dev/null

echo "linked=${linked}  missing-or-empty=${missing}"
echo "tree:"
find "${INT_ROOT}" -maxdepth 3 -type l 2>/dev/null | sort | sed 's/^/  /'
