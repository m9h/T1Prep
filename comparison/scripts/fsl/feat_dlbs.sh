#!/usr/bin/env bash
# FEAT first-level GLM for DLBS task fMRI (Scenes / Words / VentralVisual).
#
# Strategy: instead of hand-rolling a minimal `.fsf` (FEAT silently requires
# ~70 set fmri(...) vars and breaks at line 390 if any expected one is
# missing), we use the canonical 1st-level template that ships with FSL's
# fslpy testdata, then sed-substitute only the per-scan vars:
#   feat_files(1), outputdir, tr, npts, custom1 (EV file), and
#   evs counts / contrasts as needed. Everything else inherits the canonical.
#
# DLBS task fMRI:
#   - Scenes        TR=2s, 171 vols × 3 runs (event-related)
#   - Words         TR=2s, ~232 vols × 1 run  (block: easy/hard semantic)
#   - VentralVisual TR=2s, ~209 vols × 2 runs (block: 7 categories)
#
# Output:
#   ${OUT_ROOT}/feat/<sub>_<ses>_<task>_<run>.feat/
#       stats/zstat1.nii.gz, design.fsf, report.html, ...
#
# Usage:
#   feat_dlbs.sh                                 # all subjects, all tasks (use with care!)
#   feat_dlbs.sh sub-1003                        # one subject, all tasks
#   feat_dlbs.sh --task Scenes sub-1003          # one subject, one task
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/common.sh"

if ! command -v tcsh >/dev/null 2>&1; then
    log "ERROR: tcsh is required by FEAT. Install:  sudo apt install tcsh"
    exit 2
fi

# Canonical 1st-level .fsf shipped with fslpy testdata
CANONICAL_FSF="${CANONICAL_FSF:-/home/mhough/fsl/envs/truenet/lib/python3.13/site-packages/fsl/tests/testdata/test_feat/1stlevel_1.feat/design.fsf}"
if [ ! -f "${CANONICAL_FSF}" ]; then
    log "ERROR: canonical FSF not found at ${CANONICAL_FSF}"
    exit 2
fi

TASK="all"
if [ "${1:-}" = "--task" ]; then
    TASK="$2"; shift 2
