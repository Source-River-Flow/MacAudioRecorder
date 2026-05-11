import Foundation

struct TranscriptLine: Equatable {
    let timestamp: TimeInterval
    let endTimestamp: TimeInterval
    let text: String
    let speakerNumber: Int

    var displayText: String {
        "\(Self.timestampString(for: timestamp)): Speaker \(speakerNumber): \(text)"
    }

    var normalizedText: String {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    init(timestamp: TimeInterval, endTimestamp: TimeInterval, text: String, speakerNumber: Int = 1) {
        self.timestamp = timestamp
        self.endTimestamp = endTimestamp
        self.text = text
        self.speakerNumber = speakerNumber
    }

    func withSpeakerNumber(_ speakerNumber: Int) -> TranscriptLine {
        TranscriptLine(timestamp: timestamp, endTimestamp: endTimestamp, text: text, speakerNumber: speakerNumber)
    }

    static func timestampString(for timestamp: TimeInterval) -> String {
        let displayTimestamp = TimeInterval(Int(timestamp.rounded(.down)))
        return timestampFormatter.string(from: displayTimestamp) ?? "00:00"
    }

    private static let timestampFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter
    }()
}

struct TranscriptAssembler {
    private(set) var committedLines: [TranscriptLine] = []
    private(set) var liveLine: TranscriptLine?
    private(set) var lastCommittedEndTimestamp: TimeInterval = 0

    private var liveLineStartTimestamp: TimeInterval?
    private var recognitionCommittedPrefix = ""

    var hasCommittedLines: Bool {
        !committedLines.isEmpty
    }

    var displayText: String {
        var lines = committedLines
        if let liveLine {
            lines.append(liveLine)
        }
        return lines.map(\.displayText).joined(separator: "\n\n")
    }

    var committedDisplayText: String {
        committedLines.map(\.displayText).joined(separator: "\n\n")
    }

    mutating func reset() {
        committedLines = []
        liveLine = nil
        lastCommittedEndTimestamp = 0
        liveLineStartTimestamp = nil
        recognitionCommittedPrefix = ""
    }

    mutating func resetRecognitionWindow() {
        recognitionCommittedPrefix = ""
    }

    mutating func update(
        text: String,
        isFinal: Bool,
        timestampCandidate: TimeInterval,
        endTimestamp: TimeInterval,
        speakerNumber: (TranscriptLine, TimeInterval) -> Int
    ) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let uncommittedText = uncommittedTranscriptText(from: text)
        let sentenceSplit = uncommittedText.splitCompletedSentences(commitTrailingFragment: isFinal)
        var committedAnySentence = false

        for sentence in sentenceSplit.completedSentences where !sentence.isEmpty {
            let timestamp = liveLineStartTimestamp ?? nextLineTimestamp(candidate: timestampCandidate)
            let line = TranscriptLine(timestamp: timestamp, endTimestamp: endTimestamp, text: sentence)
            appendCommittedLine(line, speakerNumber: speakerNumber)
            recognitionCommittedPrefix = (recognitionCommittedPrefix + " " + sentence).normalizedSpacing
            liveLineStartTimestamp = nil
            committedAnySentence = true
        }

        let liveText = sentenceSplit.remainder.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !liveText.isEmpty else {
            liveLine = nil
            liveLineStartTimestamp = nil
            return
        }

        if committedAnySentence || liveLine == nil {
            liveLineStartTimestamp = nextLineTimestamp(candidate: timestampCandidate)
        }

