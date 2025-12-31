#!/bin/bash

PAL_NAME=pal-mcp-server
ZIP_VERSION=9.8.2
CUSTOM_CONFIG=openrouter_models.json

mkdir -p .kiro/settings/pal
cd .kiro/settings/pal

BASE_DIR="$(pwd)"
PAL_DIR_PREFIX="${BASE_DIR}/${PAL_NAME}"

rm -rf $PAL_DIR_PREFIX*

curl -L -o "${PAL_NAME}.zip" \
    "https://github.com/BeehiveInnovations/pal-mcp-server/archive/refs/tags/v${ZIP_VERSION}.zip"
unzip -q "${PAL_NAME}.zip"
cp "${BASE_DIR}/${CUSTOM_CONFIG}" "${PAL_DIR_PREFIX}-${ZIP_VERSION}/conf/${CUSTOM_CONFIG}"

cd "${PAL_DIR_PREFIX}-${ZIP_VERSION}"
docker build --no-cache -t "${PAL_NAME}" .