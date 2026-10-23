import Foundation
import Testing
import MidgarCommerce
@testable import MidgarCommerceUI

@Suite struct PaywallEventTests {
    @Test func aPurchasedResultNamesTheProduct() {
        let event = MidgarPaywallEvent.event(for: .success(.purchased), productID: "app.yearly")

        #expect(event == .purchased(productID: "app.yearly"))
    }

    @Test func pendingAndCancelledResultsMapOneToOne() {
        #expect(MidgarPaywallEvent.event(for: .success(.pending), productID: "p") == .pending)
        #expect(MidgarPaywallEvent.event(for: .success(.cancelled), productID: "p") == .cancelled)
    }

    @Test func anUnverifiedTransactionGetsItsOwnMessage() {
        let error = MidgarStoreError.unverifiedTransaction(productID: "app.yearly")

        let event = MidgarPaywallEvent.event(for: .failure(error), productID: "app.yearly")

        #expect(event == .failed(message: MidgarCommerceUIStrings.purchaseUnverified))
    }

    @Test func anyOtherFailureGetsTheGenericMessage() {
        struct Boom: Error {}

        #expect(MidgarPaywallEvent.event(for: .failure(Boom()), productID: "p") == .failed(message: MidgarCommerceUIStrings.purchaseFailed))
        #expect(MidgarPaywallEvent.event(for: .failure(MidgarStoreError.readOnly), productID: "p") == .failed(message: MidgarCommerceUIStrings.purchaseFailed))
    }

    @Test func onlyAPurchaseOrARestoreThatGaveSomethingIsASuccess() {
        #expect(MidgarPaywallEvent.purchased(productID: "p").isSuccess)
        #expect(MidgarPaywallEvent.restored.isSuccess)
        #expect(MidgarPaywallEvent.redeemed.isSuccess)
        #expect(MidgarPaywallEvent.pending.isSuccess == false)
        #expect(MidgarPaywallEvent.cancelled.isSuccess == false)
        #expect(MidgarPaywallEvent.nothingToRestore.isSuccess == false)
        #expect(MidgarPaywallEvent.failed(message: "m").isSuccess == false)
        #expect(MidgarPaywallEvent.restoreFailed(message: "m").isSuccess == false)
    }

    @Test func theRequiredLegalStringsExistInEnglish() {
        #expect(MidgarCommerceUIStrings.restorePurchases == "Restore Purchases")
        #expect(MidgarCommerceUIStrings.termsOfUse == "Terms of Use")
        #expect(MidgarCommerceUIStrings.privacyPolicy == "Privacy Policy")
        #expect(MidgarCommerceUIStrings.autoRenewTerms.contains("24 hours"))
        #expect(MidgarCommerceUIStrings.autoRenewTerms.contains("renew automatically"))
    }

    @Test func noPaywallStringContainsAnEmDash() {
        let strings = [
            MidgarCommerceUIStrings.autoRenewTerms, MidgarCommerceUIStrings.purchaseFailed, MidgarCommerceUIStrings.purchaseUnverified,
            MidgarCommerceUIStrings.purchasePending, MidgarCommerceUIStrings.restoreFailed, MidgarCommerceUIStrings.productsUnavailable
        ]

        #expect(strings.allSatisfy { !$0.contains("\u{2014}") })
    }

    @Test func linksAreKeptAsGiven() throws {
        let terms = try #require(URL(string: "https://example.com/terms"))
        let privacy = try #require(URL(string: "https://example.com/privacy"))

        let links = MidgarPaywallLinks(termsOfUse: terms, privacyPolicy: privacy)

        #expect(links.termsOfUse == terms)
        #expect(links.privacyPolicy == privacy)
    }
}
