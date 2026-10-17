import Foundation
import MidgarCore
import Testing
@testable import MidgarPortal

private typealias Fixtures = PortalFixtures

private let host = Fixtures.app("psywave", accent: "#EC4899")
private let flaccyPhone = Fixtures.app("flaccy", bundle: "com.midgarcorp.flaccy", id: "1001")
private let flaccyMac = Fixtures.app("flaccy", bundle: "com.midgarcorp.flaccy.mac", id: "1002", platforms: [.mac])
private let embr = Fixtures.app("embr")
private let payDay = Fixtures.app("pay-day")
private let helia = Fixtures.app("helia")
private let psybeam = Fixtures.app("psybeam")
private let dreamEater = Fixtures.app("dream-eater")
private let ranked = [flaccyMac, flaccyPhone, embr, payDay, helia, psybeam, dreamEater, host]

private func build(
    slugs: [String]? = [],
    entitlements: [PortalEntitlement]? = [],
    catalog: [MidgarApp] = ranked,
    installed: Set<String> = [],
    platform: MidgarPlatform = .ios
) -> YourMidgarSection? {
    YourMidgarBuilder.build(
        snapshot: PortalAccountSnapshot(appSlugs: slugs, entitlements: entitlements),
        catalog: catalog,
        hostBundleID: host.bundleId,
        installed: installed,
        platform: platform,
        now: Fixtures.now
    )
}

private func slugs(_ apps: [YourApp]) -> [String] { apps.compactMap(\.app.slug) }

@Suite struct YourMidgarBuilderTests {
    @Test func listsTheAppsTheMidgarIDHasASessionInWithTheHostFirst() throws {
        let section = try #require(build(slugs: ["embr", "psywave", "pay-day"]))
        #expect(slugs(section.yours) == ["psywave", "embr", "pay-day"])
        #expect(section.yours.allSatisfy { $0.owned.isEmpty })
    }

