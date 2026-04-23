# 1. Use the NVIDIA PyTorch Base Image (Ubuntu 24.04, Python 3.12, CUDA 12.6)
FROM nvcr.io/nvidia/pytorch:24.12-py3

# 2. Set Metadata
LABEL maintainer="FastSurfer-Grace-Build"
LABEL description="FastSurfer container optimized for NVIDIA Grace (ARM64)"

# 3. Set Working Directory
WORKDIR /opt/FastSurfer

# 4. Copy Source Code
COPY . .

# 5. Install System Dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libsuitesparse-dev \
    && rm -rf /var/lib/apt/lists/*

# 6. Install Python Dependencies
RUN grep -v "torch" requirements.txt | grep -v "nvidia-" | grep -v "triton" > requirements_native.txt && \
    pip install --no-cache-dir -r requirements_native.txt

# 7. CRITICAL FIX: Patch the startup script to use Python 3 instead of 3.10
RUN sed -i 's/python3.10/python3/g' run_fastsurfer.sh

# 8. Environment Setup
ENV PYTHONPATH="/opt/FastSurfer:${PYTHONPATH}"

# 9. Default Command
CMD ["/bin/bash"]
