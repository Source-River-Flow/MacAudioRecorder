import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var transcriber: SystemAudioTranscriber

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("System Audio Transcriber")
                        .font(.title2.weight(.semibold))
                    Text(transcriber.status)
                        .foregroundStyle(.secondary)
                    Text("Latest: \(transcriber.latestLogMessage)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                Spacer()

                Button {
                    transcriber.isRunning ? transcriber.stop() : transcriber.start()
                } label: {
                    Text(transcriber.isRunning ? "Stop" : "Start")
                        .frame(width: 72)
                }
                .keyboardShortcut(.space, modifiers: [])
                .controlSize(.large)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Log")
                        .font(.headline)

                    Spacer()

                    Button("Clear Log") {
                        transcriber.clearLog()
                    }
                    .disabled(transcriber.logMessages.isEmpty)
                }

                ScrollView {
                    Text(transcriber.logMessages.isEmpty ? "No log messages yet." : transcriber.logMessages.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(transcriber.logMessages.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .frame(width: 620, height: 150)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor))
                }
            }

            ScrollView {
                Text(transcriber.transcript.isEmpty ? "Play English audio on this Mac, then press Start." : transcriber.transcript)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(transcriber.transcript.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(width: 620, height: 360)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor))
            }

            HStack {
                Button("Clear") {
                    transcriber.clear()
                }
                .disabled(transcriber.transcript.isEmpty)

                Spacer()

                Text("Uses Core Audio taps + Speech")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if transcriber.lastTranscriptFile != nil || transcriber.dailyEventLogFile != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let lastTranscriptFile = transcriber.lastTranscriptFile {
                        Text("Last transcript: \(lastTranscriptFile.path)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }

                    if let dailyEventLogFile = transcriber.dailyEventLogFile {
                        Text("Daily diagnostics: \(dailyEventLogFile.path)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }

                    HStack {
                        Spacer()

                        Button("Open Logs Folder") {
                            transcriber.openLogsDirectory()
                        }
                    }
                }
            }
        }
        .padding(20)
    }
}
