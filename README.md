# MacAudioTranscriber

A small native macOS app that captures system audio with Core Audio process taps and transcribes English speech with Apple's Speech framework.

The app is intentionally simple: press **Start**, play English audio on the Mac, then press **Stop**. It displays a meeting-style transcript, writes a transcript file for each session, and appends diagnostics to a daily event log.

## Features

- Captures system audio, not microphone input
- Uses Core Audio process taps instead of ScreenCaptureKit
- Transcribes English audio with `SFSpeechRecognizer`
- Accepts Apple Speech partial results internally
- Shows only committed transcript chunks so unstable partial text is hidden
- Commits completed sentences immediately
- Commits unfinished chunks after a short pause
- Adds rough `Speaker N` labels using a lightweight audio-change heuristic
- Writes clean transcript files separately from diagnostics logs
- Provides an in-app button to open the logs directory

## Requirements

- macOS 14.2 or later
- Apple Silicon Mac target in the included build script
- Xcode Command Line Tools
- Speech Recognition permission
- System audio capture permission
- Dictation/Speech services enabled in macOS settings

The build script currently uses:

```sh
/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
```

If your SDK path is different, update `build.sh` and `test.sh`.

## Build

```sh
./build.sh
```

The app bundle is created at:

```text
build/MacAudioTranscriber.app
```

## Run

```sh
open build/MacAudioTranscriber.app
```

On first use, macOS may ask for permissions. If the app cannot capture or transcribe, check:

- System Settings > Privacy & Security > Speech Recognition
- System Settings > Privacy & Security > Audio Capture / Screen & System Audio Recording
- System Settings > Keyboard > Dictation

## Test

```sh
./test.sh
```

The tests cover transcript assembly behavior, including:

- partial-result ladders do not duplicate
- completed sentences stay permanent
- shorter later hypotheses cannot delete committed text
- punctuation edits in committed prefixes do not eat later sentences
- pause-committed chunks do not duplicate when later partials include them

## Output Files

Session transcripts are written to:

```text
~/Documents/MacAudioTranscriber Logs/Transcripts/
```

Diagnostics are appended to a daily log:

```text
~/Documents/MacAudioTranscriber Logs/Event Logs/YYYYMMDD.txt
```

The transcript and diagnostics files are intentionally separate.

## Transcription Policy

Apple Speech partial results are unstable: the recognizer may revise earlier words, punctuation, and sentence boundaries as more audio arrives. To avoid visible flicker and accidental deletion, the app uses this policy:

1. Accept partial results internally.
2. Hide the unstable live partial text.
3. Commit completed sentences as permanent transcript lines.
4. If there is no punctuation, commit the current hidden chunk after a short pause.
5. Never rewrite committed transcript lines.

This is a lightweight local approximation of how meeting apps handle live transcription.

## Limitations

- Speaker labels are heuristic, not true diarization.
- Apple Speech does not expose full meeting-transcript controls.
- On-device recognition quality depends on the macOS speech recognizer and local language support.
- The app is a small demo, not a production meeting recorder.

## Project Structure

```text
Sources/
  ContentView.swift              SwiftUI interface
  MacAudioTranscriberApp.swift   App entry point
  SystemAudioTranscriber.swift   Core Audio capture, Speech integration, logging
  TranscriptAssembler.swift      Stable transcript assembly logic

Tests/
  TranscriptAssemblerTests.swift Transcript assembly regression tests

build.sh                         Builds and signs the app bundle
test.sh                          Builds and runs transcript tests
Info.plist                       macOS bundle metadata and privacy strings
```

## License

Add a license before publishing if you want others to reuse the code.
