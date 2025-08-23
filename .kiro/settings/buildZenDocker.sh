#!/bin/bash

ZIP_FILE=zen-mcp-server.zip
ZIP_VERSION=5.10.0
CUSTOM_CONFIG=custom_models.json
CUSTOM_ENV=.env.zen

cd .kiro/settings

BASE_DIR=$(pwd)
ZEN_DIR="${BASE_DIR}/zen-mcp-server"
TMP_DIR="${BASE_DIR}/tmp"

rm -rf $ZEN_DIR
mkdir $ZEN_DIR

rm -rf $TMP_DIR
mkdir $TMP_DIR
cd $TMP_DIR
curl -L -o $ZIP_FILE \
    "https://github.com/BeehiveInnovations/zen-mcp-server/archive/refs/tags/v${ZIP_VERSION}.zip"

unzip -q $ZIP_FILE
cp -r zen-mcp-server-$ZIP_VERSION/* $ZEN_DIR
cp "${BASE_DIR}/${CUSTOM_CONFIG}" $ZEN_DIR/conf/$CUSTOM_CONFIG
cp "${BASE_DIR}/${CUSTOM_ENV}" $ZEN_DIR/.env

cd $ZEN_DIR
rm -rf $TMP_DIR
docker build --no-cache -t zen-mcp-server .