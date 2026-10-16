import Foundation

/// Where the identity flows log. Messages describe decisions (mint, attach, refresh, fork) and never contain tokens, credentials, key ids or Midgar IDs.
public struct MidgarIdentityLogger: Sendable {
    public let info: @Sendable (String) -> Void
    public let warning: @Sendable (String) -> Void

    public init(info: @escaping @Sendable (String) -> Void, warning: @escaping @Sendable (String) -> Void) {
        self.info = info
        self.warning = warning
    }

    /// The process-wide ``MidgarLog`` in the account category.
    public static let standard = MidgarIdentityLogger(
        info: { AppLogger.info($0, category: .account) },
        warning: { AppLogger.warning($0, category: .account) }
    )
}
