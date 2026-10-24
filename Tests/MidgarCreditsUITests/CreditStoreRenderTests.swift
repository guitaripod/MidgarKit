#if os(macOS) || os(iOS)
import SwiftUI
import Testing
import MidgarCredits
@testable import MidgarCreditsUI

@Suite @MainActor struct CreditStoreRenderTests {
    private var platform: String {
        #if os(macOS)
        "mac"
        #else
        "ios"
        #endif
    }

    private let titles = ["chat.haiku": "Quick chat", "reading.v2": "Readings"]

    private func check(_ name: String, size: CGSize, typeSize: DynamicTypeSize? = nil, _ model: MidgarCreditStoreModel) throws {
        let view = MidgarCreditStoreView(model: model, allowanceTitles: titles)
        let light = try renderPaywallPart(view.environment(\.dynamicTypeSize, typeSize ?? .large), size: size, dark: false)
        let dark = try renderPaywallPart(view.environment(\.dynamicTypeSize, typeSize ?? .large), size: size, dark: true)
        try PaywallSnapshotSink.write(light, name: "\(platform)-credit-store-\(name)-light.png")
        try PaywallSnapshotSink.write(dark, name: "\(platform)-credit-store-\(name)-dark.png")
        #expect(distinctColors(in: light) > 2, "\(name) light rendered blank")
        #expect(distinctColors(in: dark) > 2, "\(name) dark rendered blank")
        #expect(light != dark, "\(name) looks the same in light and dark")
    }

    private func loaded(
        _ source: FakeCreditSource = FakeCreditSource(balance: CreditFixtures.balance(128, allowances: CreditFixtures.allowances)),
        shortfall: Int? = nil
    ) async -> (MidgarCreditStoreModel, FakeCreditSource) {
        let model = MidgarCreditStoreModel(source: source, shortfall: shortfall)
        await model.load()
        return (model, source)
    }

    @Test func theStoreShowsTheBalanceTheAllowancesAndEveryPack() async throws {
        let (model, _) = await loaded()
        try check("ready", size: CGSize(width: 390, height: 780), model)
    }

    @Test func theStoreWithoutAllowancesShowsOnlyTheBalanceAndThePacks() async throws {
        let (model, _) = await loaded(FakeCreditSource(balance: CreditFixtures.balance(1)))
        try check("no-allowances", size: CGSize(width: 390, height: 600), model)
    }

    @Test func aShortfallIsBannerAndTheSmallestCoveringPackIsMarked() async throws {
        let (model, _) = await loaded(shortfall: 200)
        try check("shortfall", size: CGSize(width: 390, height: 900), model)
    }

    @Test func aPurchaseInProgressTurnsItsButtonIntoASpinnerAndDisablesTheOthers() async throws {
        let (model, source) = await loaded()
        source.holdPurchases(true)
        let purchase = Task { await model.buy(CreditFixtures.plus) }
        for _ in 0..<500 where model.buyingPackID == nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        try check("buying", size: CGSize(width: 390, height: 780), model)

        source.release()
        await purchase.value
    }

    @Test func aPendingCreditIsARowThatStaysAndTheCreditedMessageComesWithTheBalance() async throws {
        let (model, source) = await loaded()
        source.setUnconfirmed(1)
        source.queue(.creditPending(packID: "plus", credits: 700))
        await model.buy(CreditFixtures.plus)
        try check("pending", size: CGSize(width: 390, height: 860), model)

        source.setBalance(CreditFixtures.balance(828))
        source.setUnconfirmed(0)
        await model.handle(.balanceChanged(CreditFixtures.balance(828, allowances: CreditFixtures.allowances)))
        await model.handle(.purchaseCredited(packID: "plus", creditsAdded: 700))
        try check("credited", size: CGSize(width: 390, height: 780), model)
    }

    @Test func approvalAndErrorsAreOneMessageRowAboveThePacks() async throws {
        let (model, source) = await loaded()
        source.queue(.awaitingApproval)
        await model.buy(CreditFixtures.starter)
        try check("approval", size: CGSize(width: 390, height: 780), model)

        source.queue(failure: MidgarCreditsError.walletUnavailable)
        await model.buy(CreditFixtures.starter)
        try check("failure", size: CGSize(width: 390, height: 780), model)
    }

    @Test func noPacksIsAnExplanationWithATryAgainButton() async throws {
        let (model, _) = await loaded(FakeCreditSource(offers: []))
        try check("unavailable", size: CGSize(width: 390, height: 640), model)
    }

    @Test func theLoadingStateShowsASpinnerWhereThePacksWillBe() throws {
        let source = FakeCreditSource()
        try check("loading", size: CGSize(width: 390, height: 520), MidgarCreditStoreModel(source: source, shortfall: nil))
    }

    @Test func anAccessibilityTextSizeStacksEveryRowAndNothingClips() async throws {
        let (model, source) = await loaded(shortfall: 200)
        source.setUnconfirmed(1)
        source.queue(.creditPending(packID: "plus", credits: 700))
        await model.buy(CreditFixtures.plus)
        try check("accessibility5", size: CGSize(width: 390, height: 3800), typeSize: .accessibility5, model)
    }

    @Test func aSmallPhoneAtALargeTextSizeStillFitsTheColumn() async throws {
        let (model, _) = await loaded()
        try check("small-xxxlarge", size: CGSize(width: 320, height: 1500), typeSize: .xxxLarge, model)
    }

    @Test func theNarrowAndWideWindowsOfAnIPhoneDuoAndAnIPadKeepOneCenteredColumn() async throws {
        let (model, _) = await loaded(shortfall: 200)
        try check("duo-narrow-466x678", size: CGSize(width: 466, height: 678), model)
        try check("duo-tall-669x951", size: CGSize(width: 669, height: 951), model)
        try check("duo-wide-951x669", size: CGSize(width: 951, height: 669), model)
        try check("ipad-820x1180", size: CGSize(width: 820, height: 1180), model)
    }
}
#endif
