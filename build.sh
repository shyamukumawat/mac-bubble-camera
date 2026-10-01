#!/usr/bin/env bash
set -e

echo "==> Building CameraBubble for macOS..."

APP_NAME="CameraBubble"
BUILD_DIR="./build"
TARGET_APP="/Applications/${APP_NAME}.app"

# Clean build directory
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}/${APP_NAME}.app/Contents/MacOS"
mkdir -p "${BUILD_DIR}/${APP_NAME}.app/Contents/Resources"

# Compile Swift code
swiftc -O -target arm64-apple-macos14.0 Sources/main.swift -o "${BUILD_DIR}/${APP_NAME}.app/Contents/MacOS/${APP_NAME}"

# Copy Info.plist
cp Info.plist "${BUILD_DIR}/${APP_NAME}.app/Contents/"

# Ad-hoc code signing
codesign --force --deep -s - "${BUILD_DIR}/${APP_NAME}.app"

echo "==> Installing to /Applications..."
killall "${APP_NAME}" 2>/dev/null || true
sleep 0.5
rm -rf "${TARGET_APP}"
cp -R "${BUILD_DIR}/${APP_NAME}.app" /Applications/

echo "==> CameraBubble successfully installed to /Applications."
echo "==> Launching CameraBubble..."
open "${TARGET_APP}"
