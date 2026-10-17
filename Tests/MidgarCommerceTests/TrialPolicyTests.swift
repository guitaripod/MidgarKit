import Foundation
import Testing
@testable import MidgarCommerce

/// A subscription catalog the test controls. `lock` guards every field.
final class FakeSubscriptionSource: MidgarSubscriptionSource, @unchecked Sendable {
    struct Unavailable: Error {}

    private let lock = NSLock()
    private var catalog: [MidgarSubscriptionTerms] = []
    private var eligibility: [String: Bool] = [:]
    private var eligibilityCalls: [String] = []
    private var fails = false

    func serve(_ terms: [MidgarSubscriptionTerms], eligible: [String: Bool]) {
        lock.withLock {
            catalog = terms
            eligibility = eligible
        }
    }

    func failProducts() { lock.withLock { fails = true } }

    var eligibilityQueries: [String] { lock.withLock { eligibilityCalls } }

    func terms(for productIDs: [String]) async throws -> [MidgarSubscriptionTerms] {
        try lock.withLock {
            if fails { throw Unavailable() }
            return productIDs.compactMap { id in catalog.first { $0.productID == id } }
        }
    }

    func isEligibleForIntroOffer(groupID: String) async -> Bool {
        lock.withLock {
            eligibilityCalls.append(groupID)
            return eligibility[groupID] ?? false
        }
    }
}

enum TrialFixtures {
    static let english = Locale(identifier: "en_US")

    static func yearly(offer: MidgarIntroOffer? = MidgarIntroOffer(
        kind: .freeTrial, period: MidgarBillingPeriod(value: 1, unit: .week), periodCount: 1, displayPrice: "$0.00"
    )) -> MidgarSubscriptionTerms {
        MidgarSubscriptionTerms(
            productID: "app.yearly", groupID: "pro", displayPrice: "$39.99",
            period: MidgarBillingPeriod(value: 1, unit: .year), introOffer: offer
        )
    }

    static func monthly(offer: MidgarIntroOffer? = nil) -> MidgarSubscriptionTerms {
        MidgarSubscriptionTerms(
            productID: "app.monthly", groupID: "pro", displayPrice: "$4.99",
            period: MidgarBillingPeriod(value: 1, unit: .month), introOffer: offer
        )
    }

    static func policy(_ source: FakeSubscriptionSource) -> MidgarTrialPolicy {
        MidgarTrialPolicy(source: source, locale: english)
    }
}

@Suite struct TrialPolicyTests {
    @Test func aFreeTrialIsPresentedWhenStoreKitSaysTheCustomerIsEligible() async throws {
        let source = FakeSubscriptionSource()
        source.serve([TrialFixtures.yearly()], eligible: ["pro": true])

        let presentation = try await TrialFixtures.policy(source).presentation(for: "app.yearly")

        #expect(presentation?.summary == "1 week free, then $39.99/year")
        #expect(presentation?.badge == "1 week free")
        #expect(presentation?.renewalDescription == "$39.99/year")
        #expect(presentation?.isFreeTrial == true)
    }

    @Test func nothingIsPresentedWhenStoreKitSaysTheCustomerIsNotEligible() async throws {
        let source = FakeSubscriptionSource()
        source.serve([TrialFixtures.yearly()], eligible: ["pro": false])

        let presentation = try await TrialFixtures.policy(source).presentation(for: "app.yearly")

        #expect(presentation == nil)
    }

    @Test func eligibilityIsTheOnlyGateEvenForAnOfferTheAppHasUsedBefore() async throws {
        let source = FakeSubscriptionSource()
        source.serve([TrialFixtures.yearly()], eligible: ["pro": true])
        let policy = TrialFixtures.policy(source)

        let first = try await policy.presentation(for: "app.yearly")
        let second = try await policy.presentation(for: "app.yearly")

        #expect(first == second)
        #expect(first != nil)
    }

    @Test func eligibilityIsReadAgainOnEveryCallBecauseItChangesAfterAPurchase() async throws {
        let source = FakeSubscriptionSource()
        source.serve([TrialFixtures.yearly()], eligible: ["pro": true])
        let policy = TrialFixtures.policy(source)
        _ = try await policy.presentation(for: "app.yearly")

        source.serve([TrialFixtures.yearly()], eligible: ["pro": false])
        let after = try await policy.presentation(for: "app.yearly")

        #expect(after == nil)
        #expect(source.eligibilityQueries == ["pro", "pro"])
    }

    @Test func aProductWithoutAnOfferHasNoPresentationAndCostsNoEligibilityQuery() async throws {
        let source = FakeSubscriptionSource()
        source.serve([TrialFixtures.monthly()], eligible: ["pro": true])

        let found = try await TrialFixtures.policy(source).presentations(for: ["app.monthly"])

        #expect(found.isEmpty)
        #expect(source.eligibilityQueries.isEmpty)
    }

