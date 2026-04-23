#!/usr/bin/env bash
# Relocate docker's data-root from /var/lib/docker (local root disk) to
# /data/mhough/docker (TrueNAS NFS). One-off sysadmin action — requires
# sudo and will restart the docker daemon. Preserves all images + volumes.
#
# Run this outside any Claude Code session so the sudo prompt works.
#
# Afterwards:
#   docker info | grep -i 'docker root dir'
# should report /data/mhough/docker, and `df -h /` will show ~150 GB
# returned to the local root disk.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  exec sudo -- "$0" "$@"
fi

SRC=/var/lib/docker
DST=/data/mhough/docker

if [[ ! -d "$SRC" ]]; then
  echo "no $SRC — nothing to move" >&2
  exit 1
fi

echo "=== pre-check ==="
df -h / /data | head -5
du -sh "$SRC" 2>/dev/null || true

echo "=== stopping docker ==="
systemctl stop docker.socket || true
systemctl stop docker

echo "=== rsync $SRC → $DST ==="
mkdir -p "$DST"
rsync -aHAX --info=progress2 "$SRC"/ "$DST"/

echo "=== updating /etc/docker/daemon.json ==="
mkdir -p /etc/docker
if [[ -f /etc/docker/daemon.json ]]; then
  cp /etc/docker/daemon.json /etc/docker/daemon.json.bak.$(date +%s)
  python3 - <<PY
import json, pathlib
p = pathlib.Path('/etc/docker/daemon.json')
d = json.loads(p.read_text())
d['data-root'] = '$DST'
p.write_text(json.dumps(d, indent=2))
PY
else
  cat > /etc/docker/daemon.json <<EOF
{"data-root": "$DST"}
EOF
fi

echo "=== restarting docker ==="
systemctl start docker

echo "=== verify ==="
docker info | grep -i 'docker root dir'
df -h / /data | head -5

echo ""
echo "If the new root dir is /data/mhough/docker and everything still runs,"
echo "you can reclaim the old tree with:"
echo "  sudo rm -rf /var/lib/docker"
echo "(do NOT do this until you confirm the new store works.)"
