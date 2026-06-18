import Foundation

struct TranscriptAssembler {
    private(set) var committedLines: [String] = []
    private(set) var liveText = ""
    private var liveTimestamp: TimeInterval = 0

    var displayText: String {
        var parts = committedLines
        if !liveText.isEmpty {
            parts.append("\(Self.formatTimestamp(liveTimestamp)): \(liveText)")
        }
        return parts.joined(separator: "\n\n")
    }

    var fullTranscript: String {
        committedLines.joined(separator: "\n\n")
    }

    mutating func reset() {
        committedLines = []
        liveText = ""
        liveTimestamp = 0
    }

    mutating func update(text: String, isFinal: Bool, timestamp: TimeInterval) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if isFinal {
            committedLines.append("\(Self.formatTimestamp(timestamp)): \(trimmed)")
            liveText = ""
        } else {
            liveText = trimmed
            liveTimestamp = timestamp
        }
    }

    mutating func commitLive() {
        guard !liveText.isEmpty else { return }
        committedLines.append("\(Self.formatTimestamp(liveTimestamp)): \(liveText)")
        liveText = ""
    }

    private static func formatTimestamp(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds.rounded(.down))
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
