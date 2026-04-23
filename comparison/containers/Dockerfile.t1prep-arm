# T1Prep container for NVIDIA Grace (ARM64) — matches the pattern used for
# fastsurfer-grace so both arms share a base image family. Built from the
# T1Prep release tarball, not a local checkout, so the container is
# reproducible from the release tag alone.

# Pinned digest (linux/arm64) for nvcr.io/nvidia/pytorch:26.03-py3
# Lookup: docker buildx imagetools inspect nvcr.io/nvidia/pytorch:26.03-py3
FROM nvcr.io/nvidia/pytorch:26.03-py3

LABEL maintainer="t1prep-grace-build"
LABEL description="T1Prep container optimized for NVIDIA Grace (ARM64)"
LABEL org.opencontainers.image.source="https://github.com/ChristianGaser/T1Prep"

ARG T1PREP_VERSION=v0.3.3

# --- system deps
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      wget unzip zip ca-certificates default-jre-headless \
 && rm -rf /var/lib/apt/lists/*

# --- fetch T1Prep release
WORKDIR /opt
RUN wget -q --progress=dot:giga \
      "https://github.com/ChristianGaser/T1Prep/archive/refs/tags/${T1PREP_VERSION}.zip" \
      -O /opt/source.zip \
 && unzip -q /opt/source.zip -d /opt \
 && src_dir="$(find /opt -maxdepth 1 -type d -name 'T1Prep-*' | head -n 1)" \
 && test -n "${src_dir}" \
 && mv "${src_dir}" /opt/T1Prep \
 && rm /opt/source.zip

# --- python deps: NGC already has torch + cuda libs. Filter out torch from
# T1Prep's requirements so we don't fight the NGC build. Keep everything else.
WORKDIR /opt/T1Prep
RUN grep -Ev "^torch($|>=|==|<=|~=| )" requirements.txt > requirements_ngc.txt \
 && pip install --no-cache-dir -r requirements_ngc.txt

# --- Patch T1Prep's hardcoded deterministic-algorithm flag so it falls back
# to warn-only behaviour on CUDA ops (e.g. grid_sampler_3d_backward) that
# lack deterministic kernels on Blackwell. Without this, T1Prep fails on
# DGX Spark. Upstream should take `warn_only=True` as default; file a PR.
RUN sed -i 's|torch.use_deterministic_algorithms(True)|torch.use_deterministic_algorithms(True, warn_only=True)|g' \
      /opt/T1Prep/src/t1prep/segment.py

# --- Upstream case-sensitivity bug: segment.py calls get_regions_mask with
# "Neuromorphometrics" (capitalised) but the shipped atlas files are
# lowercase (neuromorphometrics.csv/.nii.gz/.txt). macOS is case-insensitive
# so the bug is invisible to upstream. On Linux we need uppercase aliases.
# File an upstream issue.
RUN cd /opt/T1Prep/src/t1prep/data/templates_MNI152NLin2009cAsym \
 && for f in neuromorphometrics.csv neuromorphometrics.nii.gz neuromorphometrics.txt; do \
      [ -e "$f" ] && ln -sf "$f" "N${f#n}"; \
    done

# --- T1Prep's own installer fetches model weights (deepmriprep, deepbet,
# CAT-surface binaries). Run it at build time so runtime is offline-safe.
# Chown to UID 1000 so `docker run --user $(id -u):$(id -g)` can write to
# the deepmriprep/deepbet model-cache dirs at runtime without perm errors.
RUN /opt/T1Prep/scripts/T1Prep --install \
 && chown -R 1000:1000 /opt/T1Prep

# --- runtime env
ENV PATH="/opt/T1Prep/scripts:${PATH}"
WORKDIR /opt/T1Prep

# Default: show help
ENTRYPOINT ["/opt/T1Prep/scripts/T1Prep"]
CMD ["--help"]
