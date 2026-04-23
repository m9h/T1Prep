# FastSurfer full pipeline (segmentation + recon_surf) for NVIDIA Grace (arm64).
#
# Extends the user's arm64 seg-only image from Deep-MI/FastSurfer#716 with
# the FreeSurfer 7.4.1 CLI toolchain that recon_surf.sh requires. Upstream
# FastSurfer pins FS_VERSION_SUPPORT="7.4.1" and aborts unless that exact
# version is present. The neurodebian agent provides 7.4.1 as an arm64
# .deb co-installable alongside FreeSurfer 8.2.0 (install prefix
# /usr/lib/freesurfer-7.4.1/).
#
# Build context must contain:
#   - All of /home/mhough/src/FastSurfer/  (COPY . .)
#   - freesurfer-7.4.1_7.4.1-1_arm64.deb
#   - libinsighttoolkit5_5.4.5-1_arm64.deb
#   - (optional) freesurfer-python_8.2.0-1_all.deb  for mri_synthstrip/mri_synthseg

FROM nvcr.io/nvidia/pytorch:24.12-py3

LABEL maintainer="fastsurfer-full-arm"
LABEL org.opencontainers.image.source="https://github.com/Deep-MI/FastSurfer"
LABEL org.opencontainers.image.description="FastSurfer seg + recon_surf on arm64, paired with FreeSurfer 7.4.1"
LABEL org.opencontainers.image.architecture="arm64"

ENV DEBIAN_FRONTEND=noninteractive

# --- system deps: FastSurfer's C bits + FreeSurfer runtime deps
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libsuitesparse-dev \
      tcsh perl bc \
      libgl1 libglu1-mesa libglut3.12 \
      libgiftiio0 libtet1.5 \
      libgomp1 \
 && rm -rf /var/lib/apt/lists/*

# --- FreeSurfer 7.4.1 + ITK 5.4 via local .debs
COPY libinsighttoolkit5_5.4.5-1_arm64.deb /build/
COPY freesurfer-7.4.1_7.4.1-1_arm64.deb /build/
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      /build/libinsighttoolkit5_5.4.5-1_arm64.deb \
      /build/freesurfer-7.4.1_7.4.1-1_arm64.deb \
 && rm -rf /build /var/lib/apt/lists/* \
 && if ! ldd /usr/lib/freesurfer-7.4.1/bin/mri_convert | grep -qE 'libitk[a-z0-9_]+-5\.4\.so'; then \
        echo "FATAL: mri_convert not linking ITK 5.4"; \
        ldd /usr/lib/freesurfer-7.4.1/bin/mri_convert | grep -iE 'itk|vnl' | head; \
        exit 1; \
    fi

# FastSurfer looks up $FREESURFER_HOME; pin at the 7.4.1 prefix.
ENV FREESURFER_HOME=/usr/lib/freesurfer-7.4.1
ENV PATH="${FREESURFER_HOME}/bin:${PATH}"
# User must mount their FreeSurfer license at runtime:
#   -v ~/license.txt:${FREESURFER_HOME}/license.txt:ro

# --- FastSurfer source (build context is the FastSurfer repo root)
WORKDIR /opt/FastSurfer
COPY . .

# Filter torch/nvidia/triton from requirements so NGC's optimised torch stack
# isn't clobbered; pin the rest. Same trick as the seg-only image.
RUN grep -v "^torch" requirements.txt | grep -v "^nvidia-" | grep -v "^triton" > requirements_native.txt \
 && pip install --no-cache-dir -r requirements_native.txt

# Upstream shebang hardcodes python3.10; NGC's 24.12 has python 3.12.
RUN sed -i 's/python3.10/python3/g' run_fastsurfer.sh
ENV PYTHONPATH="/opt/FastSurfer:"
ENV PATH="/opt/FastSurfer:${PATH}"

# Sanity — FreeSurfer + FastSurfer entry points resolve
RUN ls ${FREESURFER_HOME}/bin/mris_register ${FREESURFER_HOME}/bin/mri_em_register \
      ${FREESURFER_HOME}/bin/mri_aparc2aseg ${FREESURFER_HOME}/bin/mris_sphere \
 && ls /opt/FastSurfer/run_fastsurfer.sh \
 && echo "fastsurfer-full sanity OK"

CMD ["/bin/bash"]
