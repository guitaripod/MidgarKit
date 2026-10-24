import Foundation
import Testing
import MidgarCredits
@testable import MidgarCommerceUI

@Suite @MainActor struct CreditStoreModelTests {
    private func model(_ source: FakeCreditSource, shortfall: Int? = nil) -> MidgarCreditStoreModel {
        MidgarCreditStoreModel(source: source, shortfall: shortfall)
    }

    @Test func loadingReadsTheBalanceAndThePacksTogether() async {
        let source = FakeCreditSource(balance: CreditFixtures.balance(128, allowances: CreditFixtures.allowances))
        let model = model(source)
        #expect(model.phase == .loading)

        await model.load()

        #expect(model.phase == .ready)
        #expect(model.balance?.credits == 128)
        #expect(model.balance?.allowances.count == 2)
        #expect(model.offers.map(\.id) == ["starter", "plus", "max"])
        #expect(!model.balanceUnavailable)
    }

    @Test func aBalanceThatCannotBeReadDoesNotHideThePacks() async {
        let source = FakeCreditSource(balance: nil)
        source.setRefreshFailure(MidgarCreditsError.offline)
        let model = model(source)

        await model.load()

        #expect(model.phase == .ready)
        #expect(model.balance == nil)
        #expect(model.balanceUnavailable)
    }

    @Test func aFailedRefreshFallsBackToTheBalanceTheWalletAlreadyKnows() async {
        let source = FakeCreditSource(balance: CreditFixtures.balance(40))
        source.setRefreshFailure(MidgarCreditsError.walletUnavailable)
        let model = model(source)

        await model.load()

        #expect(model.balance?.credits == 40)
        #expect(!model.balanceUnavailable)
    }

    @Test func noPacksAndAFailedPackLoadAreBothUnavailableAndTryingAgainRecovers() async {
        let source = FakeCreditSource(offers: [])
        let model = model(source)
        await model.load()
        #expect(model.phase == .unavailable)

        source.setOffersFailure(MidgarCreditsError.offline)
        await model.load()
        #expect(model.phase == .unavailable)

        source.setOffersFailure(nil)
        source.setOffers(CreditFixtures.offers)
        await model.retry()
        #expect(model.phase == .ready)
    }

    @Test func aFailedReloadKeepsThePacksAlreadyShown() async {
        let source = FakeCreditSource()
        let model = model(source)
        await model.load()

        source.setOffersFailure(MidgarCreditsError.offline)
        await model.load()

        #expect(model.phase == .ready)
        #expect(model.offers.count == 3)
    }

    @Test func aCreditedPurchaseUpdatesTheBalanceAndSaysSo() async {
        let source = FakeCreditSource()
        let model = model(source)
        await model.load()
        source.setBalance(CreditFixtures.balance(278))
        source.queue(.credited(packID: "starter", creditsAdded: 150, balance: 278))

        await model.buy(CreditFixtures.starter)

        #expect(source.purchased == ["starter"])
        #expect(model.balance?.credits == 278)
        #expect(model.notice == .credited(150))
        #expect(model.buyingPackID == nil)
        #expect(model.confirming.isEmpty)
    }

    @Test func aCreditedPurchaseWithAnUnreadBalanceUsesTheAnswersBalanceAndKeepsTheAllowances() async {
        let source = FakeCreditSource(balance: CreditFixtures.balance(128, allowances: CreditFixtures.allowances))
        let model = model(source)
        await model.load()
        source.setBalance(nil)
        source.queue(.credited(packID: "plus", creditsAdded: 700, balance: 828))

        await model.buy(CreditFixtures.plus)

        #expect(model.balance?.credits == 828)
        #expect(model.balance?.allowances == CreditFixtures.allowances)
    }

    @Test func aPendingCreditStaysUntilTheWalletReportsItCredited() async {
        let source = FakeCreditSource()
        let model = model(source)
        await model.load()
        source.setUnconfirmed(1)
        source.queue(.creditPending(packID: "plus", credits: 700))

        await model.buy(CreditFixtures.plus)
        #expect(model.confirming.count == 1)
        #expect(model.confirming.first?.credits == 700)
        #expect(model.notice == nil)

        await model.handle(.balanceChanged(CreditFixtures.balance(130)))
        #expect(model.confirming.count == 1)
        #expect(model.balance?.credits == 130)

        source.setUnconfirmed(0)
        await model.handle(.purchaseCredited(packID: "plus", creditsAdded: 700))
        #expect(model.confirming.isEmpty)
        #expect(model.notice == .credited(700))
    }

    @Test func aPurchaseLeftUnconfirmedByAnEarlierLaunchShowsAsAPendingRow() async {
        let source = FakeCreditSource()
        source.setUnconfirmed(2)
        let model = model(source)

        await model.load()

        #expect(model.confirming.count == 2)
        #expect(model.confirming.allSatisfy { $0.packID == nil })

        source.setUnconfirmed(0)
        await model.load()
        #expect(model.confirming.isEmpty)
    }

