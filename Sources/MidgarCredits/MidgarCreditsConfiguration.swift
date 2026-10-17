import Foundation
import MidgarCommerce
import MidgarCore

/// One credit pack the app sells. All three values come from the app (later generated from the registry's `[commerce]` table); nothing is inferred from a product id or fetched to decide what a product is worth.
public struct MidgarCreditsPack: Sendable, Equatable, Identifiable, Codable {
    /// The pack id in mako's catalog for this app (`starter`). mako binds the paid product to it: the product id must be the app's product prefix plus this id.
    public let id: String
    /// The App Store product id of the consumable. It must also be in ``MidgarStoreConfiguration/productIDs``, or the store refuses to sell it.
    public let productID: String
    /// What the pack grants in total, bonus included. mako's answer is authoritative; this value is what the app shows before the purchase and what ``MidgarCreditsPurchaseResult/creditPending(packID:credits:)`` reports while mako has not answered yet.
    public let credits: Int

    public init(id: String, productID: String, credits: Int) {
        self.id = id
        self.productID = productID
        self.credits = credits
    }
}

/// What MidgarCredits needs to know about the app.
public struct MidgarCreditsConfiguration: Sendable {
    public let packs: [MidgarCreditsPack]
    /// Where purchases that mako has not confirmed yet are kept across launches. Defaults to `<Application Support>/Midgar`, beside the commerce state.
    public let directory: URL?

    public init(packs: [MidgarCreditsPack], directory: URL? = nil) {
        self.packs = packs
        self.directory = directory
    }

    /// The product ids to add to the store's ``MidgarStoreConfiguration/productIDs``.
    public var productIDs: [String] {
        packs.map(\.productID)
    }
}

/// What MidgarCredits asks of the identity: the Midgar ID's access token. ``MidgarIdentity`` is the production conformance.
public protocol MidgarCreditsIdentity: Sendable {
    func accessToken() async throws -> String
    func invalidateAccessToken() async
}

extension MidgarIdentity: MidgarCreditsIdentity {}

/// What MidgarCredits asks of the purchase engine. ``MidgarStore`` is the production conformance.
public protocol MidgarCreditsPurchasing: Sendable {
    func products() async throws -> [StoreProduct]
    func purchaseReceipt(_ productID: String) async throws -> MidgarReceiptResult
    func events() async -> AsyncStream<MidgarStoreEvent>
}

extension MidgarStore: MidgarCreditsPurchasing {}
