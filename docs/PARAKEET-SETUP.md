# Parakeet TDT Model Setup (Alternative to Whisper)

whisper.cpp has native Parakeet support built in (parakeet.h / libparakeet.a).
No pre-converted .bin model exists publicly — must convert from NVIDIA's NeMo checkpoint.

## Steps

### 1. Download NeMo checkpoint

From https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2

```bash
# Option A: git lfs
git lfs install
git clone https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2

# Option B: direct download of .nemo file (~1.2GB)
curl -L -o parakeet-tdt-0.6b-v2.nemo \
  "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2/resolve/main/parakeet-tdt-0.6b-v2.nemo"
```

### 2. Install Python dependencies

```bash
pip install -r vendor/whisper.cpp/models/requirements-parakeet.txt
pip install torch nemo_toolkit
```

### 3. Convert to GGML .bin

```bash
python vendor/whisper.cpp/models/convert-parakeet-to-ggml.py \
  --model parakeet-tdt-0.6b-v2.nemo \
  --output-dir models/
```

Output: `models/ggml-parakeet-tdt-0.6b-v2.bin`

### 4. Code changes needed

In `Sources/BridgingHeader.h`, add:
```c
#include "parakeet.h"
```

Create `Sources/ParakeetTranscriber.swift` mirroring `WhisperTranscriber.swift` but using:
- `parakeet_context_default_params()` instead of `whisper_context_default_params()`
- `parakeet_init_from_file_with_params()` instead of `whisper_init_from_file_with_params()`
- `parakeet_full_default_params()` instead of `whisper_full_default_params()`
- `parakeet_full()` instead of `whisper_full()`
- `parakeet_full_n_segments()` / `parakeet_full_get_segment_text()` for results
- `parakeet_free()` for cleanup

The API is nearly identical to whisper — same pattern, just different prefix.

In `Sources/SystemAudioTranscriber.swift`, update `modelPath` and swap `WhisperTranscriber` for `ParakeetTranscriber`.

### 5. Build

`libparakeet.a` is already compiled and linked. No build.sh changes needed beyond bundling the model file.

## Model info

- NVIDIA Parakeet TDT 0.6B: English-only, ~600M params
- Known for better accuracy than Whisper small on English speech
- Same 16kHz mono float32 input format
- v3 also available: `nvidia/parakeet-tdt-0.6b-v3`