    @Test func showsWhatThePersonOwnsInEachApp() throws {
        let section = try #require(build(
            slugs: ["psywave", "embr"],
            entitlements: [
                Fixtures.subscription("psywave", "pro", endsAfter: 30 * 86_400),
                Fixtures.lifetime("embr", "premium"),
            ]
        ))
        let psywave = try #require(section.yours.first { $0.app.slug == "psywave" })
        #expect(psywave.owned.map(\.name) == ["Pro"])
        guard case .subscription(let until, let inGrace) = psywave.owned[0].kind else {
            Issue.record("expected a subscription")
            return
        }
        #expect(until == Fixtures.now.addingTimeInterval(30 * 86_400))
        #expect(!inGrace)

        let embrApp = try #require(section.yours.first { $0.app.slug == "embr" })
        #expect(embrApp.owned == [OwnedItem(name: "Premium", kind: .lifetime)])
        #expect(embrApp.owned[0].detail == MidgarStrings.lifetime)
    }

    @Test func appsWithPurchasesComeBeforeAppsWithout() throws {
        let section = try #require(build(
            slugs: ["psywave", "embr", "pay-day", "helia"],
            entitlements: [Fixtures.lifetime("helia"), Fixtures.lifetime("pay-day")]
        ))
        #expect(slugs(section.yours) == ["psywave", "helia", "pay-day", "embr"])
    }

    @Test func aPurchaseInAnAppWithNoSessionStillListsTheApp() throws {
        let section = try #require(build(slugs: ["psywave"], entitlements: [Fixtures.lifetime("pay-day")]))
        #expect(Set(slugs(section.yours)) == ["psywave", "pay-day"])
        #expect(section.suggestions.map(\.slug).contains("pay-day") == false)
    }

    @Test func expiredSubscriptionsAreLeftOutAndGracePeriodsAreMarked() throws {
        let section = try #require(build(
            slugs: ["psywave", "embr"],
            entitlements: [
                Fixtures.subscription("psywave", "pro", endsAfter: -1),
                Fixtures.subscription("embr", "pro", endsAfter: 3 * 86_400, grace: true),
            ]
        ))
        #expect(section.yours.first { $0.app.slug == "psywave" }?.owned == [])
        let embrOwned = try #require(section.yours.first { $0.app.slug == "embr" }?.owned.first)
        guard case .subscription(_, let inGrace) = embrOwned.kind else {
            Issue.record("expected a subscription")
            return
        }
        #expect(inGrace)
        #expect(embrOwned.detail.isEmpty == false)
    }

    @Test func aNameAppearsOnceAsTheGrantThatLastsLongest() throws {
        let section = try #require(build(
            slugs: ["psywave"],
            entitlements: [
                Fixtures.subscription("psywave", "pro", endsAfter: 5 * 86_400),
                Fixtures.subscription("psywave", "pro", endsAfter: 40 * 86_400),
                Fixtures.lifetime("psywave", "pro"),
                Fixtures.subscription("psywave", "ultimate", endsAfter: 9 * 86_400),
            ]
        ))
        let owned = try #require(section.yours.first?.owned)
        #expect(owned.map(\.name) == ["Pro", "Ultimate"])
        #expect(owned[0].kind == .lifetime)
    }

    @Test func aGrantWithNoNameIsCalledUnlockedAndAnUnknownKindIsIgnored() throws {
        let section = try #require(build(
            slugs: ["psywave"],
            entitlements: [
                Fixtures.lifetime("psywave", nil),
                PortalEntitlement(app: "psywave", entitlement: "gift", kind: "consumable"),
            ]
        ))
        #expect(section.yours.first?.owned.map(\.name) == [MidgarStrings.unlocked])
        #expect(YourMidgarBuilder.displayName("pro") == "Pro")
        #expect(YourMidgarBuilder.displayName("  ") == MidgarStrings.unlocked)
    }

    @Test func aProductWithTwoStoreRecordsCountsOnceAsTheRecordForThisDevice() throws {
        let phone = try #require(build(slugs: ["psywave", "flaccy"], platform: .ios))
        #expect(phone.yours.first { $0.app.slug == "flaccy" }?.app.bundleId == "com.midgarcorp.flaccy")
        let mac = try #require(build(slugs: ["psywave", "flaccy"], platform: .mac))
        #expect(mac.yours.first { $0.app.slug == "flaccy" }?.app.bundleId == "com.midgarcorp.flaccy.mac")
        #expect(slugs(phone.yours).filter { $0 == "flaccy" }.count == 1)
    }

    @Test func suggestsTheRestOfTheCatalogInRankingOrderWithoutWhatThePersonHas() throws {
        let section = try #require(build(slugs: ["psywave", "embr"]))
        #expect(section.suggestions.map(\.slug) == ["flaccy", "pay-day", "helia"])
        #expect(section.suggestions.count == YourMidgarBuilder.suggestionLimit)
        #expect(section.suggestions.first?.bundleId == "com.midgarcorp.flaccy")
    }

    @Test func neverSuggestsTheHostAnInstalledAppOrOneThatDoesNotRunHere() throws {
        let section = try #require(build(
            slugs: ["psywave"],
            installed: ["com.example.pay-day"],
            platform: .ios
        ))
        #expect(section.suggestions.map(\.slug) == ["flaccy", "embr", "helia"])
        let tv = Fixtures.app("tv-only", platforms: [.tvos])
        let withTV = try #require(build(slugs: ["psywave"], catalog: [tv] + ranked))
        #expect(withTV.suggestions.map(\.slug).contains("tv-only") == false)
    }

    @Test func withNoMidgarIDOrOfflineThereIsNoSection() {
        #expect(build(slugs: nil, entitlements: nil) == nil)
    }

    @Test func oneAnswerIsEnoughForASection() throws {
        let slugsOnly = try #require(build(slugs: ["psywave", "embr"], entitlements: nil))
        #expect(slugs(slugsOnly.yours) == ["psywave", "embr"])
        #expect(slugsOnly.yours.allSatisfy { $0.owned.isEmpty })

        let ledgerOnly = try #require(build(slugs: nil, entitlements: [Fixtures.lifetime("embr")]))
        #expect(slugs(ledgerOnly.yours) == ["embr"])
    }

    @Test func aCatalogThatCannotBeMatchedToTheAccountBuildsNothing() {
        let noSlugs = ranked.map {
            MidgarApp(appId: $0.appId, bundleId: $0.bundleId, name: $0.name, platforms: $0.platforms)
        }
        #expect(build(slugs: ["psywave"], catalog: noSlugs) == nil)
        #expect(build(slugs: ["unreleased-app"]) == nil)
    }

    @Test func buildsFromTheRealBundledCatalog() throws {
        let catalog = CatalogService.bundledApps()
        let host = try #require(catalog.first { $0.slug == "psywave" })
        let section = try #require(YourMidgarBuilder.build(
            snapshot: PortalAccountSnapshot(appSlugs: ["psywave", "flaccy"], entitlements: [Fixtures.lifetime("flaccy")]),
            catalog: catalog,
            hostBundleID: host.bundleId,
            platform: .ios,
            now: Fixtures.now
        ))
        #expect(slugs(section.yours) == ["psywave", "flaccy"])
        #expect(section.yours.last?.app.bundleId == "com.midgarcorp.flaccy")
        #expect(section.suggestions.count == 3)
    }
}

@Suite struct PortalAccountTests {
    private func account(_ source: FakeAccountSource, clock: TestClock) -> PortalAccount {
        PortalAccount(source: source, now: { clock.now })
    }

