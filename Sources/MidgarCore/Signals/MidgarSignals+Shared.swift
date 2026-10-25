import Foundation

extension MidgarSignals {
    /// The instance ``configure(configuration:config:directory:appVersion:)`` made, or nil until the host app configures signals. Code that records events on the host's behalf, such as the portal, does nothing while this is nil.
    public static var shared: MidgarSignals? {
        MidgarSignalsRegistry.current
    }

    /// Whether usage counts are sent, for the app's settings screen: the choice of the ``shared`` instance, on until the person turns it off, and on while signals are not configured. Setting it does nothing until they are. See ``isEnabled``.
    public static var isEnabled: Bool {
        get { shared?.isEnabled ?? true }
        set { shared?.setEnabled(newValue) }
    }

    /// Creates the app's signals client and makes it ``shared``. Call it once at launch; a later call replaces the earlier instance, whose saved events the new one reads from the same file. It reports the install active (``noteActive()``) now and on every return to the foreground.
    @discardableResult
    public static func configure(
        configuration: MidgarHTTPConfiguration,
        config: @escaping @Sendable () -> MidgarConfig = { MidgarConfig() },
        directory: URL? = nil,
        appVersion: String? = nil
    ) -> MidgarSignals {
        let signals = MidgarSignals(
            configuration: configuration,
            config: config,
            directory: directory,
            appVersion: appVersion
        )
        MidgarSignalsRegistry.install(signals)
        let observer = MidgarForegroundObserver { [weak signals] in
            Task { await signals?.noteActive() }
        }
        let backgroundObserver = MidgarForegroundObserver(name: MidgarForegroundObserver.backgroundName) { [weak signals] in
            Task { await signals?.persistPending() }
        }
        Task {
            await signals.retain(observer)
            await signals.retain(backgroundObserver)
            await signals.noteActive()
        }
        return signals
    }
}

/// The process-wide instance. The lock guards the one field, which is what makes the unchecked conformance sound.
final class MidgarSignalsRegistry: @unchecked Sendable {
    private static let shared = MidgarSignalsRegistry()

    private let lock = NSLock()
    private var instance: MidgarSignals?

    static var current: MidgarSignals? {
        shared.lock.withLock { shared.instance }
    }

    static func install(_ signals: MidgarSignals?) {
        shared.lock.withLock { shared.instance = signals }
    }
}
