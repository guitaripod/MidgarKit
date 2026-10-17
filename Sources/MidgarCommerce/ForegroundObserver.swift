import Foundation

/// Calls back when the app returns to the foreground. The notification is named by its raw value so MidgarCommerce never imports UIKit or AppKit. The only stored property is an immutable observer token that is only removed in `deinit`, which is what makes the unchecked conformance sound.
final class ForegroundObserver: @unchecked Sendable {
    private let token: any NSObjectProtocol

    init(onForeground: @escaping @Sendable () -> Void) {
        token = NotificationCenter.default.addObserver(forName: Self.name, object: nil, queue: nil) { _ in
            onForeground()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }

    private static var name: Notification.Name {
        #if os(macOS)
        Notification.Name("NSApplicationDidBecomeActiveNotification")
        #else
        Notification.Name("UIApplicationWillEnterForegroundNotification")
        #endif
    }
}
