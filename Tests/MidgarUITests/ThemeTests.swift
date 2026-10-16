import SwiftUI
import Testing
@testable import MidgarUI

@Suite struct ThemeTests {
    @Test func moduleName() {
        #expect(MidgarUIModule.name == "MidgarUI")
    }

    @Test func hexReadsChannels() {
        let color = MidgarColor.RGBA(hex: 0xFF8000)
        #expect(color.red == 1)
        #expect(abs(color.green - 128.0 / 255.0) < 0.0001)
        #expect(color.blue == 0)
        #expect(color.alpha == 1)
    }

    @Test func colorResolvesPerAppearance() {
        let color = MidgarColor(lightHex: 0xFFFFFF, darkHex: 0x000000)
        #expect(color.resolved(isDark: false).red == 1)
        #expect(color.resolved(isDark: true).red == 0)
    }

    @Test func opacityScalesBothAppearances() {
        let color = MidgarColor(lightHex: 0xFFFFFF, darkHex: 0x000000).opacity(0.5)
        #expect(color.light.alpha == 0.5)
        #expect(color.dark.alpha == 0.5)
    }

    @Test func accentIsPerApp() {
        let green = MidgarColor(hex: 0x00AA55)
        let theme = MidgarTheme(accent: green)
        #expect(theme.accent == green)
        #expect(theme.background == MidgarTheme.standard.background)
        #expect(theme != MidgarTheme.standard)
    }

    @Test func semanticColorsDifferBetweenAppearances() {
        let theme = MidgarTheme.standard
        for color in [theme.background, theme.surface, theme.label, theme.destructive, theme.success, theme.warning] {
            #expect(color.light != color.dark)
        }
    }

    @Test func spacingAndRadiusAreOrdered() {
        let spacing = MidgarSpacing()
        let values = [spacing.xxs, spacing.xs, spacing.s, spacing.m, spacing.l, spacing.xl, spacing.xxl]
        #expect(values == values.sorted())
        let radius = MidgarRadius()
        #expect([radius.small, radius.medium, radius.large, radius.card] == [8, 12, 16, 20])
    }

    @Test func typeScaleMapsEveryStyleToDynamicType() {
        #expect(MidgarTextStyle.allCases.count == 10)
        #expect(MidgarTextStyle.largeTitle.swiftUI == .largeTitle)
        #expect(MidgarTextStyle.title.swiftUI == .title)
        #expect(MidgarTextStyle.caption.swiftUI == .caption)
        let sizes = MidgarTextStyle.allCases.map(\.defaultPointSize)
        #expect(sizes.first! > sizes.last!)
    }

    @Test @MainActor func installedThemeIsCurrent() {
        let previous = MidgarTheme.current
        defer { MidgarTheme.install(previous) }
        let theme = MidgarTheme(accent: MidgarColor(hex: 0x123456))
        MidgarTheme.install(theme)
        #expect(MidgarTheme.current == theme)
    }

    @Test @MainActor func platformFontsExistForEveryStyle() {
        let theme = MidgarTheme(fontDesign: .rounded)
        for style in MidgarTextStyle.allCases {
            #if canImport(UIKit)
            #expect(theme.uiFont(style).pointSize > 0)
            #elseif canImport(AppKit)
            #expect(theme.nsFont(style).pointSize > 0)
            #endif
        }
    }
}
