#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MacAudioTranscriber"
APP_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

mkdir -p "${MACOS_DIR}"
mkdir -p ".build/module-cache"
cp Info.plist "${CONTENTS_DIR}/Info.plist"

swiftc \
  -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
  -module-cache-path .build/module-cache \
  -target arm64-apple-macos14.2 \
  -parse-as-library \
  -o "${MACOS_DIR}/${APP_NAME}" \
  Sources/*.swift \
  -framework AppKit \
  -framework AVFoundation \
  -framework CoreAudio \
  -framework Speech \
  -framework SwiftUI

codesign --force --sign - "${APP_DIR}" >/dev/null

echo "${APP_DIR}"
