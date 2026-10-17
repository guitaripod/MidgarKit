import Foundation
import MidgarCommerce
import MidgarCore

extension MidgarCredits {
    /// How validating one receipt with mako ended.
    enum Settlement: Sendable, Equatable {
        case credited(creditsAdded: Int, newBalance: Int)
        case alreadyProcessed
        case retry(MidgarCreditsError)
        case rejected(MidgarCreditsError)
    }

    /// mako's text for a purchase it has already credited (400). It has no code of its own, so the text is the only signal.
    static let alreadyProcessedMessage = "already been processed"
    /// mako's text when RevenueCat does not (yet) list the purchase (400). RevenueCat can lag the App Store by seconds, so it is retried like a 500.
    static let notYetVerifiedMessage = "could not be verified"

    /// Buys a pack and credits it. The store buys, finishes and reports the transaction to the ledger first; then mako's fast-track validation credits the wallet and the balance is read again.
    ///
    /// - Returns: ``MidgarCreditsPurchaseResult``. After the customer has paid this does not throw for a failure that a later attempt can fix: the purchase stays on disk and the result is ``MidgarCreditsPurchaseResult/creditPending(packID:credits:)``.
    /// - Throws: ``MidgarCreditsError``: `notConfigured` before anything is charged, `store` when StoreKit refuses, `purchaseRejected` when mako will never credit the purchase.
    public func buy(_ packID: String) async throws -> MidgarCreditsPurchaseResult {
        guard !configuration.packs.isEmpty else {
            throw MidgarCreditsError.notConfigured(.noPacks)
        }
        guard let pack = configuration.packs.first(where: { $0.id == packID }) else {
            throw MidgarCreditsError.notConfigured(.unknownPack(packID))
        }
        let outcome: MidgarReceiptResult
        do {
            outcome = try await purchasing.purchaseReceipt(pack.productID)
        } catch let error as MidgarStoreError {
            throw Self.configurationProblem(in: error) ?? MidgarCreditsError.store(error)
        }
        switch outcome {
        case .cancelled:
            return .cancelled
        case .pending:
            return .awaitingApproval
        case .purchased(let receipt):
            return try await credit(receipt, for: pack)
        }
    }

    /// Credits a purchase the app made another way (a scene-anchored `MidgarStore.purchaseReceipt(_:confirmIn:)`). Same money path and result as ``buy(_:)``.
    public func redeem(_ receipt: MidgarPurchaseReceipt) async throws -> MidgarCreditsPurchaseResult {
        guard let pack = configuration.packs.first(where: { $0.productID == receipt.productID }) else {
            throw MidgarCreditsError.notConfigured(.productNotSold(receipt.productID))
        }
        return try await credit(receipt, for: pack)
    }

    private static func configurationProblem(in error: MidgarStoreError) -> MidgarCreditsError? {
        switch error {
        case .unknownProduct(let productID):
            return .notConfigured(.productNotSold(productID))
        case .readOnly:
            return .notConfigured(.purchasesDisabled)
        case .unverifiedTransaction, .unsupportedPlatform, .storeKit:
            return nil
        }
    }

    /// Queues the receipt on disk and validates it, retrying while mako says it will credit shortly.
    private func credit(_ receipt: MidgarPurchaseReceipt, for pack: MidgarCreditsPack) async throws -> MidgarCreditsPurchaseResult {
        enqueue(PendingCredit(packID: pack.id, receipt: receipt, queuedAt: clock()))
        var delays = Self.validationDelays[...]
        while true {
            switch await settle(receipt, for: pack) {
            case .credited(let creditsAdded, let newBalance):
                return await confirmed(pack: pack, creditsAdded: creditsAdded, fallbackBalance: newBalance)
            case .alreadyProcessed:
                return await confirmed(pack: pack, creditsAdded: pack.credits, fallbackBalance: nil)
            case .rejected(let error):
                throw error
            case .retry(let error):
                guard let delay = delays.popFirst() else {
                    log("credits: \(receipt.productID) transaction \(receipt.transactionID) is paid and not yet credited (\(Self.describe(error)))")
                    scheduleReconcile()
                    return .creditPending(packID: pack.id, credits: pack.credits)
                }
                try await sleep(.seconds(delay))
            }
        }
    }

    /// The result of a credit mako confirmed: the authoritative balance is read again, and the validation's own answer stands in when that read fails.
    private func confirmed(pack: MidgarCreditsPack, creditsAdded: Int, fallbackBalance: Int?) async -> MidgarCreditsPurchaseResult {
        let balance: Int
        if let read = try? await readBalance() {
            balance = read.credits
        } else if let fallbackBalance {
            balance = record(credits: fallbackBalance).credits
        } else {
            balance = cachedBalance?.credits ?? 0
        }
        emit(.purchaseCredited(packID: pack.id, creditsAdded: creditsAdded))
        return .credited(packID: pack.id, creditsAdded: creditsAdded, balance: balance)
    }

