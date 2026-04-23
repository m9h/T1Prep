#!/usr/bin/env bash
# Build the T1Prep comparison image and record its digest.
# Pinned release: v0.3.0. Native arm64 works on DGX Spark.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${HERE}/IMAGE_DIGESTS.md"
T1PREP_REPO="${T1PREP_REPO:-$(cd "${HERE}/../.." && pwd)}"
T1PREP_VERSION="${T1PREP_VERSION:-v0.3.0}"
BASE_TAG="python:3.12-slim"
IMAGE_TAG="smri-fm-cmp-t1prep:${T1PREP_VERSION}"
PLATFORM="${PLATFORM:-linux/arm64}"

echo "[build_t1prep] platform=${PLATFORM}"
echo "[build_t1prep] T1Prep release=${T1PREP_VERSION}"

# Resolve base-image digest before build so we fail fast on drift.
BASE_DIGEST="$(docker buildx imagetools inspect "${BASE_TAG}" \
    --format '{{range .Manifest.Manifests}}{{if eq .Platform.Architecture "arm64"}}{{.Digest}}{{end}}{{end}}' 2>/dev/null \
    || docker image inspect "${BASE_TAG}" --format='{{index .RepoDigests 0}}' 2>/dev/null \
    || true)"
echo "[build_t1prep] base digest=${BASE_DIGEST:-<unresolved>}"

cd "${T1PREP_REPO}"
docker build \
    --platform="${PLATFORM}" \
    --build-arg "T1PREP_SOURCE=release" \
    --build-arg "T1PREP_VERSION=${T1PREP_VERSION}" \
    --label "smri-fm-cmp.source.commit=$(git rev-parse HEAD)" \
    --label "smri-fm-cmp.source.ref=${T1PREP_VERSION}" \
    -t "${IMAGE_TAG}" \
    -f Dockerfile \
    .

BUILT_DIGEST="$(docker image inspect "${IMAGE_TAG}" --format='{{.Id}}')"
SOURCE_SHA="$(cd "${T1PREP_REPO}" && git rev-parse HEAD)"
BUILT_AT="$(date -Iseconds)"

{
    printf "| %s | %s | %s | %s | %s |\n" \
        "${IMAGE_TAG}" "${BUILT_DIGEST}" "${PLATFORM}" "${BUILT_AT}" "${SOURCE_SHA}"
} >> "${HERE}/.built_rows.tmp"

echo "[build_t1prep] built ${IMAGE_TAG} ${BUILT_DIGEST}"
echo "[build_t1prep] appended row to ${HERE}/.built_rows.tmp"
echo "[build_t1prep] run update_manifest.sh to merge into IMAGE_DIGESTS.md"
