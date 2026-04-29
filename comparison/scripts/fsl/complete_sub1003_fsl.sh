#!/usr/bin/env bash
# Complete the FSL processing for DLBS sub-1003.
#
# Existing state (audit 2026-04-28):
#   eddy        W1 + W3 done, W2 missing
#   bedpostx    W1 done (bedpostx_gpu output present), W2 + W3 missing
#   dtifit      none — need all 3 waves
#   xtract      none — need all 3 waves (depends on bedpostx)
#   TBSS        none — per-subject FA in standard space
#   oxford_asl  none — need W1 + W3 (ASL data at perf/, W2 has none)
#   FIX         none — denoise rest MELODIC.ica outputs
#   MELODIC     done (rest × 3 waves)
#   FEAT        done (Scenes/Words/VV/Hyp × 3 waves)
#
# Fills the gaps idempotently. Host FSL 6.0.7.19 at /home/mhough/fsl.
# bedpostx_gpu uses Blackwell; CPU stages run at low priority so they
# coexist with whatever else is running on Spark.
#
# Usage:
#   bash complete_sub1003_fsl.sh                          # all missing stages
#   STAGES="dtifit xtract" bash complete_sub1003_fsl.sh   # only specific stages

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/common.sh" 2>/dev/null || true

export FSLDIR="${FSLDIR:-/home/mhough/fsl}"
export PATH="${FSLDIR}/bin:${FSLDIR}/share/fsl/bin:${PATH}"

SUB=sub-1003
RAW_ROOT="/data/raw/openneuro/ds004856"
OUT_ROOT="/data/datasets/smri-fm-cmp/fsl/ds004856"
INT_ROOT="/data/datasets/smri-fm-cmp/integrated/ds004856/${SUB}"
LOG_DIR="/data/datasets/smri-fm-cmp/_logs/sub1003_fsl"
mkdir -p "${LOG_DIR}" "${OUT_ROOT}/dwi" "${OUT_ROOT}/asl" "${OUT_ROOT}/tbss" "${OUT_ROOT}/fix"

NICE_PREFIX="nice -n 19 ionice -c3"
STAGES="${STAGES:-eddy dtifit bedpostx xtract tbss oxford_asl fix}"

