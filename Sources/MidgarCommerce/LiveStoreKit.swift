import Foundation
import StoreKit

/// The production ``MidgarStoreKit``: a thin mapping onto StoreKit 2 with no decisions of its own.
actor LiveStoreKit: MidgarStoreKit {
    private var cachedProducts: [String: Product] = [:]

    func products(for ids: [String]) async throws -> [StoreProduct] {
        let found = try await Product.products(for: ids)
        for product in found {
            cachedProducts[product.id] = product
        }
        return ids.compactMap { id in
            cachedProducts[id].map {
                StoreProduct(
                    id: $0.id,
                    displayName: $0.displayName,
                    description: $0.description,
                    displayPrice: $0.displayPrice,
                    price: $0.price,
                    isFamilyShareable: $0.isFamilyShareable,
                    currencyCode: $0.priceFormatStyle.currencyCode
                )
            }
        }
    }

    func purchase(productID: String, appAccountToken: UUID?, confirmation: StoreConfirmation?) async throws -> StorePurchaseOutcome {
        let product = try await product(for: productID)
        var options: Set<Product.PurchaseOption> = []
        if let appAccountToken {
            options.insert(.appAccountToken(appAccountToken))
        }
        let result = try await Self.purchase(product, options: options, confirmation: confirmation)
        switch result {
        case .success(let verification):
            return .success(Self.map(verification))
        case .pending:
            return .pending
        case .userCancelled:
            return .userCancelled
        @unknown default:
            throw MidgarStoreError.storeKit("StoreKit returned a purchase result this version does not know.")
        }
    }

    /// Runs the purchase on the main actor, confirming in the scene or window when one is given. Where the SDK offers no plain `purchase(options:)` (visionOS) a purchase without a scene is refused, and a scene or window of the wrong kind for the platform is too. Before the OS versions that offer `confirmIn` (iOS 17, macOS 15.2) the plain purchase is used.
    @MainActor
    private static func purchase(
        _ product: Product,
        options: Set<Product.PurchaseOption>,
        confirmation: StoreConfirmation?
    ) async throws -> Product.PurchaseResult {
        #if os(macOS)
        if let confirmation {
            guard let window = confirmation.anchor as? NSWindow else {
                throw MidgarStoreError.unsupportedPlatform
            }
            if #available(macOS 15.2, *) {
                return try await product.purchase(confirmIn: window, options: options)
            }
        }
        return try await product.purchase(options: options)
        #elseif os(visionOS)
        guard let scene = confirmation?.anchor as? UIScene else {
            throw MidgarStoreError.unsupportedPlatform
        }
        return try await product.purchase(confirmIn: scene, options: options)
        #elseif os(iOS) || os(tvOS)
        if let confirmation {
            guard let scene = confirmation.anchor as? UIScene else {
                throw MidgarStoreError.unsupportedPlatform
            }
            if #available(iOS 17.0, tvOS 17.0, *) {
                return try await product.purchase(confirmIn: scene, options: options)
            }
        }
        return try await product.purchase(options: options)
        #else
        return try await product.purchase(options: options)
        #endif
    }

    nonisolated func updates() -> AsyncStream<StoreVerification> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    continuation.yield(Self.map(result))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func currentEntitlements() async -> [StoreVerification] {
        var found: [StoreVerification] = []
        for await result in Transaction.currentEntitlements {
            found.append(Self.map(result))
        }
        return found
    }

    func sync() async throws {
        try await AppStore.sync()
    }

    /// `AppTransaction.environment`, StoreKit's own statement of which server signed this install: `sandbox` for TestFlight and sandbox-signed debug builds, `xcode` for StoreKit testing, `production` for the App Store. Nil while the app transaction cannot be verified.
    func appEnvironment() async -> StoreEnvironment? {
        guard let result = try? await AppTransaction.shared, case .verified(let appTransaction) = result else {
            return nil
        }
        return Self.map(appTransaction.environment)
    }

    private func product(for id: String) async throws -> Product {
        if let cached = cachedProducts[id] {
            return cached
        }
        _ = try await products(for: [id])
        guard let product = cachedProducts[id] else {
            throw MidgarStoreError.unknownProduct(id)
        }
        return product
    }

    static func map(_ result: VerificationResult<Transaction>) -> StoreVerification {
        switch result {
        case .verified(let transaction):
            return .verified(map(transaction, jws: result.jwsRepresentation))
        case .unverified(let transaction, let error):
            return .unverified(map(transaction, jws: result.jwsRepresentation), reason: String(describing: error))
        }
    }

    static func map(_ transaction: Transaction, jws: String) -> StoreTransaction {
        StoreTransaction(
            id: transaction.id,
            originalID: transaction.originalID,
            productID: transaction.productID,
            kind: map(transaction.productType),
            purchaseDate: transaction.purchaseDate,
            expirationDate: transaction.expirationDate,
            revocationDate: transaction.revocationDate,
            isUpgraded: transaction.isUpgraded,
            ownership: transaction.ownershipType == .familyShared ? .familyShared : .purchased,
            appAccountToken: transaction.appAccountToken,
            environment: map(transaction.environment),
            jws: jws,
            finish: { await transaction.finish() }
        )
    }

    private static func map(_ type: Product.ProductType) -> StoreProductKind {
        switch type {
        case .consumable: return .consumable
        case .nonConsumable: return .nonConsumable
        case .nonRenewable: return .nonRenewingSubscription
        default: return .autoRenewableSubscription
        }
    }

    private static func map(_ environment: AppStore.Environment) -> StoreEnvironment {
        if environment == .production {
            return .production
        }
        if environment == .sandbox {
            return .sandbox
        }
        return .xcode
    }
}
