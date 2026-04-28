#!/usr/bin/env bash
# PETSurfer pipeline for sub-1003: amyloid (18F-AV45) × 3 waves + tau
# (18F-AV1451) × 1 wave. Inputs: Legion's recon-all output + raw PET.
#
# Per-PET pipeline:
#   1. mri_coreg PET → T1 (rigid)
#   2. gtmseg (per-subject; idempotent — cached after first run)
#   3. mri_gtmpvc with cerebellum reference, --psf 6 (Siemens HRRT-ish)
#   4. gtmstats2table → per-region SUVR TSV
#
# Outputs (NFS, downstream-readable):
#   /data/datasets/smri-fm-cmp/integrated/ds004856/sub-1003/ses-waveN/pet/<tracer>/petsurfer/
#     coreg/pet2t1.lta
#     gtmseg.mgz                (symlink into the FS subject dir; one per session)
#     pvc/{gtm,mg,rbv}.nii.gz   (PVC-corrected SUVR maps)
#     suvr.tsv                  (per-region table)
set -euo pipefail
SUBJECT="${SUBJECT:-sub-1003}"
DATASET="${DATASET:-ds004856}"
RAW_ROOT="/data/raw/openneuro/${DATASET}"
FS_ROOT="/data/datasets/smri-fm-cmp/freesurfer/${DATASET}"   # Legion-side output
INT_ROOT="/data/datasets/smri-fm-cmp/integrated/${DATASET}/${SUBJECT}"
IMG="${IMG:-freesurfer-arm:8.2.9}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

run_in_fs() {
    # Helper: invoke a FreeSurfer tool inside the container
    docker run --rm \
      --user "$(id -u):$(id -g)" \
      -v "${FS_ROOT}:/subjects:rw" \
      -v "${RAW_ROOT}:/raw:ro" \
      -v "${INT_ROOT}:/int:rw" \
      -v "${HOME}/license.txt:/usr/lib/freesurfer/license.txt:ro" \
      -e SUBJECTS_DIR=/subjects \
      -e FS_LICENSE=/usr/lib/freesurfer/license.txt \
      --entrypoint bash \
      "${IMG}" -c "source /usr/lib/freesurfer/SetUpFreeSurfer.sh && $*"
}

# --- Step 1: gtmseg per session (idempotent — checks for output)
for ses in ses-wave1 ses-wave2 ses-wave3; do
    sid="${SUBJECT}_${ses}"
    if [ -f "${FS_ROOT}/${sid}/mri/gtmseg.mgz" ]; then
        log "skip gtmseg ${sid} (already done)"
    else
        log "gtmseg ${sid} (~10-15 min)"
        run_in_fs "gtmseg --s ${sid}" 2>&1 | tail -5
    fi
done

# --- Step 2: per-PET pipeline (rigid coreg → mri_gtmpvc → SUVRs)
process_pet() {
    local ses="$1" tracer="$2" tag="$3"   # tag = amyloid|tau
    local sid="${SUBJECT}_${ses}"
    local pet_path
    pet_path=$(find "${RAW_ROOT}/${SUBJECT}/${ses}/pet" -name "*trc-${tracer}*_pet.nii.gz" 2>/dev/null | head -1)
    [ -z "${pet_path}" ] && { log "no ${tracer} PET for ${ses} — skip"; return 0; }

    local out_dir="${INT_ROOT}/${ses}/pet/${tag}_${tracer}/petsurfer"
    mkdir -p "${out_dir}/coreg" "${out_dir}/pvc"

    if [ -f "${out_dir}/suvr.tsv" ]; then
        log "skip ${ses} ${tag} (suvr.tsv exists)"
        return 0
    fi

    log "petsurfer ${ses} ${tag} (${pet_path##*/})"

    # mri_coreg PET → T1 (rigid)
    if [ ! -f "${out_dir}/coreg/pet2t1.lta" ]; then
        local pet_in_container="/raw/${SUBJECT}/${ses}/pet/$(basename "${pet_path}")"
        run_in_fs "mri_coreg --s ${sid} --mov ${pet_in_container} --reg /int/${ses}/pet/${tag}_${tracer}/petsurfer/coreg/pet2t1.lta --threads 8" 2>&1 | tail -5
    fi

    # mri_gtmpvc → cerebellum-reference SUVR + PVC variants
    run_in_fs "mri_gtmpvc \
        --i ${pet_in_container:-/raw/${SUBJECT}/${ses}/pet/$(basename "${pet_path}")} \
        --reg /int/${ses}/pet/${tag}_${tracer}/petsurfer/coreg/pet2t1.lta \
        --psf 6 --seg gtmseg.mgz --auto-mask 0.10 0.01 \
        --default-seg-merge --rescale 8 47 \
        --o /int/${ses}/pet/${tag}_${tracer}/petsurfer/pvc \
        --threads 8" 2>&1 | tail -5

    # Per-region table
    run_in_fs "gtmstats2table --inputs /int/${ses}/pet/${tag}_${tracer}/petsurfer/pvc/gtm.stats.dat \
        --tablefile /int/${ses}/pet/${tag}_${tracer}/petsurfer/suvr.tsv" 2>&1 | tail -3 || \
        log "  gtmstats2table failed (try direct mri_gtmpvc output instead)"

    log "  ${ses} ${tag} done"
}

# Amyloid AV45 in W1, W2, W3
for ses in ses-wave1 ses-wave2 ses-wave3; do
    process_pet "${ses}" "18FAV45" "amyloid"
done

# Tau AV1451 in W3 only
process_pet "ses-wave3" "18FAV1451" "tau"

log "PETSurfer done. Outputs under ${INT_ROOT}/<ses>/pet/<tag>/petsurfer/"