        liveLine = TranscriptLine(
            timestamp: liveLineStartTimestamp ?? nextLineTimestamp(candidate: timestampCandidate),
            endTimestamp: endTimestamp,
            text: liveText,
            speakerNumber: committedLines.last?.speakerNumber ?? 1
        )
    }

    mutating func commitLiveLine(speakerNumber: (TranscriptLine, TimeInterval) -> Int) {
        guard let liveLine else { return }
        if appendCommittedLine(liveLine, speakerNumber: speakerNumber) {
            recognitionCommittedPrefix = (recognitionCommittedPrefix + " " + liveLine.text).normalizedSpacing
        }
        self.liveLine = nil
        liveLineStartTimestamp = nil
    }

    @discardableResult
    private mutating func appendCommittedLine(
        _ line: TranscriptLine,
        speakerNumber: (TranscriptLine, TimeInterval) -> Int
    ) -> Bool {
        guard !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        let previousEndTimestamp = lastCommittedEndTimestamp
        let speakerLine = line.withSpeakerNumber(speakerNumber(line, previousEndTimestamp))
        let isDuplicateLastLine = committedLines.last?.normalizedText == speakerLine.normalizedText &&
            committedLines.last?.speakerNumber == speakerLine.speakerNumber

        if !isDuplicateLastLine {
            committedLines.append(speakerLine)
            lastCommittedEndTimestamp = max(lastCommittedEndTimestamp, speakerLine.endTimestamp)
            return true
        }

        return false
    }

    private func nextLineTimestamp(candidate: TimeInterval) -> TimeInterval {
        if committedLines.isEmpty {
            return 0
        }

        return max(candidate, lastCommittedEndTimestamp)
    }

    private func uncommittedTranscriptText(from text: String) -> String {
        let normalizedText = text.normalizedSpacing
        let normalizedPrefix = recognitionCommittedPrefix.normalizedSpacing

        guard !normalizedPrefix.isEmpty else {
            return normalizedText
        }

        if normalizedText.hasPrefix(normalizedPrefix) {
            return String(normalizedText.dropFirst(normalizedPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let committedWords = normalizedPrefix.normalizedWordCount
        return normalizedText.suffixAfterDroppingFirstNormalizedWords(committedWords)
    }
}

private struct SentenceSplit {
    let completedSentences: [String]
    let remainder: String
}

private extension String {
    func splitCompletedSentences(commitTrailingFragment: Bool) -> SentenceSplit {
        let text = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return SentenceSplit(completedSentences: [], remainder: "")
        }

        var completedSentences: [String] = []
        var sentenceStart = text.startIndex
        var scanIndex = text.startIndex

        while scanIndex < text.endIndex {
            let character = text[scanIndex]

            if character.isSentenceTerminator {
                let sentenceEnd = text.index(after: scanIndex)
                let sentence = String(text[sentenceStart..<sentenceEnd]).trimmingCharacters(in: .whitespacesAndNewlines)

                if !sentence.isEmpty {
                    completedSentences.append(sentence)
                }

                sentenceStart = sentenceEnd
                while sentenceStart < text.endIndex, text[sentenceStart].isWhitespace {
                    sentenceStart = text.index(after: sentenceStart)
                }
                scanIndex = sentenceStart
                continue
            }

            scanIndex = text.index(after: scanIndex)
        }

        let trailingText = String(text[sentenceStart..<text.endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        if commitTrailingFragment, !trailingText.isEmpty {
            completedSentences.append(trailingText)
            return SentenceSplit(completedSentences: completedSentences, remainder: "")
        }

        return SentenceSplit(completedSentences: completedSentences, remainder: trailingText)
    }

    var normalizedSpacing: String {
        split { $0.isWhitespace }.joined(separator: " ")
    }

    var normalizedWordCount: Int {
        lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .count
    }

    func suffixAfterDroppingFirstNormalizedWords(_ count: Int) -> String {
        guard count > 0 else {
            return trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var wordsSeen = 0
        var suffixStart = startIndex
        var index = startIndex

        while index < endIndex {
            while index < endIndex, !self[index].isLetter && !self[index].isNumber {
                index = self.index(after: index)
            }

            guard index < endIndex else { break }

            while index < endIndex, self[index].isLetter || self[index].isNumber {
                index = self.index(after: index)
            }

            wordsSeen += 1
            suffixStart = index

            if wordsSeen >= count {
                break
            }
        }

        guard wordsSeen >= count else {
            return ""
        }

        return String(self[suffixStart..<endIndex]).trimmingLeadingSentenceBoundary()
    }

    func trimmingLeadingSentenceBoundary() -> String {
        var start = startIndex

        while start < endIndex {
            let scalar = self[start].unicodeScalars.first
            if self[start].isWhitespace || scalar.map(CharacterSet.sentenceLeadingPunctuation.contains) == true {
                start = index(after: start)
            } else {
                break
            }
        }

        return String(self[start..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Character {
    var isSentenceTerminator: Bool {
        self == "." || self == "?" || self == "!"
    }
}

private extension CharacterSet {
    static let sentenceLeadingPunctuation = CharacterSet(charactersIn: ".?!,:;")
}
