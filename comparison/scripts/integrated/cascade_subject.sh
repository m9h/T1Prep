#!/usr/bin/env bash
# Per-subject post-surface cascade for any DLBS subject (Legion-side).
#
# Runs sequentially:
#   1. segment_subregions  — hippo-amygdala / brainstem / thalamus per session
#   2. PETSurfer           — gtmseg + mri_coreg + mri_gtmpvc + gtmstats2table
#                            for each tracer/session combination present
#
# Both stages reuse the parameterized sub1003 templates. Only required
# input: $SUBJECT exported (or pass as $1).
#
# Usage:
#   bash cascade_subject.sh sub-1007
#   SUBJECT=sub-1007 bash cascade_subject.sh
#
# Pre-condition: ${FS_ROOT}/${SUBJECT}_ses-wave*/scripts/recon-all.done
# present (cross-sectional FreeSurfer outputs exist). Ideally base + long
# also done so the cross-sectional segment_subregions matches longitudinal
# expectations later.
set -euo pipefail

SUBJECT="${SUBJECT:-${1:-}}"
DATASET="${DATASET:-ds004856}"
FS_ROOT="/data/datasets/smri-fm-cmp/freesurfer/${DATASET}"
LOG_DIR="${FS_ROOT}/_logs/cascade"
mkdir -p "${LOG_DIR}"

if [ -z "${SUBJECT}" ]; then
    echo "ERROR: pass a subject ID (e.g. sub-1007) as \$1 or \$SUBJECT" >&2
    exit 1
fi

log() { printf '[%s] %s\n' "$(date -Iseconds)" "$*" | tee -a "${LOG_DIR}/${SUBJECT}.log" >&2; }

# Verify cross-sectional outputs exist
for ses in ses-wave1 ses-wave2 ses-wave3; do
    if [ ! -f "${FS_ROOT}/${SUBJECT}_${ses}/surf/lh.pial" ]; then
        log "missing ${SUBJECT}_${ses}/surf/lh.pial — abort"
        exit 1
    fi
done

log "=== ${SUBJECT} cascade start ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1) segment_subregions
log "--- segment_subregions ---"
SUBJECT="${SUBJECT}" bash "${SCRIPT_DIR}/segment_subregions_sub1003.sh" \
    >> "${LOG_DIR}/${SUBJECT}.segment_subregions.log" 2>&1 \
    && log "segment_subregions done" \
    || log "segment_subregions FAILED — see ${LOG_DIR}/${SUBJECT}.segment_subregions.log"

# 2) PETSurfer
log "--- PETSurfer ---"
SUBJECT="${SUBJECT}" bash "${SCRIPT_DIR}/petsurfer_sub1003.sh" \
    >> "${LOG_DIR}/${SUBJECT}.petsurfer.log" 2>&1 \
    && log "PETSurfer done" \
    || log "PETSurfer FAILED — see ${LOG_DIR}/${SUBJECT}.petsurfer.log"

log "=== ${SUBJECT} cascade complete ==="
touch "${FS_ROOT}/_logs/CASCADE_${SUBJECT}_DONE"
