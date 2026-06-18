# MacAudioTranscriber Architecture

## Overview

A macOS app that captures all system audio in real-time using Core Audio process taps and transcribes it on-device using whisper.cpp. No cloud APIs, no microphone needed -- it listens to whatever audio is playing on the Mac (videos, calls, music, etc).

## System Diagram

```
+-----------------------+
|   macOS System Audio  |
+-----------+-----------+
            |
            v
+-------------------------------------------+
|       ProcessTapAudioCapture              |
|  (Core Audio process tap + aggregate      |
|   device, captures all system audio)      |
|  Format: 44100Hz, float32, mono LPCM     |
+-------------------+-----------------------+
                    |
                    | AVAudioPCMBuffer (IO thread)
                    v
+-------------------------------------------+
|         WhisperTranscriber                |
|                                           |
|  1. Resample: 44100Hz -> 16000Hz          |
|  2. Ring buffer accumulates samples       |
|  3. Every 5s chunk -> whisper inference   |
|  4. Background thread (processingQueue)   |
|  5. Results -> callback with timestamp    |
|                                           |
|  Model: ggml-small.en.bin (465MB)         |
|  Engine: whisper.cpp (C/C++ via bridging) |
+-------------------+-----------------------+
                    |
                    | (text, isFinal, timestamp)
                    v
+-------------------------------------------+
|       TranscriptAssembler                 |
|                                           |
|  committedLines: ["00:00: text", ...]     |
|  liveText: current partial (if any)       |
|  displayText: all lines joined            |
|                                           |
|  Lines are append-only, never erased.     |
+-------------------+-----------------------+
                    |
                    | @Published transcript
                    v
+-------------------------------------------+
|     SystemAudioTranscriber (@MainActor)   |
|                                           |
|  Orchestrator that owns all components.   |
|  Manages session lifecycle, logging,      |
|  transcript file writing, UI bindings.    |
+-------------------+-----------------------+
                    |
                    | @EnvironmentObject
                    v
+-------------------------------------------+
|           ContentView (SwiftUI)           |
|                                           |
|  - Start/Stop button                      |
|  - Scrollable transcript display          |
|  - Log panel                              |
|  - File output links                      |
+-------------------------------------------+
```

## File Map

| File | Role |
|------|------|
| `Sources/MacAudioTranscriberApp.swift` | App entry point. Creates `SystemAudioTranscriber` as `@StateObject`. |
| `Sources/SystemAudioTranscriber.swift` | Main orchestrator. Owns audio capture, whisper pipeline, assembler, session management, logging, file writing. Contains `ProcessTapAudioCapture` (Core Audio). |
| `Sources/WhisperTranscriber.swift` | Swift wrapper around whisper.cpp C API. Ring buffer, resampling, chunked inference on background thread. |
| `Sources/TranscriptAssembler.swift` | Accumulates transcript lines with timestamps. Append-only committed lines + live text. |
| `Sources/ContentView.swift` | SwiftUI view. Displays transcript, log, controls. |
| `Sources/BridgingHeader.h` | Imports `whisper.h` for Swift-C interop. |

## Key Design Decisions

### Why whisper.cpp instead of Apple SFSpeechRecognizer?

Apple's speech framework has a hard 60-second limit per recognition task. For continuous audio (like transcribing a movie), this forces periodic restarts with gaps and potential word loss at boundaries. whisper.cpp has no time limit and runs entirely on-device.

### Why 5-second chunks?

Balance between latency and accuracy. Shorter chunks (2-3s) produce faster results but whisper has less context and accuracy drops. Longer chunks (10s+) give better accuracy but the small.en model can't process them faster than real-time, causing backlog. 5s is the sweet spot for small.en on Apple Silicon.

### Why no overlap between chunks?

Earlier versions used 1s overlap to avoid losing words at chunk boundaries. This caused duplicate text in the output. Since each chunk is transcribed independently, there's no reliable way to deduplicate the overlap region. Clean sequential chunks produce better results overall.

### Audio Pipeline Threading

```
IO Thread (Core Audio)  ->  appendAudio()  ->  ring buffer (NSLock)
                                                     |
                                                     v
Background Thread (processingQueue)  ->  transcribe()  ->  callback
                                                                |
                                                                v
                                                     MainActor (UI update)
```

Audio capture runs on Core Audio's IO thread and must not block. Samples are appended to a lock-protected ring buffer. A dedicated background queue drains the buffer in chunks and runs whisper inference. Results are dispatched to MainActor for UI updates.

## Build System

No Xcode project or Swift Package Manager. The app compiles directly with `swiftc` via `build.sh`:

1. `install.sh` -- clones whisper.cpp, builds static libraries (CMake), downloads the model
2. `build.sh` -- compiles Swift sources, links against whisper.cpp static libs, bundles model into .app

Static libraries linked: `libwhisper.a`, `libparakeet.a`, `libggml.a`, `libggml-base.a`, `libggml-cpu.a`, `libggml-metal.a`, `libggml-blas.a`

Frameworks: AppKit, AVFoundation, CoreAudio, SwiftUI, Accelerate, Metal

## Model

Currently using `ggml-small.en.bin` (465MB, English-only). Bundled inside `.app/Contents/Resources/`. Falls back to `./models/` directory during development.

Available models (speed vs accuracy tradeoff):

| Model | Size | Notes |
|-------|------|-------|
| tiny.en | 74MB | Fast, rough accuracy |
| base.en | 142MB | Decent accuracy |
| small.en | 466MB | Good accuracy (current) |
| medium.en | 1.5GB | Very good, slower |
| large | 3GB | Best, too slow for real-time |

Parakeet TDT is a future alternative -- see `docs/PARAKEET-SETUP.md`.

## Requirements

- macOS 14.2+ (for Core Audio process taps)
- Apple Silicon (arm64)
- Xcode Command Line Tools
- CMake
