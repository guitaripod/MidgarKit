import Foundation
import Testing
@testable import MidgarUI

@Suite struct OnboardingStoreTests {
    @Test func startsIncompleteAndRemembersCompletion() {
        let store = MidgarOnboardingStore(appID: "app.one", version: 1, defaults: makeDefaults())
        #expect(store.shouldPresent)
        store.markCompleted()
        #expect(store.hasCompleted)
        #expect(!store.shouldPresent)
    }

    @Test func keyCombinesAppAndVersion() {
        let store = MidgarOnboardingStore(appID: "app.one", version: 3, defaults: makeDefaults())
        #expect(store.key == "midgar.onboarding.app.one.v3")
    }

    @Test func raisingTheVersionShowsOnboardingAgain() {
        let defaults = makeDefaults()
        MidgarOnboardingStore(appID: "app.one", version: 1, defaults: defaults).markCompleted()
        #expect(MidgarOnboardingStore(appID: "app.one", version: 1, defaults: defaults).hasCompleted)
        #expect(MidgarOnboardingStore(appID: "app.one", version: 2, defaults: defaults).shouldPresent)
    }

    @Test func appsDoNotShareCompletion() {
        let defaults = makeDefaults()
        MidgarOnboardingStore(appID: "app.one", version: 1, defaults: defaults).markCompleted()
        #expect(MidgarOnboardingStore(appID: "app.two", version: 1, defaults: defaults).shouldPresent)
    }

    @Test func showAgainClearsOnlyThisVersion() {
        let defaults = makeDefaults()
        let first = MidgarOnboardingStore(appID: "app.one", version: 1, defaults: defaults)
        let second = MidgarOnboardingStore(appID: "app.one", version: 2, defaults: defaults)
        first.markCompleted()
        second.markCompleted()
        second.showAgain()
        #expect(second.shouldPresent)
        #expect(first.hasCompleted)
    }
}

@Suite struct WhatsNewStoreTests {
    @Test func firstInstallShowsNothingByDefault() {
        let store = MidgarWhatsNewStore(appID: "app.one", defaults: makeDefaults())
        #expect(!store.shouldShow(for: "1.0"))
        #expect(store.shouldShow(for: "1.0", showOnFirstInstall: true))
    }

    @Test func recordingTheInstallMakesTheNextUpdateDue() {
        let store = MidgarWhatsNewStore(appID: "app.one", defaults: makeDefaults())
        store.recordInstallIfNeeded(version: "1.0")
        #expect(store.lastShownVersion == "1.0")
        #expect(!store.shouldShow(for: "1.0"))
        #expect(store.shouldShow(for: "1.1"))
    }

    @Test func recordingTheInstallDoesNotOverwriteAShownVersion() {
        let store = MidgarWhatsNewStore(appID: "app.one", defaults: makeDefaults())
        store.markShown("1.2")
        store.recordInstallIfNeeded(version: "1.4")
        #expect(store.lastShownVersion == "1.2")
    }

    @Test func showsOncePerVersion() {
        let store = MidgarWhatsNewStore(appID: "app.one", defaults: makeDefaults())
        store.markShown("1.0")
        #expect(store.shouldShow(for: "1.1"))
        store.markShown("1.1")
        #expect(!store.shouldShow(for: "1.1"))
    }

    @Test func comparesVersionsNumerically() {
        let store = MidgarWhatsNewStore(appID: "app.one", defaults: makeDefaults())
        store.markShown("1.9")
        #expect(store.shouldShow(for: "1.10"))
        #expect(!store.shouldShow(for: "1.8"))
    }

    @Test func appsKeepSeparateVersions() {
        let defaults = makeDefaults()
        MidgarWhatsNewStore(appID: "app.one", defaults: defaults).markShown("2.0")
        #expect(MidgarWhatsNewStore(appID: "app.two", defaults: defaults).lastShownVersion == nil)
    }

    @Test func resetForgetsTheVersion() {
        let store = MidgarWhatsNewStore(appID: "app.one", defaults: makeDefaults())
        store.markShown("1.0")
        store.reset()
        #expect(store.lastShownVersion == nil)
    }
}

@Suite struct OnboardingProgressTests {
    @Test func advancesToTheLastPageAndStops() {
        var progress = MidgarOnboardingProgress(count: 3)
        #expect(progress.isFirst && !progress.isLast)
        let first = progress.advance()
        let second = progress.advance()
        #expect(first && second)
        #expect(progress.isLast)
        let third = progress.advance()
        #expect(!third)
        #expect(progress.index == 2)
    }

    @Test func goesBackToTheFirstPageAndStops() {
        var progress = MidgarOnboardingProgress(count: 3, index: 2)
        let first = progress.goBack()
        let second = progress.goBack()
        let third = progress.goBack()
        #expect(first && second && !third)
        #expect(progress.index == 0)
    }

    @Test func clampsAnOutOfRangeStart() {
        #expect(MidgarOnboardingProgress(count: 2, index: 9).index == 1)
        #expect(MidgarOnboardingProgress(count: 2, index: -4).index == 0)
    }

    @Test func emptyPagerIsFirstAndLast() {
        let progress = MidgarOnboardingProgress(count: 0)
        #expect(progress.isFirst && progress.isLast)
    }
}
