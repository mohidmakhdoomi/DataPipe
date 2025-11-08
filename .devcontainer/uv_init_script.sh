#!/bin/bash

set -euo pipefail  # Exit on error, undefined vars, pipe failures
IFS=$'\n\t'       # Safer word splitting

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

main() {
    rm -rf .venv pyproject.toml uv.lock
    uv init --python "python>=3.12,<3.13" --name 'spark-dev' --bare --no-cache
    uv add pyspark==3.5.7 grpcio grpcio-status pandas pyarrow --no-cache
    uv lock
    local py_version=$(.venv/Scripts/python.exe --version | awk '{print $2}')
    sed -i "1s/.*/FROM python:${py_version}-slim/" Dockerfile
    rm -rf .venv
    exit 0
}

# Execute main function
main "$@"