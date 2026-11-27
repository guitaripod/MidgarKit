import CoreGraphics

/// The safe area around the portal, independent of UIKit, AppKit and SwiftUI.
struct PortalSafeArea: Equatable, Sendable {
    var top: CGFloat = 0
    var leading: CGFloat = 0
    var bottom: CGFloat = 0
    var trailing: CGFloat = 0
}

/// Where the chrome goes around the canvas: the card under it on tall screens, beside it when the
/// screen is too short for both, as on a phone held sideways.
struct PortalScreenLayout: Equatable, Sendable {
    static let headerHeight: CGFloat = 64 * PortalMetrics.scale
    static let cardHeight: CGFloat = 156 * PortalMetrics.scale
    static let cardMaxWidth: CGFloat = 560 * PortalMetrics.scale
    static let margin: CGFloat = 16

    let size: CGSize
    let safeArea: PortalSafeArea

    var isSideCard: Bool { size.width > size.height && size.height < 560 }

    var sideCardWidth: CGFloat { min(340 * PortalMetrics.scale, size.width * 0.42) }

    /// The header's distance from the top of the safe area: none under a notch or status bar, a
    /// little on screens that have neither.
    var headerTopPadding: CGFloat { safeArea.top > 0 ? 0 : 8 }

    /// The gap between the bottom card and the bottom of the safe area.
    var cardBottomPadding: CGFloat { max(safeArea.bottom, Self.margin) }

    /// The gap between the side card and the trailing edge of the safe area.
    var cardTrailingPadding: CGFloat { max(safeArea.trailing, Self.margin) }

    /// Where "Your Midgar" may sit, measured inside the safe area: under the header and clear of the card.
    var panelInsets: PortalInsets {
        let top = headerTopPadding + Self.headerHeight
        if isSideCard {
            return PortalInsets(top: top, bottom: 12, trailing: sideCardWidth + Self.margin + 8)
        }
        return PortalInsets(top: top, bottom: cardBottomPadding + Self.cardHeight + 12)
    }

    /// What the canvas must keep clear of: the header above, and below (or beside) the card with a
    /// little air, so no icon ever sits under the card.
    var canvasInsets: PortalInsets {
        let top = safeArea.top + Self.headerHeight
        if isSideCard {
            return PortalInsets(
                top: top,
                bottom: max(safeArea.bottom, 12),
                trailing: sideCardWidth + cardTrailingPadding + 8
            )
        }
        return PortalInsets(top: top, bottom: safeArea.bottom + cardBottomPadding + Self.cardHeight + 12)
    }

    /// The header's frame: the width of the safe area, at its top.
    var headerFrame: CGRect {
        CGRect(
            x: safeArea.leading,
            y: safeArea.top + headerTopPadding,
            width: max(0, size.width - safeArea.leading - safeArea.trailing),
            height: Self.headerHeight
        )
    }

    /// The card's frame: centred at the bottom of the safe area, or beside the canvas on a short,
    /// wide screen.
    var cardFrame: CGRect {
        let safeWidth = max(0, size.width - safeArea.leading - safeArea.trailing)
        if isSideCard {
            let safeHeight = size.height - safeArea.top - safeArea.bottom
            return CGRect(
                x: size.width - safeArea.trailing - cardTrailingPadding - sideCardWidth,
                y: safeArea.top + (safeHeight - Self.cardHeight) / 2,
                width: sideCardWidth,
                height: Self.cardHeight
            )
        }
        let width = min(Self.cardMaxWidth, max(0, safeWidth - Self.margin * 2))
        return CGRect(
            x: safeArea.leading + (safeWidth - width) / 2,
            y: size.height - safeArea.bottom - cardBottomPadding - Self.cardHeight,
            width: width,
            height: Self.cardHeight
        )
    }

    /// The largest rectangle "Your Midgar" may fill. It sits at the top of it and is only as tall
    /// as its rows.
    var panelBounds: CGRect {
        let insets = panelInsets
        let safeWidth = max(0, size.width - safeArea.leading - safeArea.trailing - insets.trailing)
        let width = min(560, max(0, safeWidth - Self.margin * 2))
        let top = safeArea.top + insets.top
        let bottom = size.height - safeArea.bottom - insets.bottom
        return CGRect(
            x: safeArea.leading + (safeWidth - width) / 2,
            y: top,
            width: width,
            height: max(0, bottom - top)
        )
    }
}
