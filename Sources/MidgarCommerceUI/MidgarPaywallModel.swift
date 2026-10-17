import MidgarCommerce
import MidgarCore
import MidgarUI
import Observation
import SwiftUI

/// What one plan costs, in the words the paywall footer states next to the product's name.
struct MidgarPlanLine: Identifiable, Equatable {
    let id: String
    let name: String
    let text: String
}

/// The state behind a paywall: the plan lines the footer states, the toast and alert for outcomes, and restore.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
@MainActor @Observable
final class MidgarPaywallModel {
    let store: MidgarStore
    private(set) var planLines: [MidgarPlanLine] = []
    private(set) var isRestoring = false
    var toast: MidgarToast?
    var failureMessage: String?

    @ObservationIgnored private let trialPolicy: MidgarTrialPolicy
    @ObservationIgnored private let groupID: String?
    @ObservationIgnored private let productIDs: Set<String>?
    @ObservationIgnored private let onEvent: @MainActor (MidgarPaywallEvent) -> Void

    /// - Parameters:
    ///   - groupID: The subscription group whose plans the footer states, or nil for no group filter.
    ///   - productIDs: The products the footer may state, or nil for every product of the store. A storefront passes the products it sells so it never states plans it does not show.
    init(
        store: MidgarStore,
        trialPolicy: MidgarTrialPolicy,
        groupID: String?,
        productIDs: Set<String>? = nil,
        onEvent: @escaping @MainActor (MidgarPaywallEvent) -> Void
    ) {
        self.store = store
        self.trialPolicy = trialPolicy
        self.groupID = groupID
        self.productIDs = productIDs
        self.onEvent = onEvent
    }

    /// Reads the plans and the offers StoreKit gives this customer. On failure the footer states no plans and the StoreKit views show their own unavailable state.
    func loadPlans() async {
        do {
            let products = try await store.products()
            let ids = products.map(\.id)
            let terms = try await trialPolicy.terms(for: ids)
            let presentations = try await trialPolicy.presentations(for: ids)
            let names = Dictionary(products.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
            planLines = terms
                .filter { (groupID == nil || $0.groupID == groupID) && (productIDs?.contains($0.productID) ?? true) }
                .map { terms in
                    MidgarPlanLine(
                        id: terms.productID,
                        name: names[terms.productID] ?? terms.productID,
                        text: presentations[terms.productID]?.summary ?? terms.renewalDescription()
                    )
                }
        } catch {
            MidgarLog.info("paywall: could not load plans: \(error)", category: .commerce)
            planLines = []
        }
    }

    /// Shows the outcome, tells the app, and reads the plans again after anything that can change offer eligibility.
    func receive(_ event: MidgarPaywallEvent) {
        switch event {
        case .purchased, .cancelled:
            break
        case .pending:
            toast = MidgarToast(MidgarCommerceUIStrings.purchasePending, style: .info, duration: 5)
        case .restored:
            toast = .success(MidgarCommerceUIStrings.purchasesRestored)
        case .nothingToRestore:
            toast = MidgarToast(MidgarCommerceUIStrings.nothingToRestore, style: .info)
        case .failed(let message):
            failureMessage = message
        }
        onEvent(event)
        if event.isSuccess {
            Task { await loadPlans() }
        }
    }

    /// Asks the store to restore, then reports whether the customer has anything.
    func restore() async {
        guard !isRestoring else {
            return
        }
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await store.restore()
            let hasPurchases = await !store.entitlements.isEmpty
            receive(hasPurchases ? .restored : .nothingToRestore)
        } catch {
            receive(.failed(message: MidgarCommerceUIStrings.restoreFailed))
        }
    }
}
