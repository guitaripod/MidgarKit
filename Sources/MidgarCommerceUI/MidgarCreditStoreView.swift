import MidgarCredits
import MidgarUI
import SwiftUI

/// The credit store of an app that sells AI credit packs on the Midgar ID wallet: the balance (and the free allowances that renew, when mako reports any), one row per pack with the credits it grants and StoreKit's price, and the result of each purchase.
///
/// The packs come from ``MidgarCredits/offers()`` and a tap runs ``MidgarCredits/buy(_:)``. A credit mako has not confirmed yet shows as a row that stays until ``MidgarCredits/events()`` reports it credited, so the person is never left wondering whether to pay twice. Pass `shortfall` when the person arrives because an action needs more credits than they have. The column is at most 560 points wide and centered, so it reads the same in an iPhone sheet, an iPad or Mac window and the windows of an iPhone Duo, and it follows Dynamic Type up to the accessibility sizes.
///
/// UIKit hosts it in a `UIHostingController(rootView: MidgarCreditStoreView(credits: credits))`.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
public struct MidgarCreditStoreView: View {
    @State private var model: MidgarCreditStoreModel
    private let allowanceTitles: [String: String]

    @Environment(\.midgarTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    /// - Parameters:
    ///   - credits: The wallet. ``MidgarCredits`` conforms; previews pass a fake.
    ///   - shortfall: How many more credits the person needs, or nil. A banner says so and the smallest pack that covers it is marked.
    ///   - allowanceTitles: The names to show for the free allowances, by the id mako keys them with. An allowance without a name shows its id.
    public init(credits: any MidgarCreditStoreSource, shortfall: Int? = nil, allowanceTitles: [String: String] = [:]) {
        self.init(model: MidgarCreditStoreModel(source: credits, shortfall: shortfall), allowanceTitles: allowanceTitles)
    }

    init(model: MidgarCreditStoreModel, allowanceTitles: [String: String] = [:]) {
        _model = State(initialValue: model)
        self.allowanceTitles = allowanceTitles
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: theme.spacing.l) {
                if let shortfall = model.shortfall {
                    MidgarCreditNoticeRow(style: .warning, symbol: "exclamationmark.circle.fill", text: MidgarCommerceUIStrings.creditsShortfall(shortfall))
                }
                MidgarCreditBalanceCard(
                    balance: model.balance,
                    isUnavailable: model.balanceUnavailable,
                    isLoading: model.phase == .loading && model.balance == nil,
                    allowanceTitles: allowanceTitles
                )
                ForEach(model.confirming) { _ in
                    MidgarCreditConfirmingRow()
                }
                notice
                packs
            }
            .padding(.horizontal, theme.spacing.l)
            .padding(.vertical, theme.spacing.xl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(theme.background.color.ignoresSafeArea())
        .tint(theme.accent.color)
        .task { await model.observe() }
        .task { await model.load() }
    }

    @ViewBuilder
    private var notice: some View {
        switch model.notice {
        case .credited(let count):
            MidgarCreditNoticeRow(style: .success, symbol: "checkmark.circle.fill", text: MidgarCommerceUIStrings.creditsAdded(count))
        case .awaitingApproval:
            MidgarCreditNoticeRow(style: .info, symbol: "clock.fill", text: MidgarCommerceUIStrings.creditsAwaitingApproval)
        case .failure(let failure):
            MidgarCreditNoticeRow(style: .failure, symbol: "exclamationmark.triangle.fill", text: failure.message)
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private var packs: some View {
        switch model.phase {
        case .loading:
            ProgressView()
                .accessibilityLabel(MidgarCommerceUIStrings.creditsLoadingPacks)
                .frame(maxWidth: .infinity, minHeight: 120)
        case .unavailable:
            unavailable
        case .ready:
            VStack(spacing: theme.spacing.m) {
                ForEach(model.offers) { offer in
                    MidgarCreditOfferRow(
                        offer: offer,
                        isBuying: model.buyingPackID == offer.pack.id,
                        isEnabled: !model.isBuying,
                        coversShortfall: model.coveringPackID == offer.pack.id,
                        buy: { Task { await model.buy(offer) } }
                    )
                }
            }
        }
    }

    private var unavailable: some View {
        VStack(spacing: theme.spacing.m) {
            Image(systemName: "creditcard.trianglebadge.exclamationmark")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(theme.secondaryLabel.color)
                .accessibilityHidden(true)
            Text(MidgarCommerceUIStrings.creditsPacksUnavailableTitle)
                .midgarFont(.headline)
                .foregroundStyle(theme.label.color)
            Text(MidgarCommerceUIStrings.creditsPacksUnavailableDetail)
                .midgarFont(.subheadline)
                .foregroundStyle(theme.secondaryLabel.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(MidgarCommerceUIStrings.tryAgain) {
                Task { await model.retry() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .modifier(MidgarOnAccentLabel())
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}
