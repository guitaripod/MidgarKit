import Foundation
@testable import MidgarUI

func makeDefaults() -> UserDefaults {
    let name = "midgar.ui.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name) ?? .standard
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@MainActor
final class RecordingSystem: MidgarSystemActions {
    var opened: [URL] = []
    var copied: [String] = []
    var played: [MidgarHapticEvent] = []
    var openSucceeds = true

    func open(_ url: URL) async -> Bool {
        opened.append(url)
        return openSucceeds
    }

    func copy(_ text: String) {
        copied.append(text)
    }

    func play(_ event: MidgarHapticEvent) {
        played.append(event)
    }
}

@MainActor
final class RecordingPlayer: MidgarHapticPlaying {
    var isSupported = true
    var prepared = 0
    var events: [MidgarHapticEvent] = []

    func prepare() {
        prepared += 1
    }

    func play(_ event: MidgarHapticEvent) {
        events.append(event)
    }
}

struct TestFailure: LocalizedError {
    var errorDescription: String? { "boom" }
}