fi
SUBJECTS=("$@")
[ ${#SUBJECTS[@]} -eq 0 ] && SUBJECTS=("${DLBS_SUBJECTS[@]}")

# Convert events.tsv → 3-column EV file (onset, duration, weight=1)
make_ev() {
    local events="$1" out="$2"
    awk 'NR>1 {print $1, $2, "1.0"}' "${events}" > "${out}"
}

# Build per-scan .fsf from canonical with sed-substitution
write_fsf() {
    local fsf="$1" bold="$2" out_dir="$3" tr="$4" nvols="$5" ev_file="$6"
    # totalVoxels = dim1*dim2*dim3*dim4
    local d1 d2 d3 d4
    d1=$("${FSLDIR}/bin/fslval" "${bold}" dim1)
    d2=$("${FSLDIR}/bin/fslval" "${bold}" dim2)
    d3=$("${FSLDIR}/bin/fslval" "${bold}" dim3)
    d4=$("${FSLDIR}/bin/fslval" "${bold}" dim4)
    local total_vox=$(( d1 * d2 * d3 * d4 ))

    # Start from canonical, substitute the variable bits
    # We strip canonical's feat_files(1..3), evs, contrasts blocks at the end and append fresh ones
    sed -E \
      -e "s|^set fmri\(outputdir\) .*|set fmri(outputdir) \"${out_dir}\"|" \
      -e "s|^set fmri\(tr\) .*|set fmri(tr) ${tr}|" \
      -e "s|^set fmri\(npts\) .*|set fmri(npts) ${nvols}|" \
      -e "s|^set fmri\(multiple\) .*|set fmri(multiple) 1|" \
      -e "s|^set fmri\(reginitial_highres_yn\) .*|set fmri(reginitial_highres_yn) 0|" \
      -e "s|^set fmri\(reghighres_yn\) .*|set fmri(reghighres_yn) 0|" \
      -e "s|^set fmri\(regstandard_yn\) .*|set fmri(regstandard_yn) 0|" \
      -e "s|^set fmri\(totalVoxels\) .*|set fmri(totalVoxels) ${total_vox}|" \
      -e '/^set feat_files\(/d' \
      -e '/^set fmri\(custom[0-9]/d' \
      "${CANONICAL_FSF}" > "${fsf}"

    # Append a single feat_files + custom EV + contrast block
    cat >> "${fsf}" <<EOF

# --- DLBS per-scan overrides
set feat_files(1) "${bold}"
set fmri(custom1) "${ev_file}"
EOF
}

run_one() {
    local sub="$1" ses="$2" task="$3" run="$4" bold="$5" events="$6"
    local out_dir
    out_dir="${OUT_ROOT}/feat/${sub}_${ses}_${task}_${run}.feat"
    if [ -d "${out_dir}" ] && [ -s "${out_dir}/stats/zstat1.nii.gz" ]; then
        log "skip ${sub} ${ses} ${task} ${run} (FEAT zstat1 exists)"
        return 0
    fi
    rm -rf "${out_dir}"  # FEAT refuses to clobber

    local pre="${OUT_ROOT}/feat/_pre/${sub}_${ses}_${task}_${run}"
    mkdir -p "${pre}"
    make_ev "${events}" "${pre}/ev_all.txt"

    local tr nvols
    tr=$("${FSLDIR}/bin/fslval" "${bold}" pixdim4 | tr -d ' ')
    nvols=$("${FSLDIR}/bin/fslval" "${bold}" dim4 | tr -d ' ')

    local fsf="${pre}/design.fsf"
    write_fsf "${fsf}" "${bold}" "${out_dir}" "${tr}" "${nvols}" "${pre}/ev_all.txt"

    log "feat ${sub} ${ses} ${task} ${run} (TR=${tr}s, n=${nvols})"
    "${FSLDIR}/bin/feat" "${fsf}" 2>&1 | tail -3 || \
        log "  WARN feat returned non-zero on ${sub} ${ses} ${task} ${run}"
}

run_one_subject_task() {
    local sub="$1" task="$2"
    for ses in $(list_sessions "${sub}"); do
        local globpat="*_task-${task}_*_bold.nii.gz"
        while IFS= read -r bold; do
            [ -z "${bold}" ] && continue
            local stem run events
            stem="$(basename "${bold}" .nii.gz)"
            run=$(echo "${stem}" | grep -oE 'run-[0-9]+' || echo run-1)
            events="${bold%_bold.nii.gz}_events.tsv"
            if [ "${task}" = "Words" ]; then
                # DLBS Words events live at the dataset root (study-wide
                # stimulus onset file, not per-subject). README claims the
                # filename ends "_run-1_events.tsv" but the actual file
                # shipped with ds004856 is task-Words_events.tsv. Try both.
                if [ -f "${RAW_ROOT}/task-Words_events.tsv" ]; then
                    events="${RAW_ROOT}/task-Words_events.tsv"
                else
                    events="${RAW_ROOT}/task-Words_run-1_events.tsv"
                fi
            fi
            if [ ! -f "${events}" ]; then
                log "  no events for ${stem}, skip"
                continue
            fi
            run_one "${sub}" "${ses}" "${task}" "${run}" "${bold}" "${events}"
        done < <(list_runs "${sub}" "${ses}" func "${globpat}")
    done
}

TASKS=(Scenes Words VentralVisual)
[ "${TASK}" != "all" ] && TASKS=("${TASK}")

for sub in "${SUBJECTS[@]}"; do
    for t in "${TASKS[@]}"; do
        run_one_subject_task "${sub}" "${t}"
    done
done

log "FEAT done. Outputs under ${OUT_ROOT}/feat/"
