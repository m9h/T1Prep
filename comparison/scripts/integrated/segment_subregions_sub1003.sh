#!/usr/bin/env bash
# FreeSurfer segment_subregions for sub-1003 — hippo-amygdala + brainstem
# + thalamus subregions per session, longitudinal-aware mode.
#
# Input: Legion's recon-all output (cross + base + long all done).
# Tool: segment_subregions (FS 7.3+, unified Python rewrite of the legacy
# segment_HA / -brainstem-structures / segmentThalamicNuclei trio).
#
# Output: lh/rh.{hippoSfLabels,thalamicNuclei}.mgz, brainstemSsLabels.mgz
# under ${SUBJECTS_DIR}/${sid}/mri/, plus tables under stats/.
#
# Per-structure runtime: ~5-15 min on CPU, ×3 sessions × 3 structures = ~2 hr.
# Sessions parallelisable, structures sequential per session.
set -euo pipefail
SUBJECT="${SUBJECT:-sub-1003}"
DATASET="${DATASET:-ds004856}"
FS_ROOT="/data/datasets/smri-fm-cmp/freesurfer/${DATASET}"
IMG="${IMG:-freesurfer-arm:8.2.9}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

run_one_session() {
    local sid="$1"
    if [ ! -f "${FS_ROOT}/${sid}/scripts/recon-all.done" ]; then
        log "skip ${sid} (recon-all not done)"
        return 0
    fi

    log "segment_subregions ${sid} starting"
    for structure in hippo-amygdala brainstem thalamus; do
        # Skip if already done
        case "${structure}" in
            hippo-amygdala) marker="${FS_ROOT}/${sid}/mri/lh.hippoSfLabels-T1.v22.mgz" ;;
            brainstem)      marker="${FS_ROOT}/${sid}/mri/brainstemSsLabels.v13.mgz" ;;
            thalamus)       marker="${FS_ROOT}/${sid}/mri/ThalamicNuclei.v13.T1.mgz" ;;
        esac
        # Marker filenames vary across FS versions; just call and let it skip if
        # outputs exist.

        log "  ${sid}: segment_subregions ${structure}"
        docker run --rm \
          --user "$(id -u):$(id -g)" \
          -v "${FS_ROOT}:/subjects:rw" \
          -v "${HOME}/license.txt:/usr/lib/freesurfer/license.txt:ro" \
          -e SUBJECTS_DIR=/subjects \
          -e FS_LICENSE=/usr/lib/freesurfer/license.txt \
          --entrypoint bash \
          "${IMG}" -c "source /usr/lib/freesurfer/SetUpFreeSurfer.sh && \
                      segment_subregions ${structure} --cross ${sid}" 2>&1 | tail -3 || \
            log "    ${structure} returned non-zero — see output above"
    done
    log "  ${sid} done"
}

# Parallelize across sessions (3 sessions × ~30-45 min each = ~30-45 min wall)
PARALLEL="${PARALLEL:-3}"
running=0
for ses in ses-wave1 ses-wave2 ses-wave3; do
    run_one_session "${SUBJECT}_${ses}" &
    running=$((running+1))
    if [ "${running}" -ge "${PARALLEL}" ]; then
        wait -n
        running=$((running-1))
    fi
done
wait

log "segment_subregions cross-sectional done. Longitudinal mode (--long-base ${SUBJECT}) is a separate run."
