import Foundation
import MidgarCore

/// Decides whether a build may enter demo mode. Demo mode fakes data and freezes the clock, so a shipping build must never enter it because of a launch argument or an environment variable. DEBUG builds always may. A release build may only when its Info.plist sets `MidgarDemoEnabled` to `YES`, which a screenshot build of the app does and the App Store build does not.
public enum DemoGate {
    /// The Info.plist key that lets a release build enter demo mode.
    public static let infoKey = "MidgarDemoEnabled"

    /// Whether this process may enter demo mode.
    public static var isPermitted: Bool {
        isPermitted(isDebugBuild: isDebugBuild, infoDictionary: Bundle.main.infoDictionary)
    }

    /// The rule as a pure function: debug builds, or an Info.plist value that is the boolean true or the text `YES`, `true` or `1`.
    public static func isPermitted(isDebugBuild: Bool, infoDictionary: [String: Any]?) -> Bool {
        if isDebugBuild {
            return true
        }
        switch infoDictionary?[infoKey] {
        case let flag as Bool:
            return flag
        case let text as String:
            return ["yes", "true", "1"].contains(text.lowercased())
        default:
            return false
        }
    }

    static func logRefusal() {
        AppLogger.warning("demo: ignoring the launch contract, this build is not a screenshot build (\(infoKey) is not YES)")
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}
