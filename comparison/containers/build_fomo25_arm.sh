#!/usr/bin/env bash
# Build the FOMO25 arm Grace-Blackwell-optimized image on DGX Spark.
#
# Strategy: NGC pytorch:26.03-py3 (arm64 + sm_120 Blackwell) base, with
# asparagus + gardening_tools installed --no-deps (so the upstream
# torch<2.3 cap doesn't downgrade NGC's tuned wheel), and the
# AMAES_resenc_b checkpoint pre-fetched at build time. ~14 GB final.
set -euo pipefail

CTX="$(dirname "${BASH_SOURCE[0]}")"
TAG="${TAG:-fomo25-arm:latest}"
GHCR_TAG="${GHCR_TAG:-ghcr.io/m9h/fomo25-arm:latest}"

cd "${CTX}"

docker build \
    -f Dockerfile.fomo25-arm \
    -t "${TAG}" \
    -t "${GHCR_TAG}" \
    .

echo
echo "built: ${TAG} ${GHCR_TAG}"
docker images "${TAG}" | head -3
