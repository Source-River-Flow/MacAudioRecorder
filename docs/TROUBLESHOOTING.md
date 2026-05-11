# Troubleshooting

## The App Shows No Transcript

Check the in-app log panel first.

Common causes:

- Speech Recognition permission was denied.
- Dictation/Speech services are disabled in macOS settings.
- System audio capture permission was denied.
- The audio being played does not contain clear English speech.
- The app is receiving partial text internally, but no sentence or pause has been committed yet.

Try speaking or playing audio with clear pauses between sentences.

## Siri and Dictation Are Disabled

Apple Speech can fail with an error like:

```text
Siri and Dictation are disabled
```

Enable Dictation in:

```text
System Settings > Keyboard > Dictation
```

Then relaunch the app.

## Permission Was Requested, Then Capture Stopped

Open macOS privacy settings and make sure the app is allowed for:

- Speech Recognition
- System audio capture / Screen & System Audio Recording

After changing permissions, quit and relaunch the app.

## Transcript Text Appears Slowly

This is expected. The app hides unstable partial text and only displays committed transcript chunks.

Chunks are committed when:

- Apple Speech produces a completed sentence, or
- the current hidden chunk stops changing for a short pause.

## Speaker Labels Are Wrong

Speaker labels are heuristic. They are based on simple audio-profile changes, not a trained diarization model.

They may be wrong when:

- speakers sound similar
- the same speaker changes volume
- background audio changes
- music or effects are playing
- there are overlapping voices

## Build Fails Because the SDK Path Is Missing

The scripts reference:

```text
/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
```

If your installed SDK differs, edit `build.sh` and `test.sh`.

You can inspect installed SDKs with:

```sh
ls /Library/Developer/CommandLineTools/SDKs
```