    @Test func eligibilityIsAskedOncePerGroupNotOncePerProduct() async throws {
        let source = FakeSubscriptionSource()
        let offer = MidgarIntroOffer(kind: .freeTrial, period: MidgarBillingPeriod(value: 3, unit: .day), periodCount: 1, displayPrice: "$0.00")
        source.serve([TrialFixtures.yearly(), TrialFixtures.monthly(offer: offer)], eligible: ["pro": true])

        let found = try await TrialFixtures.policy(source).presentations(for: ["app.yearly", "app.monthly"])

        #expect(found["app.yearly"]?.summary == "1 week free, then $39.99/year")
        #expect(found["app.monthly"]?.summary == "3 days free, then $4.99/month")
        #expect(source.eligibilityQueries == ["pro"])
    }

    @Test func aPayAsYouGoOfferNamesItsPriceAndLength() async throws {
        let offer = MidgarIntroOffer(kind: .payAsYouGo, period: MidgarBillingPeriod(value: 1, unit: .month), periodCount: 3, displayPrice: "$0.99")
        let source = FakeSubscriptionSource()
        source.serve([TrialFixtures.monthly(offer: offer)], eligible: ["pro": true])

        let presentation = try await TrialFixtures.policy(source).presentation(for: "app.monthly")

        #expect(presentation?.summary == "$0.99/month for 3 months, then $4.99/month")
        #expect(presentation?.badge == nil)
        #expect(presentation?.isFreeTrial == false)
    }

    @Test func aPayUpFrontOfferNamesItsPriceOnceAndItsLength() async throws {
        let offer = MidgarIntroOffer(kind: .payUpFront, period: MidgarBillingPeriod(value: 1, unit: .year), periodCount: 1, displayPrice: "$9.99")
        let source = FakeSubscriptionSource()
        source.serve([TrialFixtures.yearly(offer: offer)], eligible: ["pro": true])

        let presentation = try await TrialFixtures.policy(source).presentation(for: "app.yearly")

        #expect(presentation?.summary == "$9.99 for 1 year, then $39.99/year")
    }

    @Test func aRenewalPeriodLongerThanOneUnitIsWrittenAsEvery() async throws {
        let quarterly = MidgarSubscriptionTerms(
            productID: "app.quarterly", groupID: "pro", displayPrice: "$12.99",
            period: MidgarBillingPeriod(value: 3, unit: .month), introOffer: nil
        )

        #expect(quarterly.renewalDescription(locale: TrialFixtures.english) == "$12.99 every 3 months")
        #expect(TrialFixtures.yearly().renewalDescription(locale: TrialFixtures.english) == "$39.99/year")
    }

    @Test func aFreeTrialLastsTheOfferPeriodTimesItsCount() async throws {
        let offer = MidgarIntroOffer(kind: .freeTrial, period: MidgarBillingPeriod(value: 1, unit: .week), periodCount: 2, displayPrice: "$0.00")
        let source = FakeSubscriptionSource()
        source.serve([TrialFixtures.yearly(offer: offer)], eligible: ["pro": true])

        let presentation = try await TrialFixtures.policy(source).presentation(for: "app.yearly")

        #expect(offer.totalDuration == MidgarBillingPeriod(value: 2, unit: .week))
        #expect(presentation?.summary == "2 weeks free, then $39.99/year")
    }

    @Test func aProductStoreKitDoesNotSellIsAbsent() async throws {
        let source = FakeSubscriptionSource()
        source.serve([TrialFixtures.yearly()], eligible: ["pro": true])

        let found = try await TrialFixtures.policy(source).presentations(for: ["app.unknown", "app.yearly"])

        #expect(Set(found.keys) == ["app.yearly"])
    }

    @Test func termsComeBackInTheOrderAsked() async throws {
        let source = FakeSubscriptionSource()
        source.serve([TrialFixtures.yearly(), TrialFixtures.monthly()], eligible: [:])

        let terms = try await TrialFixtures.policy(source).terms(for: ["app.monthly", "app.yearly"])

        #expect(terms.map(\.productID) == ["app.monthly", "app.yearly"])
    }

    @Test func aStoreKitFailureReachesTheCaller() async throws {
        let source = FakeSubscriptionSource()
        source.failProducts()

        await #expect(throws: FakeSubscriptionSource.Unavailable.self) {
            _ = try await TrialFixtures.policy(source).presentations(for: ["app.yearly"])
        }
    }

    @Test func groupEligibilityIsStoreKitsAnswerUnchanged() async {
        let source = FakeSubscriptionSource()
        source.serve([], eligible: ["pro": true, "plus": false])
        let policy = TrialFixtures.policy(source)

        #expect(await policy.isEligibleForIntroOffer(inGroup: "pro"))
        #expect(await policy.isEligibleForIntroOffer(inGroup: "plus") == false)
    }
}
