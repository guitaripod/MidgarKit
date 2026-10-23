import MidgarUI
import SwiftUI

/// The top of a plan paywall: the picture, the headline, the subtitle and the benefit rows the app supplies.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
struct MidgarPaywallPitch: View {
    let hero: MidgarPaywallHero
    let isCompact: Bool
    /// Draws a symbol beside the title instead of above it, to save a row of height. Pictures stay above.
    var inlinesSymbol = false

    @Environment(\.midgarTheme) private var theme
    @State private var picture: Image?
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = MidgarPaywallPitch.baseIconWidth

    var body: some View {
        VStack(spacing: isCompact ? theme.spacing.m : theme.spacing.l) {
            VStack(spacing: theme.spacing.s) {
                if inlinesSymbol, hero.artwork?.isSymbolOnly == true {
                    HStack(spacing: theme.spacing.l) {
                        artwork
                        titleText
                    }
                } else {
                    artwork
                    titleText
                }
                if let subtitle = hero.subtitle {
                    Text(verbatim: subtitle)
                        .midgarFont(isCompact ? .headline : .title3)
                        .foregroundStyle(theme.secondaryLabel.color)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            if !hero.features.isEmpty {
                features
            }
        }
        .frame(maxWidth: .infinity)
        .task {
            if case .picture(_, let load) = hero.artwork {
                picture = await load()
            }
        }
    }

    private var titleText: some View {
        Text(verbatim: hero.title)
            .midgarFont(isCompact ? .title : .largeTitle)
            .foregroundStyle(theme.label.color)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.7)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var artwork: some View {
        switch hero.artwork {
        case .symbol(let name):
            symbolArtwork(name)
        case .picture(let name, _):
            if let picture {
                pictureArtwork(picture, symbol: name)
            } else {
                symbolArtwork(name)
            }
        case .image(let image):
            image
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: isCompact ? 132 : 180)
                .clipShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
                .accessibilityHidden(true)
        case nil:
            EmptyView()
        }
    }

    private func symbolArtwork(_ name: String, color: Color? = nil) -> some View {
        Image(systemName: name)
            .font(.system(size: isCompact ? 44 : 64, weight: .light))
            .foregroundStyle(color ?? theme.accent.color)
            .accessibilityHidden(true)
    }

    /// The picture the customer was stopped at, lightly blurred, with the symbol over it.
    private func pictureArtwork(_ image: Image, symbol: String) -> some View {
        ZStack {
            image
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: isCompact ? 96 : 148)
                .clipped()
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.55)
            symbolArtwork(symbol, color: .white)
        }
        .frame(maxWidth: .infinity)
        .frame(height: isCompact ? 96 : 148)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .accessibilityHidden(true)
    }

    private static var baseIconWidth: CGFloat {
        #if os(tvOS)
        56
        #else
        34
        #endif
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: isCompact ? theme.spacing.s : theme.spacing.m) {
            ForEach(hero.features) { feature in
                HStack(alignment: .firstTextBaseline, spacing: theme.spacing.m) {
                    Image(systemName: feature.symbol)
                        .foregroundStyle(theme.accent.color)
                        .frame(width: iconWidth)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                        Text(verbatim: feature.title)
                            .midgarFont(.body)
                            .foregroundStyle(theme.label.color)
                        if let detail = feature.detail {
                            Text(verbatim: detail)
                                .midgarFont(.subheadline)
                                .foregroundStyle(theme.secondaryLabel.color)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: Self.featuresWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private static var featuresWidth: CGFloat {
        #if os(tvOS)
        820
        #else
        480
        #endif
    }
}
