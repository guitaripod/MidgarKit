import Foundation

/// The version and build of an app, as shown in settings and copied into bug reports.
public struct MidgarVersionInfo: Sendable, Hashable {
    public var name: String
    public var version: String
    public var build: String

    public init(name: String, version: String, build: String) {
        self.name = name
        self.version = version
        self.build = build
    }

    /// Reads the display name, `CFBundleShortVersionString` and `CFBundleVersion` of a bundle.
    public init(bundle: Bundle = .main) {
        let info = bundle.infoDictionary ?? [:]
        let name = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? ""
        self.init(
            name: name,
            version: info["CFBundleShortVersionString"] as? String ?? "",
            build: info["CFBundleVersion"] as? String ?? ""
        )
    }

    /// `1.4.2 (87)`, or just `1.4.2` when there is no separate build number.
    public var display: String {
        guard !build.isEmpty, build != version else { return version }
        guard !version.isEmpty else { return build }
        return "\(version) (\(build))"
    }

    /// `Pay Day 1.4.2 (87)`, the line a person pastes into an email.
    public var copyText: String {
        [name, display].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
