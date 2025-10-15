#!/bin/bash

C2P_NAME=code2prompt-mcp
ZIP_VERSION=main

mkdir -p .kiro/settings/code2prompt
cd .kiro/settings/code2prompt

BASE_DIR="$(pwd)"
C2P_DIR_PREFIX="${BASE_DIR}/${C2P_NAME}"

rm -rf $C2P_DIR_PREFIX*

curl -L -o "${C2P_NAME}.zip" \
    "https://github.com/ODAncona/code2prompt-mcp/archive/refs/heads/${ZIP_VERSION}.zip"
unzip -q "${C2P_NAME}.zip"

cd "${C2P_DIR_PREFIX}-${ZIP_VERSION}"
sed -i "s/FROM python:slim/FROM python:3.13-slim/g" Dockerfile
docker build --no-cache -t "${C2P_NAME}" .