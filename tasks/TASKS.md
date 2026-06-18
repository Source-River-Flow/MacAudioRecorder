# Whisper Integration - Real-Time Transcription

Branch: `feature/whisper-transcription` (from `main`, independent of `fix/realtime-transcription-pipeline`)

## Goal
Replace Apple's SFSpeechRecognizer with bundled whisper.cpp for continuous real-time transcription of system audio. No 60-second limit, no restarts, no gaps.

## Current State
- Branch created from `main` (original code with Apple Speech framework)
- All source files are at their original state (pre-optimization)
- Build system: `swiftc` via `build.sh`, no Package.swift for the app itself

## Architecture
```
Core Audio Tap (existing) --> Ring Buffer --> whisper.cpp (sliding window, ~5s chunks with overlap)
                                                  |
                                          TranscriptAssembler (accumulator + live text)
                                                  |
                                          ContentView (existing SwiftUI)
```

## Tasks

### 1. Add whisper.cpp dependency
- [x] Clone/vendor whisper.cpp source into project
- [x] Download ggml-tiny.en.bin model (~75MB)
- [x] Update build.sh to compile whisper.cpp C/C++ and link with Swift app
- [x] Verify compiles on macOS Apple Silicon (Accelerate, Metal)

### 2. Create Swift wrapper for whisper.cpp
- [x] Create WhisperTranscriber.swift bridging file
- [x] Create C bridging header for whisper.h
- [x] Implement: load model, create context, process audio, get text
- [x] Audio format conversion: 44100Hz float32 --> 16kHz mono float32

### 3. Implement streaming pipeline
- [x] Ring buffer accumulating audio from Core Audio tap
- [x] Sliding window: ~5s chunks with ~1s overlap
- [x] Whisper inference on background thread
- [x] Feed results to TranscriptAssembler

### 4. Rewrite SystemAudioTranscriber
- [x] Remove all SFSpeechRecognizer code
- [x] Keep: Core Audio ProcessTapAudioCapture
- [x] Keep: Session management, logging, file writing, UI bindings
- [x] Wire audio capture --> ring buffer --> whisper pipeline

### 5. Simplify TranscriptAssembler
- [x] Accumulator + live text model (no prefix stripping, no sentence splitting)
- [x] update(text:isFinal:) and commitLive() only

### 6. Update build and bundle
- [x] Bundle whisper model in .app
- [x] Update build.sh to copy model into bundle
- [x] Test full clean build

### 7. Test and tune
- [ ] Test with pre-recorded video audio (primary use case)
- [ ] Tune chunk size vs latency
- [ ] Verify no audio gaps (overlap handling)
- [ ] Verify memory (~200MB for tiny model)
- [ ] Test start/stop lifecycle

## Key Files
- `Sources/SystemAudioTranscriber.swift` - rewrite
- `Sources/TranscriptAssembler.swift` - simplify
- `Sources/ContentView.swift` - keep as-is
- `build.sh` - update for whisper.cpp
- NEW: `Sources/WhisperTranscriber.swift`
- NEW: `Sources/BridgingHeader.h`

## Notes
- whisper.cpp is MIT licensed
- Use ggml-tiny.en for English-only, smallest footprint
- This branch will NOT merge into fix/realtime-transcription-pipeline
- Previous branch `fix/realtime-transcription-pipeline` has Apple Speech optimizations as fallback

_Updated: 2026-06-19_
