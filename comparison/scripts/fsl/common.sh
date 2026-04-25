#!/usr/bin/env bash
# Shared environment for the FSL DLBS pipeline scripts.
# Sourced by fdt_dlbs.sh / melodic_dlbs.sh / feat_dlbs.sh / oxford_asl_dlbs.sh.
#
# FSL is host-installed at /home/mhough/fsl (FSL 6.0.7.19 conda-aarch64);
# we don't ship a docker container for these — host FSL is faster and
# matches what the morphometry team already uses.
#
# All output goes under /data/datasets/smri-fm-cmp/fsl/ to keep it on the NAS.

# --- FSL env
export FSLDIR="${FSLDIR:-/home/mhough/fsl}"
export PATH="${FSLDIR}/bin:${PATH}"
export FSLOUTPUTTYPE="${FSLOUTPUTTYPE:-NIFTI_GZ}"
export FSLMULTIFILEQUIT="${FSLMULTIFILEQUIT:-TRUE}"
[ -f "${FSLDIR}/etc/fslconf/fsl.sh" ] && . "${FSLDIR}/etc/fslconf/fsl.sh"

# --- DLBS paths
export DATASET="${DATASET:-ds004856}"
export RAW_ROOT="${RAW_ROOT:-/data/raw/openneuro/${DATASET}}"
export OUT_ROOT="${OUT_ROOT:-/data/datasets/smri-fm-cmp/fsl/${DATASET}}"
export FS_ROOT="${FS_ROOT:-/data/datasets/smri-fm-cmp/fastsurfer/${DATASET}}"

# --- 23-subject benchmark cohort (everyone with FastSurfer outputs)
export DLBS_SUBJECTS=(
    sub-1003 sub-1007 sub-1013 sub-1022 sub-1023 sub-103 sub-1031
    sub-1045 sub-1054 sub-1058 sub-1084 sub-1093 sub-1139 sub-1141
    sub-1146 sub-1149 sub-1153 sub-1157 sub-1172 sub-1175 sub-1183
    sub-1200 sub-1220
)

mkdir -p "${OUT_ROOT}"

# --- helpers
log() {
    printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2
}

list_runs() {
    # list_runs <subject> <session> <subdir> <glob>
    # e.g. list_runs sub-1003 ses-wave1 dwi '*_acq-DTI_*_dwi.nii.gz'
    find "${RAW_ROOT}/$1/$2/$3" -maxdepth 1 -name "$4" 2>/dev/null | sort
}

list_sessions() {
    # list_sessions <subject>
    ls -1 "${RAW_ROOT}/$1" 2>/dev/null | grep '^ses-' || true
}
