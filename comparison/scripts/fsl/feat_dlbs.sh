#!/usr/bin/env bash
# FEAT first-level GLM for the three DLBS task fMRI paradigms.
#
# Tasks (all event-related except Words which is block):
#   - Scenes        TR=2s, 171 vols × 3 runs (incidental encoding, water-presence judgment)
#   - Words         TR=2s, ~232 vols × 1 run  (block: easy/hard semantic)
#   - VentralVisual TR=2s, ~209 vols × 2 runs (block: 7 categories)
#
# We don't run a full FEAT GUI .fsf here — instead we write a minimal .fsf
# template per task using `feat_model`-friendly EVs from the raw events.tsv,
# then call `feat` on it. tcsh is required by FEAT; install via apt if missing.
#
# This file is currently a SCAFFOLD: it generates per-task .fsf templates and
# event 3-column files. The actual FEAT invocation is parameterized by
# stim presentation file (FSL three-column format: onset, duration, weight)
# which we derive from each *_events.tsv.
#
# Usage:
#   feat_dlbs.sh                                 # all subjects, all tasks
#   feat_dlbs.sh sub-1003                         # one subject
#   feat_dlbs.sh --task Scenes sub-1003           # one subject, one task
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/common.sh"

if ! command -v tcsh >/dev/null 2>&1; then
    log "ERROR: tcsh is required by FEAT. Install:  sudo apt install tcsh"
    exit 2
fi

TASK="all"
if [ "${1:-}" = "--task" ]; then
    TASK="$2"; shift 2
fi
SUBJECTS=("$@")
[ ${#SUBJECTS[@]} -eq 0 ] && SUBJECTS=("${DLBS_SUBJECTS[@]}")

# events.tsv → 3-column EV files keyed by trial_type
make_evs() {
    local events="$1" out_dir="$2"
    mkdir -p "${out_dir}/evs"
    # trial_type column index can vary; here trial_type is column 3
    # rows look like: onset<tab>duration<tab>trial_type
    awk 'NR>1 {print $1, $2, "1.0"}' "${events}" > "${out_dir}/evs/all_trials.txt"
    # split per condition (if multiple trial_types present)
    awk 'NR>1 {print $1, $2, "1.0" >> "'"${out_dir}/evs/cond_"'"$3".txt"}' "${events}"
    log "  EVs in ${out_dir}/evs:"
    ls "${out_dir}/evs/" | sed 's/^/    /'
}

# Minimal FEAT .fsf template (per scan); we only fill in the bits that vary.
write_fsf() {
    local fsf="$1" bold="$2" out_dir="$3" tr="$4" nvols="$5" ev_file="$6"
    cat > "${fsf}" <<EOF
# Auto-generated minimal FEAT .fsf for DLBS task fMRI (single EV, no contrasts beyond mean activation).
# This is a scaffold — extend per-task with the actual EV/contrast set you need.
set fmri(version) 6.00
set fmri(level) 1
set fmri(analysis) 7        ;# preprocessing + stats + post-stats
set fmri(relative_yn) 0
set fmri(help_yn) 1
set fmri(featwatcher_yn) 0
set fmri(sscleanup_yn) 0
set fmri(outputdir) "${out_dir}"
set fmri(tr) ${tr}
set fmri(npts) ${nvols}
set fmri(ndelete) 0
set fmri(tagfirst) 1
set fmri(multiple) 1
set fmri(inputtype) 2
set fmri(filtering_yn) 1
set fmri(brain_thresh) 10
set fmri(critical_z) 5.3
set fmri(noise) 0.66
set fmri(noisear) 0.34
set fmri(mc) 1
set fmri(sh_yn) 0
set fmri(regunwarp_yn) 0
set fmri(st) 0              ;# slice-timing off (DLBS slice timing not provided)
set fmri(bet_yn) 1
set fmri(smooth) 5
set fmri(norm_yn) 0
set fmri(perfsub_yn) 0
set fmri(temphp_yn) 1
set fmri(templp_yn) 0
set fmri(melodic_yn) 0
set fmri(stats_yn) 1
set fmri(prewhiten_yn) 1
set fmri(motionevs) 1
set fmri(robust_yn) 0
set fmri(mixed_yn) 2
set fmri(evs_orig) 1
set fmri(evs_real) 2
set fmri(evs_vox) 0
set fmri(ncon_orig) 1
set fmri(ncon_real) 1
set fmri(nftests_orig) 0
set fmri(nftests_real) 0
set fmri(constcol) 0
set fmri(con_mode_old) orig
set fmri(con_mode) orig
set feat_files(1) "${bold}"
set fmri(evtitle1) "task"
set fmri(shape1) 3            ;# 3-column custom file
set fmri(convolve1) 3         ;# double-gamma HRF
set fmri(convolve_phase1) 0
set fmri(tempfilt_yn1) 1
set fmri(deriv_yn1) 1
set fmri(custom1) "${ev_file}"
set fmri(con_real1.1) 1
set fmri(con_real1.2) 0
set fmri(conpic_real.1) 1
set fmri(conname_real.1) "task>baseline"
set fmri(conname_orig.1) "task>baseline"
set fmri(con_orig1.1) 1
set fmri(reginitial_highres_yn) 0
set fmri(reghighres_yn) 0
set fmri(regstandard_yn) 0
EOF
}

run_one_task_run() {
    local sub="$1" ses="$2" task="$3" run="$4" bold="$5" events="$6"
    local out_dir tr nvols
    out_dir="${OUT_ROOT}/feat/${sub}_${ses}_${task}_${run}.feat"
    if [ -d "${out_dir}" ] && [ -s "${out_dir}/stats/zstat1.nii.gz" ]; then
        log "skip ${sub} ${ses} ${task} ${run} (FEAT zstat1 exists)"
        return 0
    fi
    rm -rf "${out_dir}"  # FEAT refuses to clobber, so wipe partial dirs

    local pre="${OUT_ROOT}/feat/_pre/${sub}_${ses}_${task}_${run}"
    mkdir -p "${pre}"
    make_evs "${events}" "${pre}"

    tr=$("${FSLDIR}/bin/fslval" "${bold}" pixdim4 | tr -d ' ')
    nvols=$("${FSLDIR}/bin/fslval" "${bold}" dim4 | tr -d ' ')

    local fsf="${pre}/design.fsf"
    write_fsf "${fsf}" "${bold}" "${out_dir}" "${tr}" "${nvols}" "${pre}/evs/all_trials.txt"

    log "feat ${sub} ${ses} ${task} ${run} (TR=${tr}s, n=${nvols})"
    "${FSLDIR}/bin/feat" "${fsf}" 2>&1 | tail -3
}

run_one_subject() {
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
                # DLBS-wide events.tsv (per-subject inaccurate per README)
                events="${RAW_ROOT}/task-Words_run-1_events.tsv"
            fi
            if [ ! -f "${events}" ]; then
                log "  no events for ${stem}, skip"
                continue
            fi
            run_one_task_run "${sub}" "${ses}" "${task}" "${run}" "${bold}" "${events}"
        done < <(list_runs "${sub}" "${ses}" func "${globpat}")
    done
}

TASKS=(Scenes Words VentralVisual)
[ "${TASK}" != "all" ] && TASKS=("${TASK}")

for sub in "${SUBJECTS[@]}"; do
    for t in "${TASKS[@]}"; do
        run_one_subject "${sub}" "${t}"
    done
done

log "FEAT done. Outputs under ${OUT_ROOT}/feat/"
