#!/usr/bin/env bash
set -euo pipefail

echo "=== MacAudioTranscriber Setup ==="
echo ""

# 1. Clone whisper.cpp if not present
if [ ! -d "vendor/whisper.cpp" ]; then
  echo "[1/3] Cloning whisper.cpp..."
  mkdir -p vendor
  git clone --depth 1 https://github.com/ggml-org/whisper.cpp.git vendor/whisper.cpp
else
  echo "[1/3] whisper.cpp already present."
fi

# 2. Build whisper.cpp static libraries
if [ ! -f "vendor/whisper.cpp/build-static/src/libwhisper.a" ]; then
  echo "[2/3] Building whisper.cpp (this may take a minute)..."
  cmake -S vendor/whisper.cpp -B vendor/whisper.cpp/build-static \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_BUILD_TYPE=Release \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_SERVER=OFF \
    -DGGML_METAL=ON \
    -DGGML_ACCELERATE=ON \
    -DBUILD_SHARED_LIBS=OFF \
    >/dev/null 2>&1
  cmake --build vendor/whisper.cpp/build-static --config Release -j"$(sysctl -n hw.ncpu)" 2>&1 | tail -3
  echo "  Done."
else
  echo "[2/3] whisper.cpp already built."
fi

# 3. Download whisper model
MODEL_DIR="models"
MODEL_FILE="${MODEL_DIR}/ggml-small.en.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin"

if [ ! -f "${MODEL_FILE}" ]; then
  echo "[3/3] Downloading whisper small.en model (~465MB)..."
  mkdir -p "${MODEL_DIR}"
  curl -L --progress-bar -o "${MODEL_FILE}" "${MODEL_URL}"
  echo "  Done."
else
  echo "[3/3] Model already downloaded."
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "To build the app:  bash build.sh"
echo "To run the app:    open build/MacAudioTranscriber.app"
echo ""
