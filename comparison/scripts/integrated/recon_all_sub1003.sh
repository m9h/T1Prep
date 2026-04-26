#!/usr/bin/env bash
# Upstream FreeSurfer 8.2.0 recon-all (cross-sectional) on sub-1003.
#
# Replaces the failed FastSurfer recon_surf path. The neurodebian-built
# FS 7.4.1 .deb in fastsurfer-full lacks the average/ atlas (e.g.
# RB_all_2020-01-02.gca needed by mri_em_register), and we don't have a
# freesurfer-data_7.4.1 .deb. Switching to upstream recon-all in
# freesurfer-arm:8.2.0 — slower but our 8.2.0 .deb suite has the full
# atlas data.
#
# Per-scan time: ~4-6 hr (FS 8.2.0 has SynthStrip + SynthSeg integrated,
# which is faster than legacy FS 7 for those steps; surface refinement
# dominates the rest).
#
# Output: standard FS subject dir at
#   ${SUBJECTS_DIR}/sub-1003_<ses>/{mri,surf,label,stats,scripts,...}/
#
# Default SUBJECTS_DIR is the canonical integrated tree's longitudinal/
# subdir so the longitudinal stream can chain off these outputs directly
# without further symlink games.
set -euo pipefail

SUBJECT="${SUBJECT:-sub-1003}"
DATASET="${DATASET:-ds004856}"
RAW_ROOT="/data/raw/openneuro/${DATASET}"
SUBJECTS_DIR_HOST="${SUBJECTS_DIR:-/data/datasets/smri-fm-cmp/integrated/${DATASET}/${SUBJECT}/longitudinal}"
IMG="${IMG:-freesurfer-arm:8.2.0}"
PARALLEL="${PARALLEL:-3}"

mkdir -p "${SUBJECTS_DIR_HOST}"
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

run_one() {
    local ses="$1"
    local sid="${SUBJECT}_${ses}"
    local logfile="/tmp/recon_all_${sid}.log"

    if [ -f "${SUBJECTS_DIR_HOST}/${sid}/surf/lh.pial" ] && \
       [ -f "${SUBJECTS_DIR_HOST}/${sid}/surf/rh.pial" ]; then
        log "skip ${sid} (lh.pial + rh.pial already present)"
        return 0
    fi

    local t1
    t1=$(find "${RAW_ROOT}/${SUBJECT}/${ses}/anat" -name "*_acq-MPRAGE_run-1_T1w.nii.gz" | head -1)
    [ -z "${t1}" ] && { log "no T1 for ${sid}"; return 0; }
    local anat_dir t1_base
    anat_dir="$(dirname "${t1}")"
    t1_base="$(basename "${t1}")"

    log "recon-all ${sid} (log → ${logfile}, ~4-6 hr)"
    docker run --gpus all --rm \
      --user "$(id -u):$(id -g)" \
      -v "${anat_dir}:/data:ro" \
      -v "${SUBJECTS_DIR_HOST}:/subjects:rw" \
      -v "${HOME}/license.txt:/usr/lib/freesurfer/license.txt:ro" \
      -e SUBJECTS_DIR=/subjects \
      -e FS_LICENSE=/usr/lib/freesurfer/license.txt \
      --entrypoint bash \
      "${IMG}" -c "source /usr/lib/freesurfer/SetUpFreeSurfer.sh && recon-all -i /data/${t1_base} -s ${sid} -all -openmp 4 -3T" \
      > "${logfile}" 2>&1
    local rc=$?
    if [ $rc -eq 0 ]; then
        log "  ${sid} recon-all done"
    else
        log "  ${sid} FAILED (rc=$rc) — see ${logfile}"
    fi
}

# Fan out per-session with PARALLEL bound
running=0
for ses in $(ls "${RAW_ROOT}/${SUBJECT}" 2>/dev/null | grep '^ses-'); do
    run_one "${ses}" &
    running=$((running+1))
    if [ "${running}" -ge "${PARALLEL}" ]; then
        wait -n
        running=$((running-1))
    fi
done
wait
log "recon-all finished. Outputs under ${SUBJECTS_DIR_HOST}/${SUBJECT}_*/"
