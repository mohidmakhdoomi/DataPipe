#!/bin/bash

C2P_NAME=code2prompt-mcp
ZIP_VERSION=main

cd .kiro/settings/code2prompt

BASE_DIR="$(pwd)"
C2P_DIR_PREFIX="${BASE_DIR}/${C2P_NAME}"

rm -rf $C2P_DIR_PREFIX*

curl -L -o "${C2P_NAME}.zip" \
    "https://github.com/ODAncona/code2prompt-mcp/archive/refs/heads/main.zip"
unzip -q "${C2P_NAME}.zip"

cd "${C2P_DIR_PREFIX}-${ZIP_VERSION}"

docker build --no-cache -t "${C2P_NAME}" .