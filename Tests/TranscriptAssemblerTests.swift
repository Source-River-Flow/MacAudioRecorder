import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    guard actual == expected else {
        throw TestFailure(description: "\(message)\nExpected: \(expected)\nActual:   \(actual)")
    }
}

private func testPartialUpdatesShowAsLiveText() throws {
    var assembler = TranscriptAssembler()

    assembler.update(text: "Hello world", isFinal: false, timestamp: 0)
    try expectEqual(assembler.liveText, "Hello world", "Partial update should set liveText.")
    try expectEqual(assembler.committedLines.count, 0, "Partial update should not commit.")
    try expectEqual(assembler.displayText, "00:00: Hello world", "Display should show timestamped live text.")
}

private func testFinalUpdateCommitsWithTimestamp() throws {
    var assembler = TranscriptAssembler()

    assembler.update(text: "Hello world", isFinal: true, timestamp: 5)
    try expectEqual(assembler.committedLines, ["00:05: Hello world"], "Final update should commit with timestamp.")
    try expectEqual(assembler.liveText, "", "Final update should clear live text.")
}

private func testMultipleFinalUpdatesAppendAsLines() throws {
    var assembler = TranscriptAssembler()

    assembler.update(text: "First chunk.", isFinal: true, timestamp: 0)
    assembler.update(text: "Second chunk.", isFinal: true, timestamp: 5)
    try expectEqual(assembler.committedLines.count, 2, "Each final should add a line.")
    try expectEqual(assembler.displayText, "00:00: First chunk.\n\n00:05: Second chunk.", "Lines should be separated by double newline.")
}

private func testCommitLiveMovesToCommittedLines() throws {
    var assembler = TranscriptAssembler()

    assembler.update(text: "In progress", isFinal: false, timestamp: 10)
    assembler.commitLive()
    try expectEqual(assembler.committedLines, ["00:10: In progress"], "Commit should move live to committed lines.")
    try expectEqual(assembler.liveText, "", "Commit should clear live text.")
}

private func testPartialOverwritesPreviousPartial() throws {
    var assembler = TranscriptAssembler()

    assembler.update(text: "Hello", isFinal: false, timestamp: 0)
    assembler.update(text: "Hello world", isFinal: false, timestamp: 0)
    try expectEqual(assembler.liveText, "Hello world", "Later partial should replace earlier one.")
    try expectEqual(assembler.committedLines.count, 0, "Committed should be untouched by partials.")
}

private func testDisplayTextCombinesCommittedAndLive() throws {
    var assembler = TranscriptAssembler()

    assembler.update(text: "Done.", isFinal: true, timestamp: 0)
    assembler.update(text: "Still going", isFinal: false, timestamp: 5)
    try expectEqual(assembler.displayText, "00:00: Done.\n\n00:05: Still going", "Display should combine committed and live text.")
}

private func testResetClearsEverything() throws {
    var assembler = TranscriptAssembler()

    assembler.update(text: "Some text.", isFinal: true, timestamp: 0)
    assembler.update(text: "Live", isFinal: false, timestamp: 5)
    assembler.reset()

    try expectEqual(assembler.committedLines.count, 0, "Reset should clear committed lines.")
    try expectEqual(assembler.liveText, "", "Reset should clear live text.")
    try expectEqual(assembler.displayText, "", "Reset should clear display text.")
}

private func testEmptyTextIsIgnored() throws {
    var assembler = TranscriptAssembler()

    assembler.update(text: "", isFinal: true, timestamp: 0)
    try expectEqual(assembler.committedLines.count, 0, "Empty text should be ignored.")

    assembler.update(text: "   ", isFinal: true, timestamp: 0)
    try expectEqual(assembler.committedLines.count, 0, "Whitespace-only text should be ignored.")
}

private func testTimestampFormatting() throws {
    var assembler = TranscriptAssembler()

    assembler.update(text: "At zero.", isFinal: true, timestamp: 0)
    assembler.update(text: "At one minute.", isFinal: true, timestamp: 60)
    assembler.update(text: "At ten minutes five seconds.", isFinal: true, timestamp: 605)

    try expectEqual(assembler.committedLines[0], "00:00: At zero.", "Zero should format as 00:00.")
    try expectEqual(assembler.committedLines[1], "01:00: At one minute.", "60s should format as 01:00.")
    try expectEqual(assembler.committedLines[2], "10:05: At ten minutes five seconds.", "605s should format as 10:05.")
}

private func testOldTextNeverErased() throws {
    var assembler = TranscriptAssembler()

    assembler.update(text: "Line one.", isFinal: true, timestamp: 0)
    assembler.update(text: "Line two.", isFinal: true, timestamp: 4)
    assembler.update(text: "Line three.", isFinal: true, timestamp: 8)

    let display = assembler.displayText
    try expectEqual(display.contains("Line one."), true, "Old lines must remain in display.")
    try expectEqual(display.contains("Line two."), true, "Old lines must remain in display.")
    try expectEqual(display.contains("Line three."), true, "Latest line must appear in display.")
    try expectEqual(assembler.committedLines.count, 3, "All three lines should be committed.")
}

private func runTests() throws {
    try testPartialUpdatesShowAsLiveText()
    try testFinalUpdateCommitsWithTimestamp()
    try testMultipleFinalUpdatesAppendAsLines()
    try testCommitLiveMovesToCommittedLines()
    try testPartialOverwritesPreviousPartial()
    try testDisplayTextCombinesCommittedAndLive()
    try testResetClearsEverything()
    try testEmptyTextIsIgnored()
    try testTimestampFormatting()
    try testOldTextNeverErased()
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
