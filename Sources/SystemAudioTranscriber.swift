import AppKit
import AVFoundation
import CoreAudio
import Darwin
import Foundation

@MainActor
final class SystemAudioTranscriber: NSObject, ObservableObject {
    @Published var transcript = ""
    @Published var status = "Idle"
    @Published var isRunning = false
    @Published var logMessages: [String]
    @Published var lastTranscriptFile: URL?
    @Published var dailyEventLogFile: URL?

    var latestLogMessage: String {
        logMessages.last ?? "No log messages yet."
    }

    var logsDirectory: URL {
        Self.logsDirectory
    }

    private var audioCapture: ProcessTapAudioCapture?
    private let whisper = WhisperTranscriber()
    private var sessionStartDate: Date?
    private var sessionEventMessages: [String] = []
    private var sessionAudioFrameCount: AVAudioFramePosition = 0
    private var sessionAudioFormatSummary = "unknown"
    private var sessionAudioSampleRate: Double?
    private var sessionFilesWritten = false
    private var transcriptAssembler = TranscriptAssembler()
    private var hasUserPressedStart = false
    private var modelLoaded = false

    override init() {
        let timestamp = Self.logTimeFormatter.string(from: Date())
        logMessages = ["[\(timestamp)] App launched idle. Recording will not start until Start is clicked."]
        super.init()
        preloadModel()
    }

    func start() {
        guard !isRunning else { return }
        hasUserPressedStart = true
        beginSession()
        log("Start button pressed.")

        guard modelLoaded else {
            setStatus("Whisper model not loaded. Cannot start.")
            return
        }

        Task {
            await startCapture()
        }
    }

    func stop() {
        guard isRunning || audioCapture != nil else { return }

        setStatus("Stopping...")
        isRunning = false
        log("Stopping transcription.")

        whisper.stop()
        transcriptAssembler.commitLive()
        refreshTranscriptText()

        do {
            try audioCapture?.stop()
            audioCapture = nil
            setStatus("Stopped")
        } catch {
            audioCapture = nil
            setStatus("Stopped with error: \(error.localizedDescription)")
            log("Stop error: \(error.diagnosticDescription)")
        }

        writeSessionFilesAfterStop()
    }

    func clear() {
        transcript = ""
    }

    func clearLog() {
        logMessages = []
        log("Log cleared.")
    }

    func openLogsDirectory() {
        do {
            try FileManager.default.createDirectory(at: Self.logsDirectory, withIntermediateDirectories: true)
            let didOpen = NSWorkspace.shared.open(Self.logsDirectory)
            log(didOpen ? "Opened logs folder: \(Self.logsDirectory.path)" : "Finder did not open logs folder: \(Self.logsDirectory.path)")
        } catch {
            log("Could not create/open logs folder: \(error.diagnosticDescription)")
        }
    }

    private func preloadModel() {
        let modelPath = Self.modelPath
        log("Looking for whisper model at: \(modelPath)")

        guard FileManager.default.fileExists(atPath: modelPath) else {
            log("Whisper model not found at \(modelPath)")
            return
        }

        modelLoaded = whisper.loadModel(at: modelPath) { [weak self] message in
            Task { @MainActor in
                self?.log(message)
            }
        }
    }

    private func startCapture() async {
        guard hasUserPressedStart else {
            log("Ignoring capture start because Start has not been clicked.")
            return
        }

        log("Preparing Core Audio tap for whisper transcription.")

        do {
            setStatus("Preparing system audio capture...")

            whisper.start { [weak self] text, isFinal, timestamp in
                Task { @MainActor in
                    guard let self, self.isRunning else { return }
                    self.transcriptAssembler.update(text: text, isFinal: isFinal, timestamp: timestamp)
                    self.refreshTranscriptText()
                }
            }

            let capture = ProcessTapAudioCapture { [weak self] buffer in
                self?.whisper.appendAudio(buffer)
            } onLog: { [weak self] message in
                Task { @MainActor in
                    self?.log(message)
                }
            } onFormat: { [weak self] formatSummary in
                Task { @MainActor in
                    self?.sessionAudioFormatSummary = formatSummary
                }
            } onSampleRate: { [weak self] sampleRate in
                Task { @MainActor in
                    self?.sessionAudioSampleRate = sampleRate
                }
            }
            try capture.start()
            audioCapture = capture
            isRunning = true
            setStatus("Listening to system audio (whisper)...")
        } catch {
            setStatus("Could not start: \(error.localizedDescription)")
            log("Start error: \(error.diagnosticDescription)")
            try? audioCapture?.stop()
            audioCapture = nil
            isRunning = false
        }
    }

