import Foundation

/// The two headers that describe the app: the platform the server buckets by and the app version.
enum MidgarSignalsPlatform {
    /// `ios`, `ipados`, `macos`, `tvos`, `visionos`, `watchos`, `android` or `linux`, read from the OS the code was built for. An iPad is told apart by its hardware name without a UI framework.
    static var current: String {
        #if os(iOS)
        #if targetEnvironment(macCatalyst)
        return "macos"
        #else
        return isPad ? "ipados" : "ios"
        #endif
        #elseif os(macOS)
        return "macos"
        #elseif os(tvOS)
        return "tvos"
        #elseif os(visionOS)
        return "visionos"
        #elseif os(watchOS)
        return "watchos"
        #elseif os(Android)
        return "android"
        #else
        return "linux"
        #endif
    }

    /// `CFBundleShortVersionString` of the host app, or nil when it has none.
    static func bundleVersion(_ bundle: Bundle = .main) -> String? {
        bundle.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    #if os(iOS) && !targetEnvironment(macCatalyst)
    /// True on an iPad, and on the simulator when it simulates one.
    private static var isPad: Bool {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated.hasPrefix("iPad")
        }
        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: &system.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
        return machine.hasPrefix("iPad")
    }
    #endif
}
