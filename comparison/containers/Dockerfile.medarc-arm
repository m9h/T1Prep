# MedARC smri-fm preprocessing pipeline for NVIDIA Grace (ARM64).
#
# Base: NGC PyTorch 26.03-py3 (Ubuntu 24.04 arm64). Adds the user's own
# arm64-native FreeSurfer 8.2.0 .debs (from /home/mhough/dev/debian/) plus
# the Python stack (surfa/voxelmorph/neurite/tf/antspyx/templateflow) that
# MedARC's upstream pipeline.py relies on for mri_synthstrip + mri_synthseg.
#
# Why this arrangement over `FROM fedora:43 + dnf copr enable`:
#   - Keeps us on the same NGC PyTorch base as fastsurfer-grace and
#     t1prep-grace → uniform CUDA stack, one base to pin.
#   - MedARC's upstream Dockerfile is also ubuntu-based (via
#     freesurfer/freesurfer:7.4.1), so ours is closer to their convention.
#   - The .debs are the artefact the user has already validated working
#     (see /home/mhough/dev/debian/freesurfer/TEST_REPORT.md 2026-04-22).
#
# Known gap: mri_synthstrip + mri_synthseg are not shipped by the .deb
# (fspython is stripped, and with it the CLI wrappers). We restore their
# functionality by pip-installing the same python stack MedARC's upstream
# does, operating directly on the shipped model weights under
# /usr/lib/freesurfer/models/.

FROM nvcr.io/nvidia/pytorch:26.03-py3

LABEL maintainer="medarc-grace-build"
LABEL description="MedARC smri-fm preprocessing, ARM64 Grace build on NGC PyTorch + local FreeSurfer .debs"

ARG MEDARC_COMMIT=main

# --- args for local .deb paths (built into the image via COPY)
# Defaults point at /build/*.deb which the build context must supply.

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      tcsh ca-certificates wget git \
      python3-pip \
 && rm -rf /var/lib/apt/lists/*

# --- FreeSurfer + ITK .debs from the build context (user's local builds).
# freesurfer depends on libinsighttoolkit5 (not in Ubuntu 24.04), so we
# install them together in one apt-get call to let apt resolve ordering.
COPY libinsighttoolkit5_5.4.5-1_arm64.deb /build/
COPY freesurfer_8.2.0-2_arm64.deb /build/
COPY freesurfer-gui_8.2.0-2_arm64.deb /build/
COPY freesurfer-data_8.2.0-1_all.deb /build/
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      /build/libinsighttoolkit5_5.4.5-1_arm64.deb \
      /build/freesurfer_8.2.0-2_arm64.deb \
      /build/freesurfer-gui_8.2.0-2_arm64.deb \
      /build/freesurfer-data_8.2.0-1_all.deb \
 && rm -rf /build /var/lib/apt/lists/*

ENV FREESURFER_HOME=/usr/lib/freesurfer
ENV PATH="${FREESURFER_HOME}/bin:${PATH}"
# SUBJECTS_DIR is per-run; set at docker run time.

# --- MedARC's python deps (surfa/voxelmorph/neurite for synthstrip+synthseg,
# antspyx/templateflow for the registration pipeline). Filter torch out since
# NGC already ships it.
RUN python3 -m pip install --no-cache-dir --break-system-packages \
      nibabel antspyx numpy templateflow \
      tf-keras \
      surfa voxelmorph neurite

# The MGH pip package `synthstrip` ships the CLI wrapper; pin and install.
# For SynthSeg we shim in our own CLI (see /build/synth_cli.py) that loads
# the .h5 weights from $FREESURFER_HOME/models directly.
RUN python3 -m pip install --no-cache-dir --break-system-packages \
      synthstrip

# --- MedARC pipeline source, pinned.
RUN git clone https://github.com/MedARC-AI/smri-fm.git /app/smri-fm \
 && cd /app/smri-fm \
 && git checkout "${MEDARC_COMMIT}" \
 && rm -rf /app/smri-fm/.git

# Pre-cache the MNI152NLin2009cAsym @ 1mm templateflow asset at build time.
ENV TEMPLATEFLOW_HOME=/opt/templateflow
RUN python3 -c "import templateflow.api as tflow; tflow.get('MNI152NLin2009cAsym', resolution=1, desc='brain', suffix='T1w', extension='.nii.gz')"

# FreeSurfer license must be mounted at runtime:
#   -v ~/license.txt:/usr/lib/freesurfer/license.txt:ro

WORKDIR /app/smri-fm
ENTRYPOINT ["python3", "/app/smri-fm/preprocessing/pipeline.py"]
CMD ["--help"]
