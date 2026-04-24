#!/usr/bin/env bash
# HD_BET.paths hardcodes ~/hd-bet_params — relocate weights from
# /opt/hdbet_params (baked into the image) into whatever $HOME the
# container is launched with, via a symlink.
set -euo pipefail
: "${HOME:=/tmp}"
mkdir -p "$HOME"
if [ ! -e "$HOME/hd-bet_params" ]; then
    ln -s /opt/hdbet_params "$HOME/hd-bet_params" 2>/dev/null || true
fi
exec python3 /opt/brainiac_preproc/brainiac_preprocess.py "$@"
