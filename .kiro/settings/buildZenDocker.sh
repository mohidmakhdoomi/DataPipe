#!/bin/bash

ZEN_NAME=zen-mcp-server
ZIP_VERSION=7.4.0
CUSTOM_CONFIG=openrouter_models.json

mkdir -p .kiro/settings/zen
cd .kiro/settings/zen

BASE_DIR="$(pwd)"
ZEN_DIR_PREFIX="${BASE_DIR}/${ZEN_NAME}"

rm -rf $ZEN_DIR_PREFIX*

curl -L -o "${ZEN_NAME}.zip" \
    "https://github.com/BeehiveInnovations/zen-mcp-server/archive/refs/tags/v${ZIP_VERSION}.zip"
unzip -q "${ZEN_NAME}.zip"
cp "${BASE_DIR}/${CUSTOM_CONFIG}" "${ZEN_DIR_PREFIX}-${ZIP_VERSION}/conf/${CUSTOM_CONFIG}"

cd "${ZEN_DIR_PREFIX}-${ZIP_VERSION}"
docker build --no-cache -t "${ZEN_NAME}" .