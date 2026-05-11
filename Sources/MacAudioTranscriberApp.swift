import SwiftUI

@main
struct MacAudioTranscriberApp: App {
    @StateObject private var transcriber = SystemAudioTranscriber()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(transcriber)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
    }
}
