import Foundation
import AVFoundation

final class WhisperTranscriber: @unchecked Sendable {
    private var ctx: OpaquePointer?
    private let processingQueue = DispatchQueue(label: "WhisperTranscriber.processing")
    private var ringBuffer: [Float] = []
    private let lock = NSLock()
    private var isProcessing = false
    private var onResult: ((String, Bool, TimeInterval) -> Void)?
    private var onLog: ((String) -> Void)?
    private var stopped = false
    private var samplesProcessed: Int = 0

    private let sampleRate: Int = 16000
    private let chunkSeconds: Int = 5
    private var chunkSamples: Int { chunkSeconds * sampleRate }

    func loadModel(at path: String, log: @escaping (String) -> Void) -> Bool {
        self.onLog = log
        var params = whisper_context_default_params()
        params.use_gpu = true
        log("Loading whisper model from: \(path)")
        ctx = whisper_init_from_file_with_params(path, params)
        if ctx != nil {
            log("Whisper model loaded successfully.")
            return true
        } else {
            log("Failed to load whisper model.")
            return false
        }
    }

    func start(onResult: @escaping (String, Bool, TimeInterval) -> Void) {
        lock.lock()
        self.onResult = onResult
        self.stopped = false
        self.samplesProcessed = 0
        ringBuffer.removeAll()
        lock.unlock()
    }

    func appendAudio(_ buffer: AVAudioPCMBuffer) {
        guard let floatData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        let sourceSampleRate = buffer.format.sampleRate
        let channelCount = Int(buffer.format.channelCount)

        var mono = [Float](repeating: 0, count: frameCount)
        if channelCount == 1 {
            memcpy(&mono, floatData[0], frameCount * MemoryLayout<Float>.size)
        } else {
            for i in 0..<frameCount {
                var sum: Float = 0
                for ch in 0..<channelCount {
                    sum += floatData[ch][i]
                }
                mono[i] = sum / Float(channelCount)
            }
        }

        let resampled: [Float]
        if abs(sourceSampleRate - 16000.0) < 1.0 {
            resampled = mono
        } else {
            let ratio = 16000.0 / sourceSampleRate
            let outputCount = Int(Double(frameCount) * ratio)
            var output = [Float](repeating: 0, count: outputCount)
            for i in 0..<outputCount {
                let srcIdx = Double(i) / ratio
                let idx0 = Int(srcIdx)
                let frac = Float(srcIdx - Double(idx0))
                let idx1 = min(idx0 + 1, frameCount - 1)
                output[i] = mono[idx0] * (1.0 - frac) + mono[idx1] * frac
            }
            resampled = output
        }

        lock.lock()
        ringBuffer.append(contentsOf: resampled)
        let bufferCount = ringBuffer.count
        let shouldProcess = bufferCount >= chunkSamples && !isProcessing && !stopped
        lock.unlock()

        if shouldProcess {
            scheduleProcessing()
        }
    }

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()

        processingQueue.sync {
            self.drainAllRemaining()
        }
    }

    func unloadModel() {
        if let ctx {
            whisper_free(ctx)
        }
        ctx = nil
        onResult = nil
        onLog = nil
    }

    private func scheduleProcessing() {
        lock.lock()
        guard !isProcessing, !stopped else {
            lock.unlock()
            return
        }
        isProcessing = true
        lock.unlock()

        processingQueue.async { [weak self] in
            self?.processNextChunk()
        }
    }

    private func processNextChunk() {
        lock.lock()
        guard ringBuffer.count >= chunkSamples else {
            isProcessing = false
            lock.unlock()
            return
        }

        let chunk = Array(ringBuffer.prefix(chunkSamples))
        let chunkTimestamp = TimeInterval(samplesProcessed) / TimeInterval(sampleRate)
        ringBuffer.removeFirst(chunkSamples)
        samplesProcessed += chunkSamples
        let morePending = ringBuffer.count >= chunkSamples
        let bufferedSeconds = Double(ringBuffer.count) / Double(sampleRate)
        lock.unlock()

        let rms = Self.rmsEnergy(chunk)
        if rms < 0.002 {
            onLog?(String(format: "Chunk @%.0fs: silent (rms=%.5f), skipped", chunkTimestamp, rms))
        } else {
            let startTime = CFAbsoluteTimeGetCurrent()
            let text = transcribe(chunk)
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            onLog?(String(format: "Chunk @%.0fs: %.1fs to transcribe, rms=%.4f, %.1fs buffered", chunkTimestamp, elapsed, rms, bufferedSeconds))

            if !text.isEmpty, !Self.isHallucination(text) {
                onResult?(text, true, chunkTimestamp)
            }
        }

        if morePending {
            processNextChunk()
        } else {
            lock.lock()
            isProcessing = false
            let shouldContinue = ringBuffer.count >= chunkSamples && !stopped
            lock.unlock()
            if shouldContinue {
                scheduleProcessing()
            }
        }
    }

    private func drainAllRemaining() {
        lock.lock()
        let totalRemaining = ringBuffer.count
        lock.unlock()

        onLog?("Draining remaining audio: \(Double(totalRemaining) / Double(sampleRate))s")

        while true {
            lock.lock()
            guard ringBuffer.count >= sampleRate else {
                ringBuffer.removeAll()
                lock.unlock()
                break
            }

            let takeCount = min(ringBuffer.count, chunkSamples)
            let chunk = Array(ringBuffer.prefix(takeCount))
            let chunkTimestamp = TimeInterval(samplesProcessed) / TimeInterval(sampleRate)
            ringBuffer.removeFirst(takeCount)
            samplesProcessed += takeCount
            lock.unlock()

            let rms = Self.rmsEnergy(chunk)
            guard rms >= 0.002 else { continue }
            let text = transcribe(chunk)
            if !text.isEmpty, !Self.isHallucination(text) {
                onResult?(text, true, chunkTimestamp)
            }
        }
    }

    private func transcribe(_ samples: [Float]) -> String {
        guard let ctx else { return "" }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(max(4, ProcessInfo.processInfo.activeProcessorCount - 2))
        params.no_timestamps = true
        params.single_segment = false
        params.print_special = false
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.no_context = true
        let langStr = strdup("en")
        params.language = UnsafePointer(langStr)
        params.suppress_blank = true
        params.suppress_nst = true

        let result = samples.withUnsafeBufferPointer { ptr -> String in
            guard let baseAddress = ptr.baseAddress else { return "" }
            let status = whisper_full(ctx, params, baseAddress, Int32(samples.count))
            guard status == 0 else {
                onLog?("Whisper inference failed with status \(status)")
                return ""
            }

            let segmentCount = whisper_full_n_segments(ctx)
            var texts: [String] = []
            for i in 0..<segmentCount {
                if let cStr = whisper_full_get_segment_text(ctx, i) {
                    let segment = String(cString: cStr).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !segment.isEmpty {
                        texts.append(segment)
                    }
                }
            }
            return texts.joined(separator: " ")
        }

        free(langStr)
        return result
    }

    private static func rmsEnergy(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sumSquares: Float = 0
        for s in samples {
            sumSquares += s * s
        }
        return sqrt(sumSquares / Float(samples.count))
    }

    private static let hallucinationPatterns: Set<String> = [
        "you",
        "thank you",
        "thanks for watching",
        "thanks for listening",
        "bye",
        "goodbye",
        "thank you for watching",
        "thanks",
        "the end",
        "subtitles by",
    ]

    private static func isHallucination(_ text: String) -> Bool {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return hallucinationPatterns.contains(normalized)
    }

    deinit {
        unloadModel()
    }
}
