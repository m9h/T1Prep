#!/usr/bin/env bash
# FreeSurfer longitudinal recon-all stream for sub-1003 (3 waves).
#
# Pipeline (Reuter et al. 2012, NeuroImage 61:1402):
#   1. Cross-sectional recon-all per timepoint  (we use FastSurfer recon_surf
#      to substitute — already running; outputs in
#      /data/datasets/smri-fm-cmp/fastsurfer/ds004856/sub-1003_ses-waveN/)
#   2. recon-all -base <subj> -tp ses-wave1 -tp ses-wave2 -tp ses-wave3 -all
#      → builds within-subject unbiased template via mri_robust_template
#   3. recon-all -long ses-waveN <subj> -all   (× 3, one per timepoint)
#      → re-runs each timepoint using the base as initial alignment + prior
#
# Outputs annual atrophy rate maps + reduced within-subject variability for
# longitudinal stats. The standard analysis for DLBS-style 3-wave aging
# studies. See sub-1003_freesurfer_sota.md for full rationale.
#
# Container: freesurfer-arm:8.2.0 (the new standalone FS base — NOT
# fastsurfer-full, since the longitudinal stream uses upstream recon-all,
# not FastSurfer's recon_surf).
#
# Prerequisites:
#   - All 3 cross-sectional recon_surf outputs must have lh.pial + rh.pial
#     and the standard FS subject dir layout (mri/, surf/, label/, stats/).
#
# Output:
#   ${SUBJECTS_DIR}/sub-1003.base/                            # within-subject template
#   ${SUBJECTS_DIR}/sub-1003_ses-wave{1,2,3}.long.sub-1003/   # per-tp longitudinal recon
#
# Time: -base ~2-3 hr; -long ~1.5 hr × 3 (parallelisable to ~1.5 hr wall).
set -euo pipefail

SUBJECT="${SUBJECT:-sub-1003}"
DATASET="${DATASET:-ds004856}"
FS_ROOT="/data/datasets/smri-fm-cmp/fastsurfer/${DATASET}"
LONG_ROOT="/data/datasets/smri-fm-cmp/integrated/${DATASET}/${SUBJECT}/longitudinal"
IMG="${IMG:-freesurfer-arm:8.2.0}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

# Verify cross-sectional surfaces exist
SESSIONS=()
for ses in ses-wave1 ses-wave2 ses-wave3; do
    sid="${SUBJECT}_${ses}"
    if [ -f "${FS_ROOT}/${sid}/surf/lh.pial" ] && [ -f "${FS_ROOT}/${sid}/surf/rh.pial" ]; then
        SESSIONS+=("${sid}")
    else
        log "WARN: ${sid} surfaces not yet ready — skipping (re-run after recon_surf)"
    fi
done

if [ ${#SESSIONS[@]} -lt 2 ]; then
    log "ERROR: need at least 2 timepoints with surfaces, found ${#SESSIONS[@]}"
    exit 1
fi

mkdir -p "${LONG_ROOT}"
SUBJECTS_DIR="${LONG_ROOT}"
log "longitudinal recon for ${SUBJECT} with ${#SESSIONS[@]} timepoints: ${SESSIONS[*]}"
log "SUBJECTS_DIR = ${SUBJECTS_DIR}"

# Symlink cross-sectional outputs into SUBJECTS_DIR so recon-all -base can find them
for sid in "${SESSIONS[@]}"; do
    [ -e "${SUBJECTS_DIR}/${sid}" ] || ln -s "${FS_ROOT}/${sid}" "${SUBJECTS_DIR}/${sid}"
done

# --- Stage 2: -base ---
TP_FLAGS=()
for sid in "${SESSIONS[@]}"; do TP_FLAGS+=(-tp "${sid}"); done

log ">>> recon-all -base ${SUBJECT} (template construction, ~2-3 hr)"
docker run --gpus all --rm \
  --user "$(id -u):$(id -g)" \
  -v "${SUBJECTS_DIR}:/subjects:rw" \
  -v "${HOME}/license.txt:/usr/lib/freesurfer/license.txt:ro" \
  -e SUBJECTS_DIR=/subjects \
  -e FS_LICENSE=/usr/lib/freesurfer/license.txt \
  --entrypoint bash \
  "${IMG}" -c "recon-all -base ${SUBJECT} ${TP_FLAGS[*]} -all -openmp 4" 2>&1 | tail -10

if [ ! -d "${SUBJECTS_DIR}/${SUBJECT}/surf" ]; then
    log "ERROR: -base failed (no surf/ in ${SUBJECTS_DIR}/${SUBJECT}/)"
    exit 1
fi
log ">>> -base done"

# --- Stage 3: -long per timepoint ---
log ">>> recon-all -long × ${#SESSIONS[@]} timepoints in parallel"
PIDS=()
for sid in "${SESSIONS[@]}"; do
    log_per="${SUBJECTS_DIR}/${sid}.long.${SUBJECT}/scripts/recon-all-long.log"
    docker run --gpus all --rm \
      --user "$(id -u):$(id -g)" \
      -v "${SUBJECTS_DIR}:/subjects:rw" \
      -v "${HOME}/license.txt:/usr/lib/freesurfer/license.txt:ro" \
      -e SUBJECTS_DIR=/subjects \
      -e FS_LICENSE=/usr/lib/freesurfer/license.txt \
      --entrypoint bash \
      "${IMG}" -c "recon-all -long ${sid} ${SUBJECT} -all -openmp 4" \
      > "/tmp/recon_long_${sid}.log" 2>&1 &
    PIDS+=("$!")
done
log "  spawned PIDs: ${PIDS[*]}"
wait "${PIDS[@]}"

log "longitudinal recon complete"
ls -la "${SUBJECTS_DIR}/" | grep -E "sub-1003|long" | head
