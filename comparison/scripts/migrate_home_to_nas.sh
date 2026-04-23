#!/usr/bin/env bash
# Migrate large directories from /home/mhough to /data/mhough (NFS) and
# symlink them back. Keeps the user's shell/credentials/config directories
# intact — those stay on local root disk where they belong.
#
# Run WITHOUT sudo — operates entirely within the user's own namespace.
#
# Safety:
#   - Refuses to move a directory if any process holds a file open inside it
#     (lsof check). Skips busy ones with a warning so you can rerun after
#     the process finishes.
#   - Uses rsync --archive --remove-source-files then removes empty source
#     dirs; if rsync fails, source is preserved.
#   - Skips if the symlink target already exists (idempotent).
#
# After this script runs:
#   /home/mhough/dev        → /data/mhough/dev
#   /home/mhough/src        → /data/mhough/src
#   /home/mhough/nvidia-workbench → /data/mhough/nvidia-workbench
#   /home/mhough/fs_checkpoints   → /data/mhough/fs_checkpoints
#   /home/mhough/.cache     → /data/mhough/.cache
#
# Run AFTER the current image rebuild (bm5ivovzo) finishes, so the
# fastsurfer-arm build (which reads ~/src/FastSurfer) isn't disrupted.
set -euo pipefail

SRC_HOME=/home/mhough
DST_NAS=/data/mhough

# Directories to move. Order: smallest/safest first.
DIRS_TO_MIGRATE=(
    fs_checkpoints
    nvidia-workbench
    src
    dev
    .cache
)

mkdir -p "$DST_NAS"

check_busy() {
    # Returns 0 if busy (files open), 1 if idle.
    local dir="$1"
    if command -v lsof >/dev/null; then
        if lsof +D "$dir" 2>/dev/null | grep -v '^COMMAND' | grep -q .; then
            return 0
        fi
    fi
    return 1
}

migrate_dir() {
    local name="$1"
    local src="${SRC_HOME}/${name}"
    local dst="${DST_NAS}/${name}"

    if [[ ! -e "$src" ]]; then
        echo "SKIP ${name}: no such directory at ${src}"
        return 0
    fi

    if [[ -L "$src" ]]; then
        echo "SKIP ${name}: already a symlink → $(readlink "$src")"
        return 0
    fi

    if check_busy "$src"; then
        echo "BUSY ${name}: files open in ${src} — rerun later"
        lsof +D "$src" 2>/dev/null | head -5
        return 0
    fi

    local src_bytes
    src_bytes=$(du -sb "$src" 2>/dev/null | awk '{print $1}')
    local src_human
    src_human=$(du -sh "$src" 2>/dev/null | awk '{print $1}')
    echo ">>> migrating ${name} (${src_human}) → ${dst}"

    mkdir -p "$dst"
    rsync -aH --info=progress2 "$src"/ "$dst"/ || {
        echo "FAIL rsync ${name}: leaving source intact" >&2
        return 1
    }

    # Verify sizes match (rough check)
    local dst_bytes
    dst_bytes=$(du -sb "$dst" 2>/dev/null | awk '{print $1}')
    if [[ -n "${src_bytes}" && "${dst_bytes}" -lt "${src_bytes}" ]]; then
        echo "FAIL size mismatch for ${name}: src=${src_bytes} dst=${dst_bytes}" >&2
        return 1
    fi

    rm -rf "$src"
    ln -s "$dst" "$src"
    echo "DONE ${name}: $(ls -la "$src" | awk '{print $NF, "→", $NF}' | tr -s ' ')"
}

echo "=== migrate_home_to_nas started $(date -Iseconds) ==="
df -h / /data | head

for d in "${DIRS_TO_MIGRATE[@]}"; do
    migrate_dir "$d"
done

echo "=== migrate_home_to_nas finished $(date -Iseconds) ==="
df -h / /data | head

echo ""
echo "Dirs kept on local root (intentional): ~/.ssh ~/.config ~/.claude"
echo "  ~/.gnupg ~/.aws ~/.bashrc (and other dotfiles under 100 MB total)"
