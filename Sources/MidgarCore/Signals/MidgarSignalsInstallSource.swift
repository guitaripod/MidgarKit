import Foundation
#if canImport(StoreKit)
import StoreKit
#endif

/// Where this install came from, as far as usage counts care.
enum MidgarSignalsInstallSource {
    /// True unless this run is an App Store copy of the app: never a simulator, never a build with `DEBUG` on, never a
    /// bundle with no store receipt (an Xcode install, a development-signed build, a preview), and never an install
    /// StoreKit places anywhere but the production server (TestFlight, sandbox-signed builds, StoreKit testing in Xcode).
    /// Only a receipt that StoreKit cannot answer for counts, so an App Store copy launched offline is still counted.
    static func isTestInstall(bundle: Bundle = .main, fileManager: FileManager = .default) async -> Bool {
        #if targetEnvironment(simulator)
        return true
        #elseif DEBUG
        return true
        #elseif !canImport(Darwin)
        return true
        #else
        return isTestInstall(hasReceipt: hasReceipt(in: bundle, fileManager: fileManager), production: await isProductionInstall())
        #endif
    }

    /// The rule on the facts, which the tests read: StoreKit's answer decides when it has one, and a bundle with no
    /// receipt it cannot place is not an App Store copy.
    static func isTestInstall(hasReceipt: Bool, production: Bool?) -> Bool {
        if let production {
            return !production
        }
        return !hasReceipt
    }

    /// Whether the bundle carries the receipt the App Store leaves in a copy it installed, which a build run from Xcode,
    /// a development-signed build and a simulator do not have.
    private static func hasReceipt(in bundle: Bundle, fileManager: FileManager) -> Bool {
        guard let url = bundle.appStoreReceiptURL else {
            return false
        }
        return fileManager.fileExists(atPath: url.path)
    }

    /// True when StoreKit places this install on the App Store's production server, false for TestFlight, sandbox-signed
    /// and StoreKit-testing installs, nil when StoreKit cannot answer.
    private static func isProductionInstall() async -> Bool? {
        #if canImport(StoreKit)
        guard let result = try? await AppTransaction.shared else {
            return nil
        }
        return result.unsafePayloadValue.environment == .production
        #else
        return nil
        #endif
    }
}
