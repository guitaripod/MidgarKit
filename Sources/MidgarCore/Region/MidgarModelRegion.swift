import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(StoreKit)
import StoreKit
#endif

/// Whether model features (anything that asks a language or image model through Midgar's servers) work where this device connects from.
///
/// Midgar's servers refuse model calls with HTTP 451 `unavailable_in_region` in the countries the model providers do not serve, China mainland and Hong Kong among them. Apps hide their model features and the paywall lines that sell them while ``modelsAvailable`` is false, and show ``unavailableMessage`` where a refused call would have answered. The answer is the device's last one from the gateway, so it follows the person when they travel.
public final class MidgarModelRegion: @unchecked Sendable {
    /// Posted on the thread that learned the change whenever ``modelsAvailable`` or ``onDeviceGenerationAvailable`` flips; observers that touch UI hop to the main actor.
    public static let didChangeNotification = Notification.Name("MidgarModelRegionDidChange")

    /// The HTTP status every model route answers with when it refuses a call for the caller's country.
    public static let refusalStatus = 451

    /// The instance every app uses, remembered in the standard user defaults.
    public static let shared = MidgarModelRegion(defaults: .standard)

    private static let storageKey = "MidgarModelRegion.modelsAvailable"

    private static let onDeviceStorageKey = "MidgarModelRegion.onDeviceGenerationAvailable"

    /// The App Store storefront of China mainland, where Apple's AI declarations need CAC filings Midgar cannot hold.
    static let chinaMainlandStorefront = "CHN"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The last answer this device got, true until it gets one, so a device that never reached Midgar loses nothing.
    public var modelsAvailable: Bool {
        defaults.object(forKey: Self.storageKey) as? Bool ?? true
    }

    /// Whether generative features that run on the device (Apple Foundation Models, MLX models) may be offered: false for a China mainland App Store account, so the app's China declarations can answer No. True until ``refresh(client:)`` has read the storefront.
    public var onDeviceGenerationAvailable: Bool {
        defaults.object(forKey: Self.onDeviceStorageKey) as? Bool ?? true
    }

    /// Whether on-device generation may be offered to an account of this storefront (`Storefront.countryCode`).
    static func allowsOnDeviceGeneration(storefrontCountryCode: String?) -> Bool {
        storefrontCountryCode?.uppercased() != chinaMainlandStorefront
    }

    /// The one line shown where a model feature was refused for the person's country. It blames no one.
    public static var unavailableMessage: String {
        NSLocalizedString(
            "Not available in your region.",
            bundle: .module,
            comment: "Shown instead of an AI feature, or after a request to one, when Midgar's servers do not offer AI features in the country the device connects from"
        )
    }

    /// Asks the gateway whether model features work here and reads the App Store storefront for on-device generation, and remembers both. A failed request keeps the last answer. Call it at launch and when the app returns to the foreground.
    @discardableResult
    public func refresh(client: MidgarHTTPClient) async -> Bool {
        await refreshStorefront()
        let answer: RegionAnswer? = try? await client.send(MidgarRequest(service: "region"))
        if let answer {
            remember(answer.models)
        }
        return modelsAvailable
    }

    /// Reads the account's storefront; nothing changes where StoreKit has none to give.
    private func refreshStorefront() async {
        #if canImport(StoreKit)
        if let storefront = await Storefront.current {
            remember(onDevice: Self.allowsOnDeviceGeneration(storefrontCountryCode: storefront.countryCode))
        }
        #endif
    }

    /// Remembers a model route's answer status: a 451 means model features do not work here. Returns true when it was that refusal.
    @discardableResult
    public func note(statusCode: Int) -> Bool {
        guard statusCode == Self.refusalStatus else { return false }
        remember(false)
        return true
    }

    /// Remembers a refusal carried by an error from `MidgarHTTPClient`. Returns true when the error was that refusal.
    @discardableResult
    public func note(_ error: any Error) -> Bool {
        guard Self.isRefusal(error) else { return false }
        remember(false)
        return true
    }

    /// Whether this error is a model route's refusal for the caller's country.
    public static func isRefusal(_ error: any Error) -> Bool {
        if case .server(let status, _, _) = error as? MidgarHTTPError {
            return status == refusalStatus
        }
        return false
    }

    /// Stores the answer and posts ``didChangeNotification`` when it differs from the last one.
    private func remember(_ available: Bool) {
        let changed = available != modelsAvailable
        defaults.set(available, forKey: Self.storageKey)
        if changed {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    /// Stores the storefront's answer for on-device generation and posts ``didChangeNotification`` when it flips.
    func remember(onDevice available: Bool) {
        let changed = available != onDeviceGenerationAvailable
        defaults.set(available, forKey: Self.onDeviceStorageKey)
        if changed {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }
}

/// The gateway's `GET /v1/region` answer.
private struct RegionAnswer: Decodable, Sendable {
    let models: Bool
}
