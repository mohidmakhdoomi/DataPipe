#!/bin/bash

set -euo pipefail  # Exit on error, undefined vars, pipe failures
IFS=$'\n\t'       # Safer word splitting

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

main() {
    local workspace_delete=$(devpod delete datapipe --force 2>&1)
    local lock_delete=$(rm ~/.devpod/contexts/default/locks/datapipe.workspace.lock 2>&1)
    local provider_delete=$(devpod provider delete docker 2>&1)
    rm -rf .venv pyproject.toml uv.lock
    local docker_prune=$(docker builder prune --all --force 2>&1)
    uv clean
    uv init --python "python>=3.12,<3.13" --name 'spark-dev' --bare
    uv add pyspark==3.5.7 grpcio grpcio-status pandas pyarrow boto3 botocore
    uv lock
    local py_location=".venv/bin"
    if [ -d ".venv/Scripts" ]; then
        py_location=".venv/Scripts"
    fi
    local py_version=$("$py_location"/python --version | awk '{print $2}')
    sed -i "1s/.*/FROM python:${py_version}-slim/" Dockerfile
    rm -rf .venv
    devpod provider add docker
    exit 0
}

# Execute main function
main "$@"