    private func beginSession() {
        sessionStartDate = Date()
        sessionEventMessages = []
        sessionAudioFrameCount = 0
        sessionAudioFormatSummary = "unknown"
        sessionAudioSampleRate = nil
        sessionFilesWritten = false
        transcriptAssembler.reset()
        transcript = ""
        lastTranscriptFile = nil
        dailyEventLogFile = nil
        log("Started new capture session.")
    }

    private func currentElapsedTime() -> TimeInterval {
        max(0, Date().timeIntervalSince(sessionStartDate ?? Date()))
    }

    private func refreshTranscriptText() {
        transcript = transcriptAssembler.displayText
    }

    private func writeSessionFilesAfterStop() {
        guard let sessionStartDate else { return }
        guard !sessionFilesWritten else {
            log("Session files already written; skipping duplicate write.")
            return
        }

        sessionFilesWritten = true
        let endDate = Date()

        do {
            let transcriptURL = try writeTranscriptFile(startDate: sessionStartDate, endDate: endDate)
            lastTranscriptFile = transcriptURL
            log("Wrote transcript: \(transcriptURL.path)")
        } catch {
            log("Failed to write transcript: \(error.diagnosticDescription)")
        }

        do {
            let eventLogURL = try appendDailyEventLog(startDate: sessionStartDate, endDate: endDate)
            dailyEventLogFile = eventLogURL
            log("Appended daily event log: \(eventLogURL.path)")
        } catch {
            log("Failed to append daily event log: \(error.diagnosticDescription)")
        }

        self.sessionStartDate = nil
        sessionEventMessages = []
    }

    private func writeTranscriptFile(startDate: Date, endDate: Date) throws -> URL {
        try FileManager.default.createDirectory(at: Self.transcriptsDirectory, withIntermediateDirectories: true)

        let fileName = "MacAudioTranscriber-\(Self.fileDateFormatter.string(from: startDate))-transcript.txt"
        let fileURL = Self.transcriptsDirectory.appendingPathComponent(fileName)
        let duration = endDate.timeIntervalSince(startDate)
        let capturedSeconds: String
        if let sessionAudioSampleRate, sessionAudioSampleRate > 0 {
            capturedSeconds = String(format: "%.2f", Double(sessionAudioFrameCount) / sessionAudioSampleRate)
        } else {
            capturedSeconds = "unknown"
        }

        let contents = """
        MacAudioTranscriber Meeting Transcript
        Started: \(Self.fullDateFormatter.string(from: startDate))
        Stopped: \(Self.fullDateFormatter.string(from: endDate))
        Duration: \(String(format: "%.2f", duration)) seconds
        Audio format: \(sessionAudioFormatSummary)
        Captured frames: \(sessionAudioFrameCount)
        Captured seconds: \(capturedSeconds)

        Transcript:
        \(transcript.isEmpty ? "(none)" : transcript)
        """

        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func appendDailyEventLog(startDate: Date, endDate: Date) throws -> URL {
        try FileManager.default.createDirectory(at: Self.eventLogsDirectory, withIntermediateDirectories: true)

        let fileName = "\(Self.dailyLogDateFormatter.string(from: startDate)).txt"
        let fileURL = Self.eventLogsDirectory.appendingPathComponent(fileName)
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
        let contents = """
        \(fileExists ? "\n" : "MacAudioTranscriber Daily Event Log\nDate: \(Self.dailyDisplayDateFormatter.string(from: startDate))\n")
        --- Session ---
        Started: \(Self.fullDateFormatter.string(from: startDate))
        Stopped: \(Self.fullDateFormatter.string(from: endDate))

        Events:
        \(sessionEventMessages.isEmpty ? "(none)" : sessionEventMessages.joined(separator: "\n"))

        """

        if fileExists {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            if let data = contents.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
            try handle.close()
        } else {
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        return fileURL
    }

    private func setStatus(_ message: String) {
        status = message
        log(message)
    }

    private func log(_ message: String) {
        let timestamp = Self.logTimeFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)"
        logMessages.append(line)
        if sessionStartDate != nil {
            sessionEventMessages.append(line)
        }
        if logMessages.count > 200 {
            logMessages.removeFirst(logMessages.count - 200)
        }
    }

    private static let modelPath: String = {
        if let bundlePath = Bundle.main.path(forResource: "ggml-small.en", ofType: "bin") {
            return bundlePath
        }
        let devPath = FileManager.default.currentDirectoryPath + "/models/ggml-small.en.bin"
        return devPath
    }()

    private static let logTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents", isDirectory: true)
        .appendingPathComponent("MacAudioTranscriber Logs", isDirectory: true)

    private static let transcriptsDirectory = logsDirectory
        .appendingPathComponent("Transcripts", isDirectory: true)

    private static let eventLogsDirectory = logsDirectory
        .appendingPathComponent("Event Logs", isDirectory: true)

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()

    private static let dailyLogDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    private static let dailyDisplayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ"
        return formatter
    }()
}

