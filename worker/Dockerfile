FROM python:3.12-slim

# The following three ENVs are to ensure ray logs appear properly
ENV RAY_ROTATION_MAX_BYTES=10485760
ENV RAY_ROTATION_BACKUP_COUNT=1
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV UV_SYSTEM_PYTHON=1
ENV PYTHONPATH=/app

# Install system dependencies and UV
# build-essential is needed for compiling webrtcvad (used by resemblyzer for diarization)
# libsndfile1 is needed for soundfile/librosa
RUN apt-get update && apt-get install -y \
    ffmpeg \
    curl \
    build-essential \
    libsndfile1 \
    && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir uv

WORKDIR /app

# Copy only requirements to cache them in docker layer
COPY pyproject.toml README.md ./

# Install project dependencies using UV (much faster than Poetry)
# Default: worker only
ARG INSTALL_EXTRAS="worker"
RUN uv pip install --system -e ".[$INSTALL_EXTRAS]"

# Copy the FastAPI application code
COPY common common
COPY backend/__init__.py backend/__init__.py
COPY worker worker

RUN chmod +x worker/entrypoint.sh

CMD [ "/bin/bash", "worker/entrypoint.sh" ]
