#!/usr/bin/env bash
# Finish the docker data-root relocation after Ctrl-C'ing the rsync.
# - Wipes any partial /data/mhough/docker rsync had been populating.
# - Points docker at a fresh empty NAS directory via /etc/docker/daemon.json.
# - Starts docker and verifies the new root.
#
# After this succeeds, images + containers start empty. Anything we need
# (gpu-workbench, t1prep-arm, fastsurfer-arm) is rebuilt from code into
# the NAS-backed store going forward.
#
# Run with sudo:
#   sudo /home/mhough/dev/T1Prep/comparison/scripts/finish_docker_relocate.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  exec sudo -- "$0" "$@"
fi

NEW_ROOT=/data/mhough/docker

echo "=== sanity: rsync must not still be running ==="
if pgrep -f "rsync .*/var/lib/docker" >/dev/null; then
  echo "ERROR: rsync is still running. Ctrl-C it first." >&2
  exit 1
fi

echo "=== sanity: docker should be stopped ==="
if systemctl is-active --quiet docker; then
  echo "ERROR: docker is currently running. Stop it first:" >&2
  echo "  sudo systemctl stop docker.socket docker" >&2
  exit 1
fi

echo "=== wiping partial ${NEW_ROOT} ==="
rm -rf "${NEW_ROOT}"
mkdir -p "${NEW_ROOT}"

echo "=== writing /etc/docker/daemon.json ==="
mkdir -p /etc/docker
if [[ -f /etc/docker/daemon.json ]]; then
  cp /etc/docker/daemon.json "/etc/docker/daemon.json.bak.$(date +%s)"
  python3 - <<PY
import json, pathlib
p = pathlib.Path('/etc/docker/daemon.json')
d = json.loads(p.read_text() or '{}')
d['data-root'] = '${NEW_ROOT}'
p.write_text(json.dumps(d, indent=2))
PY
else
  cat > /etc/docker/daemon.json <<EOF
{
  "data-root": "${NEW_ROOT}"
}
EOF
fi

echo "=== starting docker ==="
systemctl start docker

sleep 2

echo "=== verify ==="
docker info 2>/dev/null | grep -i 'docker root dir'
df -h / /data | head -5

echo ""
echo "Docker is up on ${NEW_ROOT} with an empty store."
echo "Next steps (on the claude side): rebuild t1prep-arm + fastsurfer-arm"
echo "into the NAS-backed store, push to ghcr.io."
echo ""
echo "To reclaim the old tree on root (optional, recommend doing this only"
echo "after a few test docker runs succeed):"
echo "  sudo rm -rf /var/lib/docker"
