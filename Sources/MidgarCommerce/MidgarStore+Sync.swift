import Foundation
import MidgarCore

extension MidgarStore {
    /// Brings everything up to date: StoreKit's current entitlements, the queued reports, the ledger's answer. Call it when the app comes to the foreground (the store also observes that itself) and whenever a screen needs fresh entitlements. Calls that overlap share one run, and a call that arrives mid-run makes it run once more so nothing it saw is stale.
    public func refresh() async {
        if let running = syncTask {
            rerunRequested = true
            await running.value
            return
        }
        let task = Task { await self.performRefresh() }
        syncTask = task
        await task.value
    }

    private func performRefresh() async {
        repeat {
            rerunRequested = false
            await refreshLocal()
            await flushReports()
            await refreshLedger()
            publishIfChanged()
        } while rerunRequested
        syncTask = nil
        ensureRetryLoop()
    }

    /// Queues a signed transaction for the ledger and writes the queue to disk. A newer version of a queued transaction (a refund) replaces the older one.
    func enqueueReport(_ transaction: StoreTransaction) {
        state.pending.removeAll { $0.transactionID == transaction.id }
        state.pending.append(PendingReport(
            transactionID: transaction.id,
            productID: transaction.productID,
            signedTransaction: transaction.jws,
            queuedAt: clock()
        ))
        persist()
    }

    /// Sends the queue in order. A report leaves the queue when the ledger acknowledges it or refuses it for good; any other failure stops the run and leaves the rest for the retry.
    func flushReports() async {
        for report in state.pending {
            do {
                try await ledger.report(signedTransaction: report.signedTransaction)
                removeReport(report)
            } catch {
                if Self.isPermanentRefusal(error) {
                    log("commerce: the ledger refused the transaction of \(report.productID) (\(error.serverCode ?? "no code")), dropping it")
                    removeReport(report)
                } else {
                    log("commerce: the ledger report of \(report.productID) will be retried (\(Self.describe(error)))")
                    return
                }
            }
        }
    }

    /// The ledger will never accept these: the transaction belongs to another Midgar ID or app, does not verify, or is malformed. Everything else (offline, 5xx, rate limits, a missing token, an unexpected 4xx while the ledger is not deployed yet) is retried.
    static func isPermanentRefusal(_ error: MidgarHTTPError) -> Bool {
        guard case .server(let status, let code, _) = error, status == 400 || status == 403, let code else {
            return false
        }
        return ["account_mismatch", "bundle_mismatch", "unverifiable_payload", "invalid_request"].contains(code)
    }

    /// A short name for a failure, safe to log: never the server's message.
    static func describe(_ error: MidgarHTTPError) -> String {
        switch error {
        case .offline: return "offline"
        case .timeout: return "timeout"
        case .unauthorized: return "unauthorized"
        case .paymentRequired: return "paymentRequired"
        case .rateLimited: return "rateLimited"
        case .notFound: return "notFound"
        case .server(let status, _, _): return "http \(status)"
        case .decoding: return "decoding"
        case .invalidRequest: return "invalidRequest"
        case .cancelled: return "cancelled"
        case .tokenUnavailable: return "tokenUnavailable"
        }
    }

    private func removeReport(_ report: PendingReport) {
        state.pending.removeAll { $0 == report }
        persist()
    }

    func persist() {
        if !storage.save(state) {
            log("commerce: the commerce file could not be written, queued reports would be lost on relaunch")
        }
    }

    /// Fetches the ledger's entitlements for this Midgar ID and keeps them with the time. When the ledger cannot answer the last snapshot stays. A snapshot for another Midgar ID or another environment is discarded first, so it can never grant anything.
    func refreshLedger() async {
        let current: String
        do {
            current = try await identity.midgarId.lowercased()
        } catch {
            log("commerce: ledger refresh skipped, the Midgar ID is unavailable")
            return
        }
        let sandbox = await ledgerUsesSandbox()
        let environment = sandbox ? "Sandbox" : "Production"
        if let snapshot = state.ledger, snapshot.midgarId != current || snapshot.environment != environment {
            log("commerce: the Midgar ID or environment changed, ledger cache cleared")
            state.ledger = nil
            persist()
        }
        do {
            let response = try await ledger.entitlements(sandbox: sandbox)
            state.ledger = LedgerSnapshot(
                midgarId: response.midgarId.lowercased(),
                environment: environment,
                fetchedAt: clock(),
                entitlements: response.entitlements
            )
            persist()
        } catch {
            log("commerce: the ledger entitlements are unavailable (\(Self.describe(error))), using the cache and StoreKit")
        }
    }

    /// Sandbox and Xcode builds read the ledger's Sandbox environment; production reads Production. The environment is what StoreKit says about this install (`AppTransaction.environment`) unless a transaction already showed a non-production one.
    private func ledgerUsesSandbox() async -> Bool {
        if resolvedEnvironment == nil {
            resolvedEnvironment = await storeKit.appEnvironment()
        }
        return (resolvedEnvironment ?? .production) != .production
    }

    /// Starts the background retry when reports are waiting, and stops it when the queue is empty.
    func ensureRetryLoop() {
        guard !state.pending.isEmpty else {
            retryTask?.cancel()
            retryTask = nil
            return
        }
        guard retryTask == nil else {
            return
        }
        retryTask = Task { [weak self, sleep] in
            var attempt = 0
            while true {
                let delays = MidgarStore.retryDelays
                do {
                    try await sleep(.seconds(delays[min(attempt, delays.count - 1)]))
                } catch {
                    return
                }
                guard let store = self, await store.retryOnce() else {
                    return
                }
                attempt += 1
            }
        }
    }

    /// Runs a full refresh and reports whether reports are still waiting.
    private func retryOnce() async -> Bool {
        await refresh()
        return !state.pending.isEmpty
    }
}
