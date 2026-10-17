import MidgarCommerce
import MidgarUI
import StoreKit
import SwiftUI

/// One plan or product as a card: its name, what it costs, an optional line of detail and an optional badge. It draws from the Midgar theme and holds no purchase logic, so it works in a picker the app builds itself or as the face of a StoreKit product (``MidgarPlanProductViewStyle``).
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
public struct MidgarPlanCard: View {
    public let title: String
    /// What the plan costs with its period, e.g. `$39.99/year`, or a one-time price.
    public let price: String
    /// A line under the title, e.g. the trial summary `1 week free, then $39.99/year`.
    public let detail: String?
    /// A short label on the card, e.g. `1 week free` or `Best value`.
    public let badge: String?
    public let isSelected: Bool
    /// True for a product the customer owns. The card then shows "Purchased" in place of the price.
    public let isPurchased: Bool

    @Environment(\.midgarTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(
        title: String,
        price: String,
        detail: String? = nil,
        badge: String? = nil,
        isSelected: Bool = false,
        isPurchased: Bool = false
    ) {
        self.title = title
        self.price = price
        self.detail = detail
        self.badge = badge
        self.isSelected = isSelected
        self.isPurchased = isPurchased
    }

    /// A card for a StoreKit product: the price and period come from StoreKit, and the detail and badge from the trial `presentation` when there is one, else the product's own description.
    public init(
        product: Product,
        presentation: MidgarTrialPresentation? = nil,
        badge: String? = nil,
        isSelected: Bool = false,
        isPurchased: Bool = false
    ) {
        let terms = MidgarSubscriptionTerms(product: product)
        self.init(
            title: product.displayName,
            price: terms?.renewalDescription() ?? product.displayPrice,
            detail: presentation?.summary ?? (product.description.isEmpty ? nil : product.description),
            badge: badge ?? presentation?.badge,
            isSelected: isSelected,
            isPurchased: isPurchased
        )
    }

    public var body: some View {
        layout
            .padding(theme.spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface.color, in: shape)
            .overlay(shape.strokeBorder(isSelected ? theme.accent.color : theme.separator.color, lineWidth: isSelected ? 2 : 1))
            .contentShape(shape)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
    }

    @ViewBuilder
    private var layout: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: theme.spacing.s) {
                titleBlock
                trailingBlock(alignment: .leading)
            }
        } else {
            HStack(alignment: .center, spacing: theme.spacing.m) {
                titleBlock
                Spacer(minLength: theme.spacing.m)
                trailingBlock(alignment: .trailing)
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Text(verbatim: title)
                .midgarFont(.headline)
                .foregroundStyle(theme.label.color)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(verbatim: detail)
                    .midgarFont(.subheadline)
                    .foregroundStyle(theme.secondaryLabel.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func trailingBlock(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: theme.spacing.xs) {
            if isPurchased {
                Label(MidgarCommerceUIStrings.purchased, systemImage: "checkmark.circle.fill")
                    .midgarFont(.subheadline)
                    .foregroundStyle(theme.success.color)
            } else {
                Text(verbatim: price)
                    .midgarFont(.headline)
                    .foregroundStyle(theme.label.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let badge {
                Text(verbatim: badge)
                    .midgarFont(.caption)
                    .foregroundStyle(theme.accent.color)
                    .padding(.horizontal, theme.spacing.s)
                    .padding(.vertical, theme.spacing.xxs)
                    .background(theme.accent.color.opacity(0.15), in: Capsule())
            }
        }
    }
}

/// Draws every product of a `StoreView` or `ProductView` as a ``MidgarPlanCard``. A tap runs the view's own purchase, so ``View/midgarPurchases(store:onEvent:)`` applies.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
public struct MidgarPlanProductViewStyle: ProductViewStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        switch configuration.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding()
        case .success(let product):
            Button {
                configuration.purchase()
            } label: {
                MidgarPlanCard(product: product, isPurchased: configuration.hasCurrentEntitlement)
            }
            .buttonStyle(.plain)
            .disabled(configuration.hasCurrentEntitlement)
        case .unavailable, .failure:
            EmptyView()
        @unknown default:
            EmptyView()
        }
    }
}