    @Test func theEventsStreamDrivesTheModelWhileItIsObserved() async {
        let source = FakeCreditSource()
        source.setUnconfirmed(1)
        let model = model(source)
        await model.load()
        let observing = Task { await model.observe() }

        source.setUnconfirmed(0)
        source.emit(.balanceChanged(CreditFixtures.balance(300)))
        source.emit(.purchaseCredited(packID: "starter", creditsAdded: 150))
        source.finishEvents()
        await observing.value

        #expect(model.balance?.credits == 300)
        #expect(model.confirming.isEmpty)
    }

    @Test func approvalIsAMessageAndCancellingShowsNothing() async {
        let source = FakeCreditSource()
        let model = model(source)
        await model.load()

        source.queue(.awaitingApproval)
        await model.buy(CreditFixtures.starter)
        #expect(model.notice == .awaitingApproval)

        source.queue(.cancelled)
        await model.buy(CreditFixtures.starter)
        #expect(model.notice == nil)
        #expect(model.confirming.isEmpty)
    }

    @Test(arguments: [
        (MidgarCreditsError.offline, MidgarCreditStoreFailure.offline),
        (MidgarCreditsError.walletUnavailable, .walletUnavailable),
        (MidgarCreditsError.unauthorized, .signIn),
        (MidgarCreditsError.identityUnavailable, .signIn),
        (MidgarCreditsError.rateLimited(retryAfter: 3), .rateLimited),
        (MidgarCreditsError.purchaseRejected(message: "no"), .rejected),
        (MidgarCreditsError.notConfigured(.noPacks), .unavailable),
        (MidgarCreditsError.insufficientCredits(balance: 1), .generic),
        (MidgarCreditsError.server(status: 500, code: nil, message: "x"), .generic),
        (MidgarCreditsError.invalidResponse, .generic)
    ])
    func eachErrorBecomesOneShortMessage(error: MidgarCreditsError, failure: MidgarCreditStoreFailure) async {
        let source = FakeCreditSource()
        let model = model(source)
        source.queue(failure: error)

        await model.buy(CreditFixtures.starter)

        #expect(model.notice == .failure(failure))
        #expect(!failure.message.isEmpty)
        #expect(model.buyingPackID == nil)
    }

    @Test func anErrorOfAnotherKindIsTheGenericMessageAndCancellationIsSilent() async {
        let source = FakeCreditSource()
        let model = model(source)

        source.queue(failure: FakeCreditSource.Unreachable())
        await model.buy(CreditFixtures.starter)
        #expect(model.notice == .failure(.generic))

        source.queue(failure: CancellationError())
        await model.buy(CreditFixtures.starter)
        #expect(model.notice == nil)
    }

    @Test func everyFailureHasItsOwnMessage() {
        let all: [MidgarCreditStoreFailure] = [.offline, .walletUnavailable, .signIn, .rateLimited, .rejected, .unavailable, .generic]
        #expect(Set(all.map(\.message)).count == all.count)
    }

    @Test func onlyOnePurchaseRunsAtATimeAndTheRowKnowsWhichOne() async {
        let source = FakeCreditSource()
        source.holdPurchases(true)
        let model = model(source)
        source.queue(.cancelled)

        let first = Task { await model.buy(CreditFixtures.plus) }
        await Task.yield()
        #expect(model.buyingPackID == "plus")
        #expect(model.isBuying)
        await waitUntilTheWalletIsAsked(source)

        await model.buy(CreditFixtures.starter)
        #expect(source.purchased == ["plus"])

        source.release()
        await first.value
        #expect(model.buyingPackID == nil)
    }

    private func waitUntilTheWalletIsAsked(_ source: FakeCreditSource) async {
        for _ in 0..<500 where source.purchased.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func theSmallestPackThatCoversTheShortfallIsTheOneMarked() async {
        let source = FakeCreditSource()
        let covered = model(source, shortfall: 200)
        await covered.load()
        #expect(covered.coveringPackID == "plus")

        let exact = model(source, shortfall: 150)
        await exact.load()
        #expect(exact.coveringPackID == "starter")

        let tooBig = model(source, shortfall: 9000)
        await tooBig.load()
        #expect(tooBig.coveringPackID == nil)
        #expect(tooBig.shortfall == 9000)
    }

    @Test func noShortfallOrAnEmptyOneMarksNothing() async {
        let source = FakeCreditSource()
        for shortfall in [nil, 0, -5] as [Int?] {
            let model = model(source, shortfall: shortfall)
            await model.load()
            #expect(model.shortfall == nil)
            #expect(model.coveringPackID == nil)
        }
    }

    @Test func theWalletActorConformsToTheSource() {
        func accepts<Source: MidgarCreditStoreSource>(_: Source.Type) {}
        accepts(MidgarCredits.self)
    }
}
