import Foundation
#if canImport(StoreKit)
import StoreKit
#endif

/// Where this install came from, as far as usage counts care.
enum MidgarSignalsInstallSource {
    /// True when StoreKit says a server other than the App Store's production one signed this install (`AppTransaction.environment`): TestFlight, a sandbox-signed development build, or StoreKit testing in Xcode. False on the App Store, off Apple platforms, and whenever StoreKit cannot answer, so an install that may be a customer's is always counted.
    static func isTestInstall() async -> Bool {
        #if canImport(StoreKit)
        guard let result = try? await AppTransaction.shared else {
            return false
        }
        return result.unsafePayloadValue.environment != .production
        #else
        return false
        #endif
    }
}