private final class ProcessTapAudioCapture {
    private let onBuffer: @Sendable (AVAudioPCMBuffer) -> Void
    private let onLog: @Sendable (String) -> Void
    private let onFormat: @Sendable (String) -> Void
    private let onSampleRate: @Sendable (Double) -> Void
    private let ioQueue = DispatchQueue(label: "ProcessTapAudioCapture.io")

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var audioFormat: AVAudioFormat?

    init(
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onLog: @escaping @Sendable (String) -> Void,
        onFormat: @escaping @Sendable (String) -> Void,
        onSampleRate: @escaping @Sendable (Double) -> Void
    ) {
        self.onBuffer = onBuffer
        self.onLog = onLog
        self.onFormat = onFormat
        self.onSampleRate = onSampleRate
    }

    func start() throws {
        guard #available(macOS 14.2, *) else {
            throw TranscriberError.unsupportedOS
        }

        let excludedProcesses = currentProcessObjectID().map { [$0] } ?? []
        let tapDescription = CATapDescription(monoGlobalTapButExcludeProcesses: excludedProcesses)
        tapDescription.name = "MacAudioTranscriber Process Tap"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .unmuted

        onLog("Creating Core Audio process tap. Excluded process IDs: \(excludedProcesses).")
        try check(AudioHardwareCreateProcessTap(tapDescription, &tapID), "create process tap")
        onLog("Created process tap: \(tapID).")

        do {
            let tapUID = try stringProperty(objectID: tapID, selector: kAudioTapPropertyUID)
            var streamDescription = try audioStreamBasicDescription(objectID: tapID, selector: kAudioTapPropertyFormat)
            onLog("Tap UID: \(tapUID)")
            onLog("Tap format: \(streamDescription.debugSummary)")
            onFormat(streamDescription.debugSummary)
            onSampleRate(streamDescription.mSampleRate)

            guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
                throw TranscriberError.unsupportedFormat
            }
            audioFormat = format

            let aggregateDescription: [String: Any] = [
                kAudioAggregateDeviceNameKey: "MacAudioTranscriber Aggregate",
                kAudioAggregateDeviceUIDKey: "local.macaudio.transcriber.aggregate.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [
                    [
                        kAudioSubTapUIDKey: tapUID,
                        kAudioSubTapDriftCompensationKey: true,
                        kAudioSubTapDriftCompensationQualityKey: kAudioAggregateDriftCompensationMaxQuality
                    ]
                ]
            ]

            try check(
                AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateDeviceID),
                "create aggregate device"
            )
            onLog("Created private aggregate device: \(aggregateDeviceID).")

            let ioBlock: AudioDeviceIOBlock = { [weak self] _, inputData, _, _, _ in
                self?.handle(inputData: inputData)
            }

            try check(
                AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateDeviceID, ioQueue, ioBlock),
                "create IOProc"
            )
            onLog("Created aggregate device IOProc.")

            try check(AudioDeviceStart(aggregateDeviceID, ioProcID), "start aggregate device")
            onLog("Started aggregate device.")
        } catch {
            onLog("Core Audio setup failed: \(error.diagnosticDescription)")
            try? stop()
            throw error
        }
    }

    func stop() throws {
        var firstError: Error?

        if aggregateDeviceID != kAudioObjectUnknown {
            let stopStatus = AudioDeviceStop(aggregateDeviceID, ioProcID)
            if stopStatus != noErr {
                firstError = TranscriberError.coreAudio("stop aggregate device", stopStatus)
            } else {
                onLog("Stopped aggregate device.")
            }

            if let ioProcID {
                let destroyIOStatus = AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
                if firstError == nil, destroyIOStatus != noErr {
                    firstError = TranscriberError.coreAudio("destroy IOProc", destroyIOStatus)
                } else if destroyIOStatus == noErr {
                    onLog("Destroyed aggregate device IOProc.")
                }
                self.ioProcID = nil
            }

            let destroyAggregateStatus = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            if firstError == nil, destroyAggregateStatus != noErr {
                firstError = TranscriberError.coreAudio("destroy aggregate device", destroyAggregateStatus)
            } else if destroyAggregateStatus == noErr {
                onLog("Destroyed aggregate device.")
            }
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        }

        if tapID != kAudioObjectUnknown {
            let destroyTapStatus = AudioHardwareDestroyProcessTap(tapID)
            if firstError == nil, destroyTapStatus != noErr {
                firstError = TranscriberError.coreAudio("destroy process tap", destroyTapStatus)
            } else if destroyTapStatus == noErr {
                onLog("Destroyed process tap.")
            }
            tapID = AudioObjectID(kAudioObjectUnknown)
        }

        audioFormat = nil

        if let firstError {
            throw firstError
        }
    }

    private func handle(inputData: UnsafePointer<AudioBufferList>?) {
        guard let inputData, let audioFormat else { return }

        let sourceBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        guard let firstSource = sourceBuffers.first,
              firstSource.mData != nil,
              firstSource.mDataByteSize > 0 else {
            return
        }

        let bytesPerFrame = audioFormat.streamDescription.pointee.mBytesPerFrame
        guard bytesPerFrame > 0 else { return }

        let frameCount = AVAudioFrameCount(firstSource.mDataByteSize / bytesPerFrame)
        guard frameCount > 0,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
            return
        }

        pcmBuffer.frameLength = frameCount
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)
        let bufferCount = min(sourceBuffers.count, destinationBuffers.count)

        for index in 0..<bufferCount {
            guard let sourceData = sourceBuffers[index].mData,
                  let destinationData = destinationBuffers[index].mData else {
                continue
            }

            let byteCount = min(sourceBuffers[index].mDataByteSize, destinationBuffers[index].mDataByteSize)
            memcpy(destinationData, sourceData, Int(byteCount))
            destinationBuffers[index].mDataByteSize = byteCount
        }

        onBuffer(pcmBuffer)
    }

    private func currentProcessObjectID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid = getpid()
        var processID = AudioObjectID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let qualifierSize = UInt32(MemoryLayout<pid_t>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            qualifierSize,
            &pid,
            &dataSize,
            &processID
        )

        guard status == noErr, processID != kAudioObjectUnknown else {
            return nil
        }

        return processID
    }

    private func stringProperty(objectID: AudioObjectID, selector: AudioObjectPropertySelector) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        try check(
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value),
            "read Core Audio string property"
        )

        guard let value else {
            throw TranscriberError.missingProperty
        }

        return value.takeRetainedValue() as String
    }

    private func audioStreamBasicDescription(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = AudioStreamBasicDescription()
        var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)

        try check(
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value),
            "read Core Audio property"
        )

        return value
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else {
            throw TranscriberError.coreAudio(operation, status)
        }
    }

    deinit {
        try? stop()
    }
}

