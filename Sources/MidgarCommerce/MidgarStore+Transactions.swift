import Foundation
import MidgarCore

extension MidgarStore {
    /// Runs one transaction through the money path. Verified: queue the report on disk, finish, record the signal, re-read StoreKit's entitlements and refresh the ledger view. Unverified: log, tell observers and, for a purchase the customer just made, throw; never granted, finished or reported. A product the store was not configured with is left untouched for whichever system owns it.
    func handle(_ verification: StoreVerification, origin: Origin) async throws {
        switch verification {
        case .unverified(let transaction, let reason):
            guard handledProducts.contains(transaction.productID) else {
                return
            }
            log("commerce: refused an unverified transaction for \(transaction.productID): \(reason)")
            emit(.refused(productID: transaction.productID))
            if origin == .purchase {
                throw MidgarStoreError.unverifiedTransaction(productID: transaction.productID)
            }
        case .verified(let transaction):
            guard handledProducts.contains(transaction.productID) else {
                log("commerce: ignored a transaction for \(transaction.productID), which this store does not handle")
                return
            }
            await accept(transaction, origin: origin)
        }
    }

    private func accept(_ transaction: StoreTransaction, origin: Origin) async {
        guard markSeen(transaction) || origin == .purchase else {
            return
        }
        observe(transaction.environment)
        if shouldReport(transaction) {
            enqueueReport(transaction)
        }
        await finishOnce(transaction)
        let isNewPurchase = Self.isNewPurchase(transaction)
        if origin == .purchase || isNewPurchase {
            await signal(.paywallPurchase(product: transaction.productID))
        }
        if origin == .update && isNewPurchase {
            emit(.purchaseApproved(productID: transaction.productID))
        }
        await refreshLocal()
        await awaitLocalGrant(of: transaction)
        publishIfChanged()
        Task { [weak self] in await self?.refresh() }
    }

    /// The pauses between re-reads of StoreKit's entitlements while a transaction that grants something is not listed yet, three seconds in all.
    static let grantLagDelays: [Duration] = Array(repeating: .milliseconds(250), count: 12)

    /// StoreKit can hand over a transaction before `currentEntitlements` lists it (the macOS 27 betas trail by up to a second, seen with an approved Ask to Buy and with renewals), and nothing would read the list again. A transaction that grants something right now is waited for in bounded steps, so the change is published once, with the grant in it.
    private func awaitLocalGrant(of transaction: StoreTransaction) async {
        guard let expected = localEntitlement(for: transaction), expected.isActive(at: clock()) else {
            return
        }
        for delay in Self.grantLagDelays {
            if isListed(expected) {
                return
            }
            do {
                try await grantLagSleep(delay)
            } catch {
                return
            }
            await refreshLocal()
        }
        if !isListed(expected) {
            log("commerce: StoreKit still does not list \(transaction.productID) after a verified transaction; the next refresh grants it")
        }
    }

    /// True when the local grants hold the entitlement at least until the transaction's expiry, so a renewal counts only once its new period is listed.
    private func isListed(_ expected: MidgarEntitlement) -> Bool {
        localEntitlements.contains { granted in
            guard granted.name == expected.name else {
                return false
            }
            guard let expiry = expected.expirationDate else {
                return true
            }
            return (granted.expirationDate ?? .distantFuture) >= expiry
        }
    }

    /// True the first time this transaction in this revocation state reaches the store. A purchase result and the updates listener may both deliver one transaction; a refund of it is a different state and is processed.
    private func markSeen(_ transaction: StoreTransaction) -> Bool {
        seenTransactions.insert(Self.stateKey(transaction)).inserted
    }

    private static func stateKey(_ transaction: StoreTransaction) -> String {
        "\(transaction.id):\(transaction.revocationDate != nil)"
    }

    /// A first purchase, as opposed to a renewal (a later transaction of the same original id) or a refund.
    static func isNewPurchase(_ transaction: StoreTransaction) -> Bool {
        transaction.id == transaction.originalID && transaction.revocationDate == nil && transaction.ownership == .purchased
    }

    /// The ledger can only attribute a transaction the account bought itself, and cannot verify one signed by Xcode's local certificate.
    func shouldReport(_ transaction: StoreTransaction) -> Bool {
        transaction.ownership == .purchased && transaction.environment != .xcode
    }

    private func finishOnce(_ transaction: StoreTransaction) async {
        guard finishedTransactions.insert(Self.stateKey(transaction)).inserted else {
            return
        }
        await transaction.finish()
    }

    /// A non-production environment on any transaction means this install talks to the sandbox, which decides the ledger environment.
    private func observe(_ environment: StoreEnvironment) {
        if environment != .production {
            resolvedEnvironment = environment
        }
    }

    /// Re-reads StoreKit's current entitlements into the local grants. Unverified entries grant nothing. Revoked, upgraded and non-entitlement transactions never appear.
    func refreshLocal() async {
        guard configuration.mode == .purchases else {
            return
        }
        var granted: [MidgarEntitlement] = []
        for verification in await storeKit.currentEntitlements() {
            switch verification {
            case .verified(let transaction):
                if let entitlement = localEntitlement(for: transaction) {
                    granted.append(entitlement)
                }
            case .unverified(let transaction, let reason):
                log("commerce: ignored an unverified current entitlement for \(transaction.productID): \(reason)")
            }
        }
        localEntitlements = Self.collapse(granted)
    }

    private func localEntitlement(for transaction: StoreTransaction) -> MidgarEntitlement? {
        guard let name = configuration.entitlementsByProduct[transaction.productID],
              transaction.revocationDate == nil,
              !transaction.isUpgraded
        else {
            return nil
        }
        let kind: MidgarEntitlement.Kind
        switch transaction.kind {
        case .nonConsumable:
            kind = .nonConsumable
        case .autoRenewableSubscription:
            kind = .subscription
        case .consumable, .nonRenewingSubscription:
            return nil
        }
        return MidgarEntitlement(
            name: name,
            productID: transaction.productID,
            kind: kind,
            expirationDate: transaction.expirationDate,
            isInGracePeriod: false,
            ownership: transaction.ownership == .familyShared ? .familyShared : .purchased,
            sources: .storeKit,
            app: nil
        )
    }
}
