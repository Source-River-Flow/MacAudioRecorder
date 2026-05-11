# Architecture

MacAudioTranscriber has three main parts:

1. Core Audio capture
2. Apple Speech transcription
3. Stable transcript assembly

## Core Audio Capture

`ProcessTapAudioCapture` creates a Core Audio process tap with `CATapDescription(monoGlobalTapButExcludeProcesses:)`.

The app excludes its own process so system playback is captured without feeding the app's output back into itself. The tap is attached to a private aggregate device, and an IOProc receives audio buffers from that aggregate device.

Captured buffers are forwarded to `SFSpeechAudioBufferRecognitionRequest`.

## Speech Recognition

`SystemAudioTranscriber` owns the Apple Speech request and recognition task.

The app enables partial results because final-only recognition can take too long on continuous system audio. Partial results are accepted internally, but the unstable live partial is not displayed as transcript text.

When Apple Speech returns a final result, the current hidden chunk is committed and the recognition task is restarted.

## Stable Transcript Assembly

`TranscriptAssembler` converts Apple's unstable recognition stream into a meeting-style transcript.

The policy is:

- Accept partial recognition text internally.
- Hide live partial text from the user.
- Commit completed sentences as permanent transcript lines.
- Commit an unfinished chunk after a pause.
- Treat pause-committed chunks as part of the committed prefix.
- Strip already-committed prefix text from later partials.
- Never rewrite committed transcript lines.

This prevents common partial-recognition failures:

- duplicate expanding lines
- old sentences disappearing
- punctuation changes eating the next sentence
- shorter later hypotheses deleting committed text

## Speaker Labels

Speaker labels are generated with a lightweight heuristic. The app computes simple audio profiles from recent captured buffers and compares each committed line with the previous committed line.

If the audio profile changes enough after a short gap, the app increments the speaker number.

This is not true diarization. It is a local, dependency-free approximation.

## Logs

The app writes two types of files:

- Session transcript files in `~/Documents/MacAudioTranscriber Logs/Transcripts/`
- Daily diagnostics logs in `~/Documents/MacAudioTranscriber Logs/Event Logs/`

Diagnostics and transcript content are intentionally kept separate.
