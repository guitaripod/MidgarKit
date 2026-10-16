import SwiftUI
@testable import MidgarUI

@MainActor
enum RenderFixtures {
    static let theme = MidgarTheme(accent: MidgarColor(hex: 0x2A9D8F))

    static let settingsSections: [MidgarSettingsSection] = [
        MidgarSettingsSection(id: "app", title: "App", rows: [
            .toggle(id: "haptics", title: "Haptics", systemImage: "waveform", isOn: { true }, setOn: { _ in }),
            .custom(id: "appearance", title: "Appearance", detail: "System", systemImage: "circle.lefthalf.filled") {}
        ]),
        MidgarSettingsSection(id: "about", title: "About", rows: [
            .restorePurchases {},
            .support(address: "support@midgarcorp.cc"),
            .version(MidgarVersionInfo(name: "Pay Day", version: "1.4.2", build: "87"))
        ]),
        MidgarSettingsSection(id: "account", rows: [.deleteAccount {}])
    ]

    static var portalCard: some View {
        RoundedRectangle(cornerRadius: 16).fill(.purple).frame(height: 88).padding()
    }

    static func settings() -> some View {
        MidgarSettings(sections: settingsSections) { portalCard }
    }

    static let onboardingPages: [MidgarOnboardingPage] = [
        MidgarOnboardingPage(id: "a", title: "Welcome", body: "Everything in one place.", artwork: .symbol("sparkles")),
        MidgarOnboardingPage(id: "b", title: "Stay in sync", body: "Your data follows you.", artwork: .symbol("icloud"))
    ]

    static func onboarding() -> some View {
        MidgarOnboarding(pages: onboardingPages, showsSkip: true) {}
    }

    static let whatsNewItems: [MidgarWhatsNewItem] = [
        MidgarWhatsNewItem(title: "Faster search", body: "Results appear as you type.", systemImage: "magnifyingglass"),
        MidgarWhatsNewItem(title: "New widgets", body: "Glance at your day.", systemImage: "rectangle.3.group")
    ]

    static func whatsNew() -> some View {
        MidgarWhatsNew(items: whatsNewItems) {}
    }

    static func toastModel(_ style: MidgarToast.Style) -> MidgarToast {
        MidgarToast("Purchases restored", style: style)
    }

    static func toast(_ style: MidgarToast.Style) -> some View {
        MidgarToastView(toastModel(style))
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MidgarTheme.standard.background.color)
    }
}