log() { printf '[%s] %s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$*" | tee -a "${LOG_DIR}/runner.log" >&2; }

stage_active() { [[ " ${STAGES} " == *" $1 "* ]]; }

# -- diffusion utilities ----------------------------------------------------

dwi_path()    { echo "${RAW_ROOT}/${SUB}/$1/dwi/${SUB}_$1_acq-DTI_run-1_dwi.nii.gz"; }
bvec_path()   { echo "${RAW_ROOT}/${SUB}/$1/dwi/${SUB}_$1_acq-DTI_run-1_dwi.bvec"; }
bval_path()   { echo "${RAW_ROOT}/${SUB}/$1/dwi/${SUB}_$1_acq-DTI_run-1_dwi.bval"; }
eddy_stem()   { echo "${OUT_ROOT}/dwi/${SUB}_$1/${SUB}_$1_acq-DTI_run-1_dwi_eddy"; }
dtifit_stem() { echo "${OUT_ROOT}/dwi/${SUB}_$1/dtifit"; }
bp_indir()    { echo "${OUT_ROOT}/dwi/${SUB}_$1.bedpostx_in"; }
bp_outdir()   { echo "${OUT_ROOT}/dwi/${SUB}_$1.bedpostx_in.bedpostX"; }

# -- stage runners ----------------------------------------------------------

run_eddy() {
    local ses="$1"
    local in="$(dwi_path "${ses}")"
    [ ! -f "${in}" ] && { log "  ${ses}: no DWI raw, skip eddy"; return 0; }
    local out_dir="${OUT_ROOT}/dwi/${SUB}_${ses}"
    local out="$(eddy_stem "${ses}")"
    mkdir -p "${out_dir}"
    if [ -s "${out}.nii.gz" ]; then
        log "  ${ses}: eddy_correct already done"
        return 0
    fi
    log "  ${ses}: eddy_correct (CPU, ~10-20 min)"
    ${NICE_PREFIX} "${FSLDIR}/bin/eddy_correct" "${in}" "${out}" 0 \
        >> "${LOG_DIR}/eddy_${ses}.log" 2>&1 \
        && log "    ${ses}: eddy done" \
        || log "    ${ses}: eddy FAILED — see ${LOG_DIR}/eddy_${ses}.log"
}

run_dtifit() {
    local ses="$1"
    local eddy="$(eddy_stem "${ses}").nii.gz"
    [ ! -f "${eddy}" ] && { log "  ${ses}: no eddy output, skip dtifit"; return 0; }
    local stem="$(dtifit_stem "${ses}")"
    if [ -s "${stem}_FA.nii.gz" ]; then
        log "  ${ses}: dtifit already done"
        return 0
    fi
    mkdir -p "$(dirname "${stem}")"
    # Need a brain mask for the eddy-corrected DWI
    local mask="$(dirname "${stem}")/nodif_brain_mask.nii.gz"
    if [ ! -s "${mask}" ]; then
        log "  ${ses}: dtifit prep — extract nodif and BET"
        local nodif="$(dirname "${stem}")/nodif.nii.gz"
        ${NICE_PREFIX} "${FSLDIR}/bin/fslroi" "${eddy}" "${nodif}" 0 1 \
            >> "${LOG_DIR}/dtifit_${ses}.log" 2>&1 || true
        ${NICE_PREFIX} "${FSLDIR}/bin/bet" "${nodif}" "$(dirname "${stem}")/nodif_brain" \
            -m -f 0.2 -R \
            >> "${LOG_DIR}/dtifit_${ses}.log" 2>&1 || true
    fi
    log "  ${ses}: dtifit (CPU, ~5 min)"
    ${NICE_PREFIX} "${FSLDIR}/bin/dtifit" \
        --data="${eddy}" \
        --out="${stem}" \
        --mask="${mask}" \
        --bvecs="$(bvec_path "${ses}")" \
        --bvals="$(bval_path "${ses}")" \
        >> "${LOG_DIR}/dtifit_${ses}.log" 2>&1 \
        && log "    ${ses}: dtifit done" \
        || log "    ${ses}: dtifit FAILED — see ${LOG_DIR}/dtifit_${ses}.log"
}

run_bedpostx() {
    local ses="$1"
    local eddy="$(eddy_stem "${ses}").nii.gz"
    local mask_dir="$(dtifit_stem "${ses}")"
    local mask="$(dirname "${mask_dir}")/nodif_brain_mask.nii.gz"
    [ ! -f "${eddy}" ] && { log "  ${ses}: no eddy, skip bedpostx"; return 0; }
    [ ! -f "${mask}" ] && { log "  ${ses}: no brain mask, skip bedpostx"; return 0; }
    local indir="$(bp_indir "${ses}")"
    local outdir="$(bp_outdir "${ses}")"
    if [ -s "${outdir}/dyads1.nii.gz" ] || [ -s "${outdir}/mean_S0samples.nii.gz" ]; then
        log "  ${ses}: bedpostx already done"
        return 0
    fi
    log "  ${ses}: bedpostx prep (input dir layout)"
    mkdir -p "${indir}"
    cp -f "${eddy}" "${indir}/data.nii.gz"
    cp -f "$(bvec_path "${ses}")" "${indir}/bvecs"
    cp -f "$(bval_path "${ses}")" "${indir}/bvals"
    cp -f "${mask}" "${indir}/nodif_brain_mask.nii.gz"
    log "  ${ses}: bedpostx_gpu (~30-60 min on Blackwell)"
    ${NICE_PREFIX} "${FSLDIR}/bin/bedpostx_gpu" "${indir}" \
        >> "${LOG_DIR}/bedpostx_${ses}.log" 2>&1 \
        && log "    ${ses}: bedpostx done" \
        || log "    ${ses}: bedpostx FAILED — see ${LOG_DIR}/bedpostx_${ses}.log"
}

run_xtract() {
    local ses="$1"
    local bp_dir="$(bp_outdir "${ses}")"
    [ ! -s "${bp_dir}/dyads1.nii.gz" ] && [ ! -s "${bp_dir}/mean_S0samples.nii.gz" ] && {
        log "  ${ses}: bedpostx not done, skip xtract"
        return 0
    }
    local out_dir="${OUT_ROOT}/xtract/${SUB}_${ses}"
    if [ -d "${out_dir}/tracts" ] && [ -n "$(ls -A "${out_dir}/tracts" 2>/dev/null)" ]; then
        log "  ${ses}: xtract already done"
        return 0
    fi
    mkdir -p "${out_dir}"
    log "  ${ses}: xtract (~30 min on GPU)"
    ${NICE_PREFIX} "${FSLDIR}/bin/xtract" \
        -bpx "${bp_dir}" -out "${out_dir}" \
        -species HUMAN -gpu \
        >> "${LOG_DIR}/xtract_${ses}.log" 2>&1 \
        && log "    ${ses}: xtract done" \
        || log "    ${ses}: xtract FAILED — see ${LOG_DIR}/xtract_${ses}.log"
}

run_tbss() {
    local out_dir="${OUT_ROOT}/tbss/${SUB}"
    if [ -s "${out_dir}/stats/all_FA_skeletonised.nii.gz" ]; then
        log "  TBSS already done"
        return 0
    fi
    # TBSS expects a directory with FA images named consistently
    mkdir -p "${out_dir}"
    cd "${out_dir}"
    for ses in ses-wave1 ses-wave2 ses-wave3; do
        local fa="$(dtifit_stem "${ses}")_FA.nii.gz"
        if [ -s "${fa}" ]; then
            cp -f "${fa}" "${SUB}_${ses}_FA.nii.gz"
        fi
    done
    local n_fa
    n_fa=$(ls *_FA.nii.gz 2>/dev/null | wc -l)
    if [ "${n_fa}" -lt 1 ]; then
        log "  TBSS: no FA images, skip"
        return 0
    fi
    log "  TBSS (4 stages: preproc, reg, postreg, prestats; ~20-40 min)"
    {
        ${NICE_PREFIX} "${FSLDIR}/bin/tbss_1_preproc" *_FA.nii.gz
        ${NICE_PREFIX} "${FSLDIR}/bin/tbss_2_reg" -T
        ${NICE_PREFIX} "${FSLDIR}/bin/tbss_3_postreg" -S
        ${NICE_PREFIX} "${FSLDIR}/bin/tbss_4_prestats" 0.2
    } >> "${LOG_DIR}/tbss.log" 2>&1 \
        && log "    TBSS done" \
        || log "    TBSS FAILED — see ${LOG_DIR}/tbss.log"
    cd - >/dev/null
}

run_oxford_asl() {
    local ses="$1"
    local asl="${RAW_ROOT}/${SUB}/${ses}/perf/${SUB}_${ses}_acq-ASL_run-1_asl.nii.gz"
    [ ! -f "${asl}" ] && { log "  ${ses}: no ASL data, skip oxford_asl"; return 0; }
    local out_dir="${OUT_ROOT}/asl/${SUB}_${ses}_run-1"
    if [ -s "${out_dir}/native_space/perfusion_calib.nii.gz" ]; then
        log "  ${ses}: oxford_asl already done"
        return 0
    fi
    mkdir -p "${out_dir}"
    log "  ${ses}: oxford_asl (~20-30 min, fabber-driven Bayesian Buxton)"
    # PCASL with single-PLD per the JSON; use simple defaults
    ${NICE_PREFIX} "${FSLDIR}/bin/oxford_asl" \
        -i "${asl}" \
        -o "${out_dir}" \
        --casl --tis=3.4 --bolus=1.65 \
        --iaf=ct --ibf=tis --rpts=18 \
        --fixbolus \
        --bat=1.3 \
        --tr=4.15 \
        >> "${LOG_DIR}/oxford_asl_${ses}.log" 2>&1 \
        && log "    ${ses}: oxford_asl done" \
        || log "    ${ses}: oxford_asl FAILED — see ${LOG_DIR}/oxford_asl_${ses}.log"
}

run_fix() {
    # FIX requires a trained classifier; FSL ships a few standard ones.
    # Use the bundled "Standard" training data if present.
    local fix_train_data
    for cand in \
        "${FSLDIR}/share/fsl/data/fix/training_files/Standard.RData" \
        "${FSLDIR}/data/fix/training_files/Standard.RData" \
        "${FSLDIR}/etc/fix/training_files/Standard.RData"; do
        if [ -f "${cand}" ]; then fix_train_data="${cand}"; break; fi
    done
    if [ -z "${fix_train_data:-}" ]; then
        log "  FIX: no Standard.RData training file found; skip"
        return 0
    fi

    for ses in ses-wave1 ses-wave2 ses-wave3; do
        local melodic_dir
        for run in 1 2 3 4 5; do
            melodic_dir="${OUT_ROOT}/melodic/${SUB}_${ses}_run-${run}.ica"
            [ -d "${melodic_dir}" ] || continue
            local fix_out="${OUT_ROOT}/fix/${SUB}_${ses}_run-${run}"
            local marker="${fix_out}/fix4melview_Standard.txt"
            if [ -s "${marker}" ]; then
                log "  ${ses} run-${run}: FIX already done"
                continue
            fi
            mkdir -p "${fix_out}"
            log "  ${ses} run-${run}: FIX classification (~5 min)"
            ${NICE_PREFIX} "${FSLDIR}/bin/fix" \
                -c "${melodic_dir}" "${fix_train_data}" 20 \
                >> "${LOG_DIR}/fix_${ses}_run-${run}.log" 2>&1 \
                && cp -r "${melodic_dir}/fix4melview_Standard_thr20.txt" "${marker}" 2>/dev/null \
                && log "    ${ses} run-${run}: FIX done" \
                || log "    ${ses} run-${run}: FIX FAILED — see ${LOG_DIR}/fix_${ses}_run-${run}.log"
        done
    done
}

# -- main -------------------------------------------------------------------

log "=== complete_sub1003_fsl: stages='${STAGES}' ==="

if stage_active eddy; then
    log "--- eddy ---"
    for ses in ses-wave1 ses-wave2 ses-wave3; do run_eddy "${ses}"; done
fi
if stage_active dtifit; then
    log "--- dtifit ---"
    for ses in ses-wave1 ses-wave2 ses-wave3; do run_dtifit "${ses}"; done
fi
if stage_active bedpostx; then
    log "--- bedpostx ---"
    for ses in ses-wave1 ses-wave2 ses-wave3; do run_bedpostx "${ses}"; done
fi
if stage_active xtract; then
    log "--- xtract ---"
    for ses in ses-wave1 ses-wave2 ses-wave3; do run_xtract "${ses}"; done
fi
if stage_active tbss; then
    log "--- TBSS ---"
    run_tbss
fi
if stage_active oxford_asl; then
    log "--- oxford_asl ---"
    for ses in ses-wave1 ses-wave2 ses-wave3; do run_oxford_asl "${ses}"; done
fi
if stage_active fix; then
    log "--- FIX ---"
    run_fix
fi

log "=== complete_sub1003_fsl done ==="
log "wired output tree: ${OUT_ROOT}/{dwi,asl,tbss,xtract,fix}/${SUB}*"
