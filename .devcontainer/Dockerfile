FROM python:3.12.11-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PATH="/root/.local/bin:/workspace/.venv/bin:${PATH}" \
    UV_LINK_MODE=copy

# check uv container

RUN --mount=type=cache,target=/var/cache/apt \
    set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      curl bash git ca-certificates procps \
    && apt-get install -y openssh-client && rm -rf /var/lib/apt/lists/*

# uv package manager
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

WORKDIR /workspace/.devcontainer

COPY .devcontainer/pyproject.toml .devcontainer/uv.lock ./

RUN ls -al

# 1) Create venv and install ONLY dependencies
RUN --mount=type=cache,target=/root/.cache/uv \
    uv venv && uv sync --locked --no-install-project --no-dev

WORKDIR /workspace

COPY . .

RUN ls -al

RUN --mount=type=cache,target=/root/.cache/uv \
    cd .devcontainer && uv sync --locked --no-dev

ENV PYSPARK_PYTHON=/workspace/.devcontainer/.venv/bin/python \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# [OPTIONAL] This line is for auto-activation in interactive shells
RUN echo "alias ll='ls -al'" >> /root/.bashrc
RUN echo "chmod 700 /root/.ssh && chmod 600 /root/.ssh/*" >> /root/.bashrc
RUN echo "source /workspace/.devcontainer/.venv/bin/activate" >> /root/.bashrc

WORKDIR /workspace

RUN ls -al

# DevContainers and VS Code can control how the container is launched.
ENTRYPOINT []