private enum TranscriberError: LocalizedError {
    case unsupportedOS
    case unsupportedFormat
    case missingProperty
    case coreAudio(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            "Core Audio process taps require macOS 14.2 or later."
        case .unsupportedFormat:
            "The process tap produced an audio format that cannot be consumed."
        case .missingProperty:
            "Core Audio did not return a required property."
        case .coreAudio(let operation, let status):
            "Core Audio failed to \(operation) (\(status.diagnosticDescription))."
        }
    }
}

private extension Error {
    var diagnosticDescription: String {
        let nsError = self as NSError
        var parts = ["\(localizedDescription)"]
        parts.append("domain=\(nsError.domain)")
        parts.append("code=\(nsError.code)")

        if let reason = nsError.localizedFailureReason {
            parts.append("reason=\(reason)")
        }

        if let recovery = nsError.localizedRecoverySuggestion {
            parts.append("recovery=\(recovery)")
        }

        return parts.joined(separator: "; ")
    }
}

private extension OSStatus {
    var diagnosticDescription: String {
        let code = Int32(self)
        let rawValue = UInt32(bitPattern: code)
        let bytes = [
            UInt8((rawValue >> 24) & 0xff),
            UInt8((rawValue >> 16) & 0xff),
            UInt8((rawValue >> 8) & 0xff),
            UInt8(rawValue & 0xff)
        ]

        let fourCC: String
        if bytes.allSatisfy({ $0 >= 32 && $0 <= 126 }) {
            fourCC = String(bytes: bytes, encoding: .macOSRoman) ?? ""
        } else {
            fourCC = ""
        }

        if fourCC.isEmpty {
            return "\(self)"
        }

        return "\(self) ('\(fourCC)')"
    }
}

private extension AudioStreamBasicDescription {
    var debugSummary: String {
        [
            "sampleRate=\(mSampleRate)",
            "formatID=\(mFormatID.osTypeString)",
            "formatFlags=\(mFormatFlags)",
            "bytesPerPacket=\(mBytesPerPacket)",
            "framesPerPacket=\(mFramesPerPacket)",
            "bytesPerFrame=\(mBytesPerFrame)",
            "channels=\(mChannelsPerFrame)",
            "bitsPerChannel=\(mBitsPerChannel)"
        ].joined(separator: ", ")
    }
}

private extension AudioFormatID {
    var osTypeString: String {
        let bytes = [
            UInt8((self >> 24) & 0xff),
            UInt8((self >> 16) & 0xff),
            UInt8((self >> 8) & 0xff),
            UInt8(self & 0xff)
        ]

        guard bytes.allSatisfy({ $0 >= 32 && $0 <= 126 }),
              let string = String(bytes: bytes, encoding: .macOSRoman) else {
            return "\(self)"
        }

        return "'\(string)'"
    }
}
