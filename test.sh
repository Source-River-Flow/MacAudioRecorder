#!/usr/bin/env bash
set -euo pipefail

mkdir -p ".build/module-cache"

swiftc \
  -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
  -module-cache-path .build/module-cache \
  -target arm64-apple-macos14.2 \
  Sources/TranscriptAssembler.swift \
  Tests/TranscriptAssemblerTests.swift \
  -o .build/TranscriptAssemblerTests

.build/TranscriptAssemblerTests
