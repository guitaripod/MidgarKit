import Testing
@testable import MidgarUI

@Suite @MainActor struct HapticsTests {
    @Test func forwardsEveryEventToTheSupportedPlayer() {
        let player = RecordingPlayer()
        let haptics = MidgarHaptics(player: player)
        haptics.success()
        haptics.warning()
        haptics.error()
        haptics.selection()
        haptics.impact(.heavy)
        haptics.impact()
        #expect(player.events == [.success, .warning, .error, .selection, .impact(.heavy), .impact(.medium)])
    }

    @Test func disabledHapticsPlayNothing() {
        let player = RecordingPlayer()
        let haptics = MidgarHaptics(player: player)
        haptics.isEnabled = false
        haptics.success()
        haptics.prepare()
        #expect(player.events.isEmpty)
        #expect(player.prepared == 0)
    }

    @Test func unsupportedPlatformsAreANoOp() {
        let player = RecordingPlayer()
        player.isSupported = false
        let haptics = MidgarHaptics(player: player)
        haptics.play(.error)
        haptics.prepare()
        #expect(!haptics.isSupported)
        #expect(player.events.isEmpty)
        #expect(player.prepared == 0)
    }

    @Test func silentPlayerNeverPlays() {
        let haptics = MidgarHaptics(player: MidgarSilentHapticPlayer())
        #expect(!haptics.isSupported)
        for style in MidgarImpactStyle.allCases { haptics.impact(style) }
        haptics.success()
    }

    @Test func liveSharedInstanceDoesNotCrashWithoutADevice() {
        MidgarHaptics.shared.prepare()
        MidgarHaptics.shared.selection()
        MidgarHaptics.shared.impact(.soft)
    }

    @Test func preparesASupportedPlayer() {
        let player = RecordingPlayer()
        MidgarHaptics(player: player).prepare()
        #expect(player.prepared == 1)
    }
}

@Suite struct ToastTests {
    @Test func defaultsFollowTheStyle() {
        let toast = MidgarToast("Saved", style: .success)
        #expect(toast.systemImage == MidgarToast.Style.success.systemImage)
        #expect(toast.duration == MidgarToast.defaultDuration)
    }

    @Test func everyToastHasItsOwnIdentity() {
        #expect(MidgarToast("Same") != MidgarToast("Same"))
    }

    @Test func shortcutsSetTheStyle() {
        #expect(MidgarToast.success("a").style == .success)
        #expect(MidgarToast.warning("a").style == .warning)
        #expect(MidgarToast.error("a").style == .error)
    }

    @Test func customSymbolWins() {
        #expect(MidgarToast("a", systemImage: "star").systemImage == "star")
    }

    @Test func styleHapticsMatchTheirMeaning() {
        #expect(MidgarToast.Style.info.haptic == nil)
        #expect(MidgarToast.Style.success.haptic == .success)
        #expect(MidgarToast.Style.warning.haptic == .warning)
        #expect(MidgarToast.Style.error.haptic == .error)
    }
}
