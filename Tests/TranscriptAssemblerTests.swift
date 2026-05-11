import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    guard actual == expected else {
        throw TestFailure(description: "\(message)\nExpected: \(expected)\nActual:   \(actual)")
    }
}

private func expect(_ condition: Bool, _ message: String) throws {
    guard condition else {
        throw TestFailure(description: message)
    }
}

private func feed(
    _ assembler: inout TranscriptAssembler,
    _ text: String,
    isFinal: Bool = false,
    at time: TimeInterval
) {
    assembler.update(
        text: text,
        isFinal: isFinal,
        timestampCandidate: time,
        endTimestamp: time,
        speakerNumber: { _, _ in 1 }
    )
}

private func committedTexts(_ assembler: TranscriptAssembler) -> [String] {
    assembler.committedLines.map(\.text)
}

private func testPartialLadderDoesNotDuplicate() throws {
    var assembler = TranscriptAssembler()

    feed(&assembler, "Well, the", at: 0)
    try expectEqual(assembler.committedDisplayText, "", "Unfinished partials should not be displayed as committed transcript.")

    feed(&assembler, "Well, the wealthy are living", at: 1)
    try expectEqual(assembler.committedDisplayText, "", "Expanding partials should stay hidden until committed.")

    feed(&assembler, "Well, the wealthy are living their best lives.", at: 2)

    try expectEqual(committedTexts(assembler), ["Well, the wealthy are living their best lives."], "Completed sentence should commit once.")
    try expectEqual(assembler.committedDisplayText, "00:00: Speaker 1: Well, the wealthy are living their best lives.", "Committed display should show only finalized sentence lines.")
    try expectEqual(assembler.liveLine?.text, nil, "No live line should remain after a completed sentence.")
}

private func testCompletedSentencesStayPermanentWhenLaterHypothesisChangesThem() throws {
    var assembler = TranscriptAssembler()

    feed(&assembler, "Hi. Fine. Let's have a meeting", at: 0)
    try expectEqual(committedTexts(assembler), ["Hi.", "Fine."], "Two complete sentences should become permanent immediately.")
    try expectEqual(assembler.liveLine?.text, "Let's have a meeting", "Trailing incomplete sentence should stay live.")

    feed(&assembler, "Hello. Fine. Let's have a meeting today", at: 1)
    try expectEqual(committedTexts(assembler), ["Hi.", "Fine."], "Autocorrect should not rewrite permanent sentences.")
    try expectEqual(assembler.liveLine?.text, "Let's have a meeting today", "Only the unfinished tail should update.")
}

private func testShorterLaterHypothesisDoesNotDeleteCommittedSentences() throws {
    var assembler = TranscriptAssembler()

    feed(&assembler, "One. Two. Three. Four is still live", at: 0)
    try expectEqual(committedTexts(assembler), ["One.", "Two.", "Three."], "First three sentences should be committed.")

    feed(&assembler, "One. Two. Four changed", at: 1)
    try expectEqual(committedTexts(assembler), ["One.", "Two.", "Three."], "A shorter revised hypothesis must not delete permanent text.")
    try expectEqual(assembler.liveLine?.text, "changed", "The remaining live tail should be bounded after committed words.")
}

private func testLiveSentenceAutocorrectsUntilCommitted() throws {
    var assembler = TranscriptAssembler()

    feed(&assembler, "I just really like cockies now", at: 0)
    feed(&assembler, "I just really like cookies now", at: 1)
    feed(&assembler, "I just really like cookies now.", at: 2)

    try expectEqual(committedTexts(assembler), ["I just really like cookies now."], "Current unfinished sentence should accept autocorrect before commit.")
}

private func testPunctuationChangeInCommittedPrefixDoesNotLeakPunctuation() throws {
    var assembler = TranscriptAssembler()

    feed(&assembler, "Hello world.", at: 0)
    feed(&assembler, "Hello, world. How are you?", at: 1)

    try expectEqual(
        committedTexts(assembler),
        ["Hello world.", "How are you?"],
        "Committed prefix with punctuation changes should be stripped cleanly. Live: \(assembler.liveLine?.text ?? "nil")"
    )
    try expectEqual(assembler.liveLine?.text, nil, "Both sentences should be committed.")
}

private func testSingleUpdateWithMultipleSentencesAssignsMonotonicTimestampsWithoutCallback() throws {
    var assembler = TranscriptAssembler()

    feed(&assembler, "First sentence.", at: 0)
    feed(&assembler, "First sentence. Second sentence. Third is live", at: 0.2)

    try expectEqual(committedTexts(assembler), ["First sentence.", "Second sentence."], "Second complete sentence should commit.")
    try expect(assembler.committedLines[1].timestamp >= assembler.committedLines[0].endTimestamp, "Committed timestamps should not move backward.")
    try expect((assembler.liveLine?.timestamp ?? -1) >= assembler.committedLines[1].endTimestamp, "Live timestamp should not move backward after a same-update commit.")
}

private func testSpeakerCallbackReceivesPreviousEndWithoutReadingAssembler() throws {
    var assembler = TranscriptAssembler()
    var previousEndValues: [TimeInterval] = []

    assembler.update(
        text: "First. Second.",
        isFinal: false,
        timestampCandidate: 0,
        endTimestamp: 2,
        speakerNumber: { _, previousEnd in
            previousEndValues.append(previousEnd)
            return 1
        }
    )

    try expectEqual(previousEndValues, [0, 2], "Speaker callback should receive previous committed end timestamp.")
}

private func testPauseCommittedLiveChunkIsStrippedFromLaterPartials() throws {
    var assembler = TranscriptAssembler()

    feed(&assembler, "This has no punctuation yet", at: 0)
    assembler.commitLiveLine(speakerNumber: { _, _ in 1 })
    feed(&assembler, "This has no punctuation yet and now continues.", at: 2)

    try expectEqual(
        committedTexts(assembler),
        ["This has no punctuation yet", "and now continues."],
        "A pause-committed chunk should become part of the stripped committed prefix."
    )
}

private func runTests() throws {
    try testPartialLadderDoesNotDuplicate()
    try testCompletedSentencesStayPermanentWhenLaterHypothesisChangesThem()
    try testShorterLaterHypothesisDoesNotDeleteCommittedSentences()
    try testLiveSentenceAutocorrectsUntilCommitted()
    try testPunctuationChangeInCommittedPrefixDoesNotLeakPunctuation()
    try testSingleUpdateWithMultipleSentencesAssignsMonotonicTimestampsWithoutCallback()
    try testSpeakerCallbackReceivesPreviousEndWithoutReadingAssembler()
    try testPauseCommittedLiveChunkIsStrippedFromLaterPartials()
}

@main
private enum TranscriptAssemblerTestRunner {
    static func main() {
        do {
            try runTests()
            print("TranscriptAssemblerTests: passed")
        } catch {
            print("TranscriptAssemblerTests: failed")
            print(error)
            exit(1)
        }
    }
}
