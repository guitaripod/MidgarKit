import MidgarCommerce
import MidgarCore
import MidgarUI
import Observation
import StoreKit
import SwiftUI

/// Runs the purchase sheet for a product with the options the store asks for. The view supplies it from the `\.purchase` environment action, a test from `Product.purchase(options:)`.
typealias MidgarPurchaseExecutor = @MainActor (Product, Set<Product.PurchaseOption>) async throws -> Product.PurchaseResult

/// The state behind a plan paywall: the plans StoreKit reports, the selected one, the purchase and restore in flight, and the toast and alert for outcomes.
///
/// A purchase goes through the ``MidgarStore``: its purchase options carry the Midgar ID as `appAccountToken`, and the result goes to ``MidgarStore/complete(_:)``, so verification, the report queue, finish, the signal and the entitlements are the same as for ``MidgarStore/purchase(_:)``.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
@MainActor @Observable
final class MidgarPlanPaywallModel {
    enum Phase: Equatable {
        case loading
        case ready
        case unavailable
    }

    let configuration: MidgarPlanPaywallConfiguration
    private(set) var phase = Phase.loading
    private(set) var catalog = MidgarPlanCatalog.empty
    private(set) var selection = MidgarPlanSelection()
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    var toast: MidgarToast?
    var failureMessage: String?
    var isPresentingOfferCodeSheet = false
    private(set) var successCount = 0
    private(set) var failureCount = 0

    @ObservationIgnored private let store: MidgarStore
    @ObservationIgnored private let trialPolicy: MidgarTrialPolicy
    @ObservationIgnored private let loadProduct: @Sendable (String) async throws -> Product?
    @ObservationIgnored private let onEvent: @MainActor (MidgarPaywallEvent) -> Void
    @ObservationIgnored private var entitlementsBeforeRedemption = 0

    init(
        configuration: MidgarPlanPaywallConfiguration,
        store: MidgarStore,
        trialPolicy: MidgarTrialPolicy,
        loadProduct: @escaping @Sendable (String) async throws -> Product? = { id in try await Product.products(for: [id]).first },
        onEvent: @escaping @MainActor (MidgarPaywallEvent) -> Void
    ) {
        self.configuration = configuration
        self.store = store
        self.trialPolicy = trialPolicy
        self.loadProduct = loadProduct
        self.onEvent = onEvent
    }

    var selectedID: String? {
        selection.selectedID
    }

    var selectedPlan: MidgarPlan? {
        catalog.plan(id: selectedID)
    }

    var isBusy: Bool {
        isPurchasing || isRestoring
    }

    /// Reads the plans, their prices and the offers StoreKit gives this customer. The selection survives a reload when its plan is still sold.
    func load() async {
        if catalog.plans.isEmpty {
            phase = .loading
        }
        do {
            let products = try await store.products().filter { configuration.productIDs.contains($0.id) }
            let terms = try await trialPolicy.terms(for: configuration.productIDs)
            let presentations = try await trialPolicy.presentations(for: configuration.productIDs)
            apply(MidgarPlanCatalog.make(
                products: products,
                terms: terms,
                presentations: presentations,
                order: configuration.productIDs,
                featuredID: configuration.featuredProductID,
                names: configuration.planNames,
                oneTimeNote: configuration.oneTimeNote
            ))
        } catch {
            MidgarLog.info("paywall: could not load plans: \(error)", category: .commerce)
            apply(.empty)
        }
    }

    func select(_ id: String) {
        selection.select(id, in: catalog, isBusy: isBusy)
    }

    /// Buys the selected plan with `execute`, then hands the result to the store.
    func purchase(using execute: MidgarPurchaseExecutor) async {
        guard let plan = selectedPlan, !isBusy else {
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            guard let product = try await loadProduct(plan.id) else {
                receive(.failed(message: MidgarCommerceUIStrings.purchaseFailed))
                return
            }
            let options = await store.purchaseOptions()
            let result = try await execute(product, options)
            let outcome = try await store.complete(result)
            receive(MidgarPaywallEvent.event(for: .success(outcome), productID: plan.id))
        } catch {
            receive(MidgarPaywallEvent.event(for: .failure(error), productID: plan.id))
        }
    }

    /// Asks the store to restore, then reports whether the customer has anything.
    func restore() async {
        guard !isBusy else {
            return
        }
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await store.restore()
            receive(await hasPurchasesAfterRestore() ? .restored : .nothingToRestore)
        } catch {
            receive(.restoreFailed(message: MidgarCommerceUIStrings.restoreFailed))
        }
    }

    private func hasPurchasesAfterRestore() async -> Bool {
        if await !store.entitlements.isEmpty {
            return true
        }
        return await configuration.ownsPurchaseOutsideStore?() ?? false
    }

    /// Opens the offer code sheet.
    func redeemCode() {
        guard !isBusy else {
            return
        }
        isPresentingOfferCodeSheet = true
        Task { entitlementsBeforeRedemption = await store.entitlements.count }
    }

    /// The sheet reports nothing about the code, so a redemption shows only as the store's entitlements growing a moment after the sheet is gone. Reports ``MidgarPaywallEvent/redeemed`` when they did.
    func offerCodeSheetFinished(_ result: Result<Void, any Error>) async {
        guard case .success = result else {
            MidgarLog.info("paywall: the offer code sheet failed", category: .commerce)
            return
        }
        for _ in 0..<Self.redemptionPollAttempts {
            if await store.entitlements.count > entitlementsBeforeRedemption {
                receive(.redeemed)
                return
            }
            try? await Task.sleep(for: Self.redemptionPollInterval)
        }
    }

    private static let redemptionPollAttempts = 8
    private static let redemptionPollInterval = Duration.milliseconds(500)

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
        case .failed(let message), .restoreFailed(let message):
            failureMessage = message
        case .redeemed:
            break
        }
        countFeedback(for: event)
        onEvent(event)
        if event.isSuccess {
            Task { await load() }
        }
    }

    private func countFeedback(for event: MidgarPaywallEvent) {
        switch event {
        case .purchased, .restored, .redeemed:
            successCount += 1
        case .failed, .restoreFailed:
            failureCount += 1
        case .pending, .cancelled, .nothingToRestore:
            break
        }
    }

    private func apply(_ catalog: MidgarPlanCatalog) {
        self.catalog = catalog
        phase = catalog.plans.isEmpty ? .unavailable : .ready
        selection.reconcile(with: catalog)
    }
}
