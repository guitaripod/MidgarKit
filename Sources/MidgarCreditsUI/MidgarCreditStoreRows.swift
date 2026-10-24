import MidgarCommerceUI
import MidgarCredits
import MidgarUI
import SwiftUI

/// The balance with the free allowances under it, in one card.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
struct MidgarCreditBalanceCard: View {
    let balance: MidgarCreditsBalance?
    let isUnavailable: Bool
    let isLoading: Bool
    let allowanceTitles: [String: String]

    @Environment(\.midgarTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                Text(MidgarCreditsUIStrings.creditsBalanceTitle)
                    .midgarFont(.subheadline)
                    .foregroundStyle(theme.secondaryLabel.color)
                balanceText
            }
            .accessibilityElement(children: .combine)
            if let allowances = balance?.allowances, !allowances.isEmpty {
                Divider()
                Text(MidgarCreditsUIStrings.creditsAllowancesTitle)
                    .midgarFont(.subheadline)
                    .foregroundStyle(theme.secondaryLabel.color)
                ForEach(allowances) { allowance in
                    MidgarCreditAllowanceRow(allowance: allowance, title: allowanceTitles[allowance.id] ?? allowance.id)
                }
            }
        }
        .padding(theme.spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(MidgarCreditCardSurface())
    }

    @ViewBuilder
    private var balanceText: some View {
        if let balance {
            Text(verbatim: MidgarCreditsUIStrings.creditsCount(balance.credits))
                .midgarFont(.largeTitle)
                .monospacedDigit()
                .foregroundStyle(theme.label.color)
                .fixedSize(horizontal: false, vertical: true)
        } else if isLoading {
            ProgressView()
                .accessibilityLabel(MidgarCreditsUIStrings.creditsLoadingPacks)
        } else if isUnavailable {
            Text(MidgarCreditsUIStrings.creditsBalanceUnavailable)
                .midgarFont(.subheadline)
                .foregroundStyle(theme.secondaryLabel.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One free allowance: its name, how much is left, a gauge, and when it refills.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
struct MidgarCreditAllowanceRow: View {
    let allowance: MidgarCreditsAllowance
    let title: String

    @Environment(\.midgarTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                    name
                    left
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: theme.spacing.s) {
                    name
                    Spacer(minLength: theme.spacing.s)
                    left
                }
            }
            gauge
            if let resetsAt = allowance.resetsAt {
                Text(MidgarCreditsUIStrings.creditsAllowanceResets(resetsAt.formatted(date: .abbreviated, time: .omitted)))
                    .midgarFont(.caption)
                    .foregroundStyle(theme.secondaryLabel.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var name: some View {
        Text(verbatim: title)
            .midgarFont(.body)
            .foregroundStyle(theme.label.color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var left: some View {
        Text(verbatim: MidgarCreditsUIStrings.creditsAllowanceLeft(remaining: allowance.remaining, limit: allowance.limit))
            .midgarFont(.subheadline)
            .monospacedDigit()
            .foregroundStyle(theme.secondaryLabel.color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var gauge: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.separator.color)
                Capsule()
                    .fill(theme.accent.color)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    private var fraction: CGFloat {
        guard allowance.limit > 0 else {
            return 0
        }
        return CGFloat(min(allowance.remaining, allowance.limit)) / CGFloat(allowance.limit)
    }
}

/// One pack: the credits it grants, its name, and a buy button with StoreKit's price that turns into a spinner while the purchase runs.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
struct MidgarCreditOfferRow: View {
    let offer: MidgarCreditsOffer
    let isBuying: Bool
    let isEnabled: Bool
    let coversShortfall: Bool
    let buy: () -> Void

    @Environment(\.midgarTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        layout
            .padding(theme.spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(MidgarCreditCardSurface(highlighted: coversShortfall))
            .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var layout: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: theme.spacing.m) {
                titleBlock
                buyButton(fillsWidth: true)
            }
        } else {
            HStack(alignment: .center, spacing: theme.spacing.m) {
                titleBlock
                Spacer(minLength: theme.spacing.m)
                buyButton(fillsWidth: false)
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text(verbatim: MidgarCreditsUIStrings.creditsCount(offer.pack.credits))
                .midgarFont(.headline)
                .foregroundStyle(theme.label.color)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: offer.product.displayName)
                .midgarFont(.subheadline)
                .foregroundStyle(theme.secondaryLabel.color)
                .fixedSize(horizontal: false, vertical: true)
            if coversShortfall {
                Text(MidgarCreditsUIStrings.creditsCoversShortfall)
                    .midgarFont(.caption)
                    .foregroundStyle(theme.accent.color)
                    .padding(.horizontal, theme.spacing.s)
                    .padding(.vertical, theme.spacing.xxs)
                    .background(theme.accent.color.opacity(0.15), in: Capsule())
            }
        }
    }

    private func buyButton(fillsWidth: Bool) -> some View {
        Button(action: buy) {
            ZStack {
                MidgarCreditBuyLabel(price: offer.product.displayPrice)
                    .opacity(isBuying ? 0 : 1)
                if isBuying {
                    ProgressView()
                        .modifier(MidgarOnAccentSpinner())
                        .accessibilityLabel(MidgarCreditsUIStrings.purchasing)
                }
            }
            .frame(minWidth: 72, maxWidth: fillsWidth ? .infinity : nil, minHeight: 24)
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.accent.color)
        .disabled(!isEnabled && !isBuying)
        .accessibilityLabel(MidgarCreditsUIStrings.creditsBuy(offer.product.displayPrice))
    }
}

/// A purchase that was paid for and not yet credited. It stays until the wallet credits it.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
struct MidgarCreditConfirmingRow: View {
    @Environment(\.midgarTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        stack
            .padding(theme.spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(MidgarCreditCardSurface(highlighted: true))
            .accessibilityElement(children: .combine)
    }

    /// At an accessibility text size the spinner sits above the text instead of beside it, so the text keeps the whole width.
    @ViewBuilder
    private var stack: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: theme.spacing.m) {
                spinner
                texts
            }
        } else {
            HStack(alignment: .top, spacing: theme.spacing.m) {
                spinner
                texts
                Spacer(minLength: 0)
            }
        }
    }

    private var spinner: some View {
        ProgressView()
            .accessibilityHidden(true)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text(MidgarCreditsUIStrings.creditsConfirmingTitle)
                .midgarFont(.headline)
                .foregroundStyle(theme.label.color)
                .fixedSize(horizontal: false, vertical: true)
            Text(MidgarCreditsUIStrings.creditsConfirmingDetail)
                .midgarFont(.subheadline)
                .foregroundStyle(theme.secondaryLabel.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A line about the last result or the shortfall: a symbol in the color of its meaning and a message.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
struct MidgarCreditNoticeRow: View {
    enum Style {
        case success
        case info
        case warning
        case failure
    }

    let style: Style
    let symbol: String
    let text: String

    @Environment(\.midgarTheme) private var theme

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        stack
            .padding(theme.spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: theme.radius.medium, style: .continuous))
            .accessibilityElement(children: .combine)
    }

    /// At an accessibility text size the symbol sits above the message instead of beside it, so the message keeps the whole width.
    @ViewBuilder
    private var stack: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: theme.spacing.s) {
                icon
                message
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing.m) {
                icon
                message
                Spacer(minLength: 0)
            }
        }
    }

    private var icon: some View {
        Image(systemName: symbol)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }

    private var message: some View {
        Text(verbatim: text)
            .midgarFont(.subheadline)
            .foregroundStyle(theme.label.color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var color: Color {
        switch style {
        case .success:
            return theme.success.color
        case .info:
            return theme.accent.color
        case .warning:
            return theme.warning.color
        case .failure:
            return theme.destructive.color
        }
    }
}

/// The card face every row of the credit store shares: the surface, a hairline, and the accent when the row is highlighted.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
struct MidgarCreditCardSurface: ViewModifier {
    var highlighted = false

    @Environment(\.midgarTheme) private var theme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
        content
            .background(theme.surface.color, in: shape)
            .overlay(shape.strokeBorder(highlighted ? theme.accent.color : theme.separator.color, lineWidth: highlighted ? 2 : 1))
    }
}

/// The price on a buy button: the color that reads on the accent while the button is enabled, and the system's own disabled color while another purchase runs, so a disabled price is dim but never white on light gray.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
private struct MidgarCreditBuyLabel: View {
    let price: String

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        if isEnabled {
            Text(verbatim: price)
                .midgarFont(.headline)
                .modifier(MidgarOnAccentLabel())
        } else {
            Text(verbatim: price)
                .midgarFont(.headline)
        }
    }
}

/// Tints a spinner on the accent in the color that reads there: the button's own tint is the accent, which would make the spinner invisible.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
private struct MidgarOnAccentSpinner: ViewModifier {
    @Environment(\.midgarTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.tint(MidgarOnAccentLabel.isLight(theme.accent.resolved(isDark: colorScheme == .dark)) ? Color.black : Color.white)
    }
}