    @Test func oneReadServesEveryCallerForTenMinutesThenReadsAgain() async {
        let source = FakeAccountSource(slugs: .success(["psywave"]), entitlements: .success([Fixtures.lifetime("psywave")]))
        let clock = TestClock(Fixtures.now)
        let account = account(source, clock: clock)

        let first = await account.snapshot()
        clock.advance(PortalAccount.timeToLive - 1)
        let second = await account.snapshot()
        #expect(first == second)
        #expect(source.calls == (1, 1))

        clock.advance(2)
        _ = await account.snapshot()
        #expect(source.calls == (2, 2))
    }

    @Test func callersThatArriveTogetherShareOneRead() async {
        let source = FakeAccountSource(slugs: .success(["psywave"]))
        let account = account(source, clock: TestClock(Fixtures.now))
        async let a = account.snapshot()
        async let b = account.snapshot()
        async let c = account.snapshot()
        _ = await (a, b, c)
        #expect(source.calls.slugs == 1)
    }

    @Test func aFailureIsUnknownAndIsNotCached() async {
        let source = FakeAccountSource(
            slugs: .failure(FakeAccountSource.Failure()),
            entitlements: .failure(FakeAccountSource.Failure())
        )
        let account = account(source, clock: TestClock(Fixtures.now))
        #expect(await account.snapshot().isUnknown)
        source.slugs = .success(["psywave"])
        source.entitlements = .success([])
        let recovered = await account.snapshot()
        #expect(recovered.appSlugs == ["psywave"])
        #expect(source.calls.slugs == 2)
    }

    @Test func halfAnAnswerIsUsedButNotCached() async {
        let source = FakeAccountSource(slugs: .success(["psywave"]), entitlements: .failure(FakeAccountSource.Failure()))
        let account = account(source, clock: TestClock(Fixtures.now))
        let half = await account.snapshot()
        #expect(half.appSlugs == ["psywave"])
        #expect(half.entitlements == nil)
        #expect(!half.isComplete)

        source.entitlements = .success([Fixtures.lifetime("psywave")])
        #expect(await account.snapshot().isComplete)
    }

    @Test func goingOfflineAfterAGoodReadReadsAsUnknownOnceItExpires() async {
        let source = FakeAccountSource(slugs: .success(["psywave"]), entitlements: .success([]))
        let clock = TestClock(Fixtures.now)
        let account = account(source, clock: clock)
        _ = await account.snapshot()

        source.slugs = .failure(FakeAccountSource.Failure())
        source.entitlements = .failure(FakeAccountSource.Failure())
        clock.advance(PortalAccount.timeToLive + 1)
        #expect(await account.snapshot().isUnknown)
    }

    @Test func invalidatingForcesTheNextReadToTheNetwork() async {
        let source = FakeAccountSource(slugs: .success([]), entitlements: .success([]))
        let account = account(source, clock: TestClock(Fixtures.now))
        _ = await account.snapshot()
        await account.invalidate()
        _ = await account.snapshot()
        #expect(source.calls.slugs == 2)
    }
}

@Suite(.serialized) struct LivePortalAccountSourceTests {
    private func source(token: String? = "token-1") -> LivePortalAccountSource {
        let configuration = MidgarHTTPConfiguration(
            baseURL: URL(string: "https://portal-account.test")!,
            appID: "psywave",
            session: PortalHTTPStub.session(),
            tokenProvider: { token }
        )
        return LivePortalAccountSource(http: MidgarHTTPClient(configuration: configuration))
    }

