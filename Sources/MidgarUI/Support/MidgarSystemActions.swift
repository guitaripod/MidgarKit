import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// What MidgarUI asks of the system outside its own views: opening links, copying text and playing haptics.
/// Tests replace it with a recorder.
@MainActor
protocol MidgarSystemActions {
    func open(_ url: URL) async -> Bool
    func copy(_ text: String)
    func play(_ event: MidgarHapticEvent)
}

@MainActor
struct MidgarLiveSystemActions: MidgarSystemActions {
    func open(_ url: URL) async -> Bool {
        #if canImport(UIKit)
        await UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }

    func copy(_ text: String) {
        #if canImport(UIKit) && !os(tvOS)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    func play(_ event: MidgarHapticEvent) {
        MidgarHaptics.shared.play(event)
    }
}

/// Speaks a short message to VoiceOver users.
@MainActor
enum MidgarAnnouncer {
    static func announce(_ message: String) {
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: message)
        #elseif canImport(AppKit)
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
        #endif
    }
}
