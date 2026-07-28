#if canImport(UIKit)
import UIKit

/// A capsule GET/price label that pads itself through layout instead of through literal spaces.
///
/// The padding used to be baked into the string as `"  GET  "`. Text layout collapses a line's
/// trailing whitespace when it measures and draws, but keeps the leading run, so the glyphs sat
/// off-centre inside the capsule — visibly more space on the left than on the right.
@MainActor
final class PillLabel: UILabel {
    private let horizontalInset: CGFloat = 12

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + horizontalInset * 2, height: size.height)
    }

    override func textRect(forBounds bounds: CGRect,
                           limitedToNumberOfLines numberOfLines: Int) -> CGRect {
        let inset = bounds.insetBy(dx: horizontalInset, dy: 0)
        let rect = super.textRect(forBounds: inset, limitedToNumberOfLines: numberOfLines)
        return rect.insetBy(dx: -horizontalInset, dy: 0)
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.insetBy(dx: horizontalInset, dy: 0))
    }
}
#endif
