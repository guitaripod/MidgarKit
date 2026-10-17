import MidgarUI
import SwiftUI

/// The part of a paywall App Review looks for first: what each plan costs and its period from StoreKit, the auto-renew terms, Terms of Use, Privacy Policy and Restore Purchases. It sits outside the scrolling StoreKit view so it is always on screen.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
struct MidgarPaywallFooter: View {
    let planLines: [MidgarPlanLine]
    let showsAutoRenew: Bool
    var showsActions = true
    let links: MidgarPaywallLinks
    let isRestoring: Bool
    let restore: () -> Void
    var focus: FocusState<MidgarPaywallFocus?>.Binding?

    @Environment(\.midgarTheme) private var theme

    var body: some View {
        VStack(spacing: theme.spacing.s) {
            ForEach(planLines) { line in
                planRow(line)
            }
            if showsAutoRenew {
                Text(MidgarCommerceUIStrings.autoRenewTerms)
                    .midgarFont(.caption)
                    .foregroundStyle(theme.secondaryLabel.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsActions {
                actions
            }
        }
        .padding(.horizontal, theme.spacing.l)
        .padding(.vertical, theme.spacing.m)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(theme.background.color)
    }

    private func planRow(_ line: MidgarPlanLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing.s) {
            Text(verbatim: line.name)
                .midgarFont(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(theme.label.color)
            Spacer(minLength: theme.spacing.s)
            Text(verbatim: line.text)
                .midgarFont(.footnote)
                .foregroundStyle(theme.secondaryLabel.color)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: theme.spacing.l) {
                actionButtons
            }
            VStack(spacing: theme.spacing.s) {
                actionButtons
            }
        }
        .midgarFont(.footnote)
        .foregroundStyle(theme.accent.color)
    }

    @ViewBuilder
    private var actionButtons: some View {
        legalLinks
        Button(action: restore) {
            if isRestoring {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(MidgarCommerceUIStrings.restoring)
            } else {
                Text(MidgarCommerceUIStrings.restorePurchases)
            }
        }
        .buttonStyle(.plain)
        .disabled(isRestoring)
        .modifier(MidgarRestoreFocus(focus: focus))
    }

    /// The address a person types, without the scheme.
    private static func address(of url: URL) -> String {
        let text = url.absoluteString
        return text.replacingOccurrences(of: "^https?://", with: "", options: .regularExpression)
    }

    /// Terms of Use and Privacy Policy as links. tvOS cannot open a web page, so it states the addresses.
    @ViewBuilder
    private var legalLinks: some View {
        #if os(tvOS)
        Text(verbatim: "\(MidgarCommerceUIStrings.termsOfUse): \(Self.address(of: links.termsOfUse))")
        Text(verbatim: "\(MidgarCommerceUIStrings.privacyPolicy): \(Self.address(of: links.privacyPolicy))")
        #else
        Link(MidgarCommerceUIStrings.termsOfUse, destination: links.termsOfUse)
        Link(MidgarCommerceUIStrings.privacyPolicy, destination: links.privacyPolicy)
        #endif
    }
}

/// Marks Restore Purchases as a focus target when the paywall tracks focus (tvOS), and does nothing otherwise.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
private struct MidgarRestoreFocus: ViewModifier {
    let focus: FocusState<MidgarPaywallFocus?>.Binding?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let focus {
            content.focused(focus, equals: .restore)
        } else {
            content
        }
    }
}
