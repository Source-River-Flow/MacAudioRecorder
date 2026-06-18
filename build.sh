#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MacAudioTranscriber"
APP_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
WHISPER_DIR="vendor/whisper.cpp"
WHISPER_BUILD="${WHISPER_DIR}/build-static"

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
mkdir -p ".build/module-cache"
cp Info.plist "${CONTENTS_DIR}/Info.plist"

if [ ! -f "${WHISPER_BUILD}/src/libwhisper.a" ]; then
  echo "Building whisper.cpp static libraries..."
  cmake -S "${WHISPER_DIR}" -B "${WHISPER_BUILD}" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_BUILD_TYPE=Release \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_SERVER=OFF \
    -DGGML_METAL=ON \
    -DGGML_ACCELERATE=ON \
    -DBUILD_SHARED_LIBS=OFF \
    >/dev/null 2>&1
  cmake --build "${WHISPER_BUILD}" --config Release -j"$(sysctl -n hw.ncpu)" 2>&1 | tail -5
fi

echo "Compiling Swift app with whisper.cpp..."
swiftc \
  -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
  -module-cache-path .build/module-cache \
  -target arm64-apple-macos14.2 \
  -parse-as-library \
  -import-objc-header Sources/BridgingHeader.h \
  -I "${WHISPER_DIR}/include" \
  -I "${WHISPER_DIR}/ggml/include" \
  -L "${WHISPER_BUILD}/src" \
  -L "${WHISPER_BUILD}/ggml/src" \
  -L "${WHISPER_BUILD}/ggml/src/ggml-metal" \
  -L "${WHISPER_BUILD}/ggml/src/ggml-blas" \
  -lwhisper -lparakeet -lggml -lggml-base -lggml-cpu -lggml-metal -lggml-blas \
  -o "${MACOS_DIR}/${APP_NAME}" \
  Sources/*.swift \
  -framework AppKit \
  -framework AVFoundation \
  -framework CoreAudio \
  -framework SwiftUI \
  -framework Accelerate \
  -framework Metal \
  -framework Foundation \
  -framework CoreML \
  -lc++

cp models/ggml-small.en.bin "${RESOURCES_DIR}/ggml-small.en.bin"

codesign --force --sign - "${APP_DIR}" >/dev/null

echo "${APP_DIR}"