    /// Sends one receipt to mako and settles the queue by the answer. A receipt that is already being validated counts as a retry, so two callers never race each other.
    func settle(_ receipt: MidgarPurchaseReceipt, for pack: MidgarCreditsPack) async -> Settlement {
        guard settling.insert(receipt.transactionID).inserted else {
            return .retry(.walletUnavailable)
        }
        defer { settling.remove(receipt.transactionID) }
        let body = CreditsValidateBody(
            packID: pack.id,
            purchaseToken: receipt.transactionID,
            productID: receipt.productID,
            platform: "ios",
            signedTransaction: receipt.signedTransaction
        )
        let settlement: Settlement
        do {
            let wire = try await api.validate(body)
            settlement = wire.success ? .credited(creditsAdded: wire.creditsAdded, newBalance: wire.newBalance) : .rejected(.invalidResponse)
        } catch let error as MidgarCreditsError {
            settlement = Self.classify(error)
        } catch {
            return .retry(.offline)
        }
        switch settlement {
        case .credited, .alreadyProcessed, .rejected:
            dequeue(receipt)
        case .retry:
            break
        }
        return settlement
    }

    /// Whether mako's refusal can still turn into a credit. Offline, a busy wallet, a rate limit, a missing token and any 5xx can; so can a 400 saying the purchase is not visible to the verifier yet. A 400 saying it is already processed is a success. Everything else is final.
    static func classify(_ error: MidgarCreditsError) -> Settlement {
        switch error {
        case .offline, .walletUnavailable, .rateLimited, .identityUnavailable, .unauthorized:
            return .retry(error)
        case .server(let status, _, let message):
            if status >= 500 {
                return .retry(error)
            }
            if status == 400, message.contains(alreadyProcessedMessage) {
                return .alreadyProcessed
            }
            if status == 400, message.contains(notYetVerifiedMessage) {
                return .retry(error)
            }
            return .rejected(.purchaseRejected(message: message))
        case .insufficientCredits, .notConfigured, .purchaseRejected, .store, .invalidResponse:
            return .rejected(error)
        }
    }

    /// Validates every queued receipt once. A receipt that is final either way leaves the queue; one older than a week is dropped with a log line, because the webhook has had every chance to credit it.
    func settlePending() async {
        dropExpired()
        for entry in pending {
            guard let pack = configuration.packs.first(where: { $0.id == entry.packID }) else {
                log("credits: dropped a queued purchase of unknown pack \(entry.packID)")
                dequeue(entry.receipt)
                continue
            }
            switch await settle(entry.receipt, for: pack) {
            case .credited(let creditsAdded, let newBalance):
                record(credits: newBalance)
                emit(.purchaseCredited(packID: pack.id, creditsAdded: creditsAdded))
            case .alreadyProcessed:
                emit(.purchaseCredited(packID: pack.id, creditsAdded: pack.credits))
            case .rejected(let error):
                log("credits: mako refused transaction \(entry.receipt.transactionID), dropping it (\(Self.describe(error)))")
            case .retry:
                break
            }
        }
    }

    /// Retries the queue in the background after a purchase stayed unconfirmed: after 30 s, 2 min, 10 min and 30 min, stopping when the queue is empty. A relaunch and every ``refresh()`` retry it as well.
    func scheduleReconcile() {
        guard reconciles, reconcileTask == nil, !isStopped else {
            return
        }
        reconcileTask = Task { [weak self] in
            await self?.reconcile()
        }
    }

    func reconcile() async {
        for delay in Self.reconcileDelays {
            guard !pending.isEmpty, (try? await sleep(.seconds(delay))) != nil else {
                break
            }
            await settlePending()
            _ = try? await readBalance()
        }
        reconcileTask = nil
    }

    private func enqueue(_ entry: PendingCredit) {
        pending.removeAll { $0.receipt.transactionID == entry.receipt.transactionID }
        pending.append(entry)
        persist()
    }

    private func dequeue(_ receipt: MidgarPurchaseReceipt) {
        guard pending.contains(where: { $0.receipt.transactionID == receipt.transactionID }) else {
            return
        }
        pending.removeAll { $0.receipt.transactionID == receipt.transactionID }
        persist()
    }

    private func dropExpired() {
        let cutoff = clock().addingTimeInterval(-Self.pendingLifetime)
        let kept = pending.filter { $0.queuedAt > cutoff }
        guard kept.count != pending.count else {
            return
        }
        log("credits: dropped \(pending.count - kept.count) queued purchases older than a week")
        pending = kept
        persist()
    }

    private func persist() {
        if !pendingStore.save(pending) {
            log("credits: the queue of unconfirmed purchases could not be written; a relaunch would lose it")
        }
    }

    /// A short, secret-free description for the log.
    static func describe(_ error: MidgarCreditsError) -> String {
        switch error {
        case .server(let status, let code, _):
            return "status \(status) \(code ?? "no code")"
        default:
            return String(describing: error)
        }
    }
}
