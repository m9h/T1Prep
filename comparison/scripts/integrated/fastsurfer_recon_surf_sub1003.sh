#!/usr/bin/env bash
# FastSurfer recon_surf — adds full FreeSurfer-compatible surface output
# (white/pial, parcellation projection, label, stats) on top of existing
# --seg_only outputs. Required for downstream PETSurfer (gtmseg) + TRACULA
# + surface-based fMRI stats.
#
# Container: ghcr.io/m9h/fastsurfer-full:7.4.1-6b6b985.1 — pairs FastSurfer
# with FS 7.4.1 binaries so the recon_surf.sh shell pipeline works.
#
# Per-scan runtime: ~1.5 hr GPU (vs 8-12 hr for upstream FreeSurfer recon-all).
#
# Output appended to existing /data/datasets/smri-fm-cmp/fastsurfer/<sid>/:
#   surf/{lh,rh}.{white,pial,sphere,thickness,curv,...}
#   label/{lh,rh}.aparc.DKTatlas40.annot
#   stats/{lh,rh}.aparc.DKTatlas.mapped.stats
#
# Usage:
#   fastsurfer_recon_surf_sub1003.sh                # all 3 sessions of sub-1003
set -euo pipefail
SUBJECT="${SUBJECT:-sub-1003}"
DATASET="${DATASET:-ds004856}"
RAW_ROOT="/data/raw/openneuro/${DATASET}"
FS_ROOT="/data/datasets/smri-fm-cmp/fastsurfer/${DATASET}"
IMG="${IMG:-fastsurfer-full-fspython:1.0}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

# Default: run all sessions concurrently (3 for sub-1003 — fits in 30 GB RAM,
# 12 CPU threads via --parallel; well within 120 GB / 20-core budget).
# Override with PARALLEL=1 (or PARALLEL=N) to limit.
PARALLEL="${PARALLEL:-3}"

run_one() {
    local ses="$1"
    local sid="${SUBJECT}_${ses}"
    local seg_dir="${FS_ROOT}/${sid}"
    if [ ! -f "${seg_dir}/mri/aparc.DKTatlas+aseg.deep.mgz" ]; then
        log "  no seg for ${sid} — skip (run fastsurfer seg_only first)"
        return 0
    fi
    if [ -f "${seg_dir}/surf/lh.pial" ] && [ -f "${seg_dir}/surf/rh.pial" ]; then
        log "skip ${sid} (surfaces already present)"
        return 0
    fi

    local t1
    t1=$(find "${RAW_ROOT}/${SUBJECT}/${ses}/anat" -name "*_acq-MPRAGE_run-1_T1w.nii.gz" | head -1)
    [ -z "${t1}" ] && { log "no T1 for ${sid}"; return 0; }
    local anat_dir t1_base
    anat_dir="$(dirname "${t1}")"
    t1_base="$(basename "${t1}")"
    local logfile="/tmp/fastsurfer_recon_surf_${sid}.log"

    log "fastsurfer recon_surf ${sid} (log → ${logfile})"
    docker run --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 --rm \
      --user "$(id -u):$(id -g)" \
      -v "${anat_dir}:/data:ro" \
      -v "${FS_ROOT}:/output" \
      -v "${HOME}/license.txt:/opt/FastSurfer/license.txt:ro" \
      -v "${HOME}/fs_checkpoints:/opt/FastSurfer/checkpoints:ro" \
      "${IMG}" \
      ./run_fastsurfer.sh \
        --t1 "/data/${t1_base}" --sid "${sid}" --sd /output \
        --surf_only --parallel --edits \
        --fs_license /opt/FastSurfer/license.txt > "${logfile}" 2>&1
    local rc=$?
    if [ $rc -eq 0 ]; then
        log "  ${sid} surfaces done"
    else
        log "  ${sid} FAILED (rc=$rc) — see ${logfile}"
    fi
}

# Fan out per-session with PARALLEL-bounded concurrency
running=0
pids=()
for ses in $(ls "${RAW_ROOT}/${SUBJECT}" 2>/dev/null | grep '^ses-'); do
    run_one "${ses}" &
    pids+=("$!")
    running=$((running+1))
    if [ "${running}" -ge "${PARALLEL}" ]; then
        wait -n
        running=$((running-1))
    fi
done
wait
log "FastSurfer recon_surf finished. Outputs under ${FS_ROOT}/<sid>/{surf,label,stats}/"