    @Test func readsTheIdentityServiceAndTheLedgerWithTheBearerToken() async throws {
        PortalHTTPStub.reset([
            "/v1/identity/me/apps": (200, #"{"apps":["embr","psywave"]}"#),
            "/v1/ledger/entitlements": (200, """
            {"midgarId":"0194f3a2-7b1c-4d2e-9a60-3c5e8f1b2d47","environment":"Production","serverTime":1800000000000,
             "entitlements":[
               {"app":"psywave","entitlement":"pro","productId":"com.example.pro.annual","kind":"subscription",
                "originalTransactionId":"1","expiresDate":1802592000000,"graceExpiresDate":null,"inGracePeriod":false,"ownership":"PURCHASED"},
               {"app":"embr","entitlement":null,"productId":"com.example.lifetime","kind":"non_consumable",
                "originalTransactionId":"2","expiresDate":null,"graceExpiresDate":null,"inGracePeriod":false,"ownership":"PURCHASED"}]}
            """),
        ])
        let source = source()

        #expect(try await source.appSlugs() == ["embr", "psywave"])
        let entitlements = try await source.entitlements()
        #expect(entitlements.map(\.app) == ["psywave", "embr"])
        #expect(entitlements[0].expiresDate == 1_802_592_000_000)
        #expect(entitlements[1].entitlement == nil)

        let seen = PortalHTTPStub.requests
        #expect(seen.map(\.path) == ["/v1/identity/me/apps", "/v1/ledger/entitlements"])
        #expect(seen.allSatisfy { $0.authorization == "Bearer token-1" && $0.appID == "psywave" })
    }

    @Test func aRefusalOrAMissingIDThrowsInsteadOfAnsweringEmpty() async {
        PortalHTTPStub.reset(["/v1/identity/me/apps": (401, #"{"error":{"code":"invalid_token","message":"no"}}"#)])
        await #expect(throws: (any Error).self) { try await source().appSlugs() }

        struct NoID: Error {}
        let configuration = MidgarHTTPConfiguration(
            baseURL: URL(string: "https://portal-account.test")!,
            appID: "psywave",
            session: PortalHTTPStub.session(),
            tokenProvider: { throw NoID() }
        )
        let noID = LivePortalAccountSource(http: MidgarHTTPClient(configuration: configuration))
        await #expect(throws: (any Error).self) { try await noID.entitlements() }
    }

    @Test func theSnapshotOfAFailingAccountIsUnknown() async {
        PortalHTTPStub.reset([:])
        let snapshot = await PortalAccount(source: source()).snapshot()
        #expect(snapshot.isUnknown)
    }
}

@MainActor @Suite struct PortalModelYourMidgarTests {
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return condition()
    }

    @Test func theModelBuildsTheSectionFromTheAccountAndHidesItWhenTheAccountIsGone() async throws {
        let source = FakeAccountSource(
            slugs: .success(["psywave", "flaccy"]),
            entitlements: .success([Fixtures.lifetime("flaccy")])
        )
        let account = PortalAccount(source: source)
        let model = PortalModel(
            config: MidgarConfig(enableTelemetry: false),
            hostBundleID: "com.marcusziade.psywave",
            account: account
        )
        model.start()
        defer { model.stop() }

        let appeared = await eventually { model.yourMidgar != nil }
        #expect(appeared)
        let section = try #require(model.yourMidgar)
        #expect(section.yours.map(\.app.slug) == ["psywave", "flaccy"])
        #expect(section.yours.last?.owned.first?.name == "Pro")

        model.showYourMidgar()
        #expect(model.showsYourMidgar)
        model.hideYourMidgar()
        #expect(!model.showsYourMidgar)
    }

    @Test func anAppTheMidgarIDHasCountsInTheHeaderAndTheCardOffersOpenNeverGet() async throws {
        let plain = PortalModel(config: MidgarConfig(enableTelemetry: false), hostBundleID: "com.marcusziade.psywave")
        plain.start()
        defer { plain.stop() }
        let candidate = try #require(plain.ranked.first { $0.runsOnThisDevice && !plain.isHost($0) && !plain.isInstalled($0) && $0.slug != nil })
        #expect(!plain.isOwned(candidate))
        #expect(plain.buttonTitle(for: candidate) == candidate.priceLabel)
        let before = plain.installedCount

        let source = FakeAccountSource(slugs: .success(["psywave", try #require(candidate.slug)]), entitlements: .success([]))
        let model = PortalModel(
            config: MidgarConfig(enableTelemetry: false),
            hostBundleID: "com.marcusziade.psywave",
            account: PortalAccount(source: source)
        )
        model.start()
        defer { model.stop() }
        let appeared = await eventually { model.yourMidgar != nil }
        #expect(appeared)

        #expect(model.isOwned(candidate))
        #expect(model.buttonTitle(for: candidate) == MidgarStrings.open)
        if case .showProduct = model.action(for: candidate) {} else { Issue.record("an owned app that is not installed opens its store page") }
        #expect(model.installedCount == before + 1)
    }

    @Test func withoutAnAccountThePortalHasNoSectionAndNothingToOpen() async {
        let model = PortalModel(config: MidgarConfig(enableTelemetry: false), hostBundleID: "com.marcusziade.psywave")
        model.start()
        defer { model.stop() }
        try? await Task.sleep(for: .milliseconds(150))
        #expect(model.yourMidgar == nil)
        model.showYourMidgar()
        #expect(!model.showsYourMidgar)
    }

    @Test func anOfflineAccountLeavesThePortalAsItWas() async {
        let source = FakeAccountSource(
            slugs: .failure(FakeAccountSource.Failure()),
            entitlements: .failure(FakeAccountSource.Failure())
        )
        let model = PortalModel(
            config: MidgarConfig(enableTelemetry: false),
            hostBundleID: "com.marcusziade.psywave",
            account: PortalAccount(source: source)
        )
        model.start()
        defer { model.stop() }
        let asked = await eventually { source.calls.slugs > 0 }
        #expect(asked)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(model.yourMidgar == nil)
        #expect(!model.ranked.isEmpty)
    }
}
