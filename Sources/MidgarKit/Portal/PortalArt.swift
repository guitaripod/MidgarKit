import CoreGraphics
import CoreText
import Foundation

/// An sRGB colour used by the portal's drawing code, independent of UIKit and AppKit.
struct PortalColor: Equatable, Sendable {
    var r: CGFloat
    var g: CGFloat
    var b: CGFloat
    var a: CGFloat = 1

    static let white = PortalColor(r: 1, g: 1, b: 1)
    static let space = PortalColor(r: 0.02, g: 0.025, b: 0.07)
    static let midgar = PortalColor(r: 0.45, g: 0.55, b: 1)

    init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    init(hex: String?, fallback: PortalColor = .midgar) {
        if let c = midgarRGBA(hex: hex) {
            self.init(r: c.r, g: c.g, b: c.b, a: c.a)
        } else {
            self = fallback
        }
    }

    func withAlpha(_ alpha: CGFloat) -> PortalColor {
        PortalColor(r: r, g: g, b: b, a: alpha)
    }

    func mixed(with other: PortalColor, _ amount: CGFloat) -> PortalColor {
        PortalColor(
            r: r + (other.r - r) * amount,
            g: g + (other.g - g) * amount,
            b: b + (other.b - b) * amount,
            a: a + (other.a - a) * amount
        )
    }

    func darkened(_ amount: CGFloat) -> PortalColor { mixed(with: PortalColor(r: 0, g: 0, b: 0, a: a), amount) }
    func lightened(_ amount: CGFloat) -> PortalColor { mixed(with: PortalColor(r: 1, g: 1, b: 1, a: a), amount) }

    var cgColor: CGColor { CGColor(colorSpace: PortalArt.colorSpace, components: [r, g, b, a])! }
}

/// Every bitmap the portal shows is drawn here once, at the size it is displayed, so the render
/// loop only ever moves pre-made textures around.
enum PortalArt {
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// Draws into a transparent bitmap of `size` points at `scale`, with the origin at the
    /// bottom-left in point units.
    static func render(size: CGSize, scale: CGFloat, _ draw: (CGContext, CGSize) -> Void) -> CGImage? {
        let width = max(1, Int((size.width * scale).rounded(.up)))
        let height = max(1, Int((size.height * scale).rounded(.up)))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.setAllowsAntialiasing(true)
        context.interpolationQuality = .high
        draw(context, size)
        return context.makeImage()
    }

    static func gradient(_ colors: [PortalColor], locations: [CGFloat]? = nil) -> CGGradient? {
        CGGradient(
            colorsSpace: colorSpace,
            colors: colors.map(\.cgColor) as CFArray,
            locations: locations
        )
    }

    /// An app icon cut to a disc: dark accent-tinted base, the artwork, a soft top gloss, an inner
    /// edge shadow and a thin lit rim. `zoom` enlarges artwork that carries its own padding.
    static func circularIcon(
        source: CGImage?,
        diameter: CGFloat,
        scale: CGFloat,
        accent: PortalColor,
        monogram: String,
        zoom: CGFloat
    ) -> CGImage? {
        render(size: CGSize(width: diameter, height: diameter), scale: scale) { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            let disc = rect.insetBy(dx: 0.5, dy: 0.5)
            ctx.saveGState()
            ctx.addEllipse(in: disc)
            ctx.clip()
            fillBase(ctx, rect: rect, accent: accent)
            if let source {
                let side = diameter * zoom
                let artwork = CGRect(x: (diameter - side) / 2, y: (diameter - side) / 2, width: side, height: side)
                ctx.draw(source, in: artwork)
            } else {
                drawMonogram(ctx, text: monogram, in: rect)
            }
            drawGloss(ctx, rect: rect)
            drawEdgeShade(ctx, rect: rect)
            ctx.restoreGState()
            drawRim(ctx, disc: disc, diameter: diameter)
        }
    }

    private static func fillBase(_ ctx: CGContext, rect: CGRect, accent: PortalColor) {
        guard let base = gradient([accent.darkened(0.15), accent.darkened(0.6)]) else { return }
        ctx.drawLinearGradient(
            base,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
    }

    private static func drawGloss(_ ctx: CGContext, rect: CGRect) {
        guard let gloss = gradient([PortalColor.white.withAlpha(0.22), PortalColor.white.withAlpha(0)]) else { return }
        ctx.drawLinearGradient(
            gloss,
            start: CGPoint(x: rect.midX, y: rect.maxY),
            end: CGPoint(x: rect.midX, y: rect.midY - rect.height * 0.05),
            options: []
        )
    }

    private static func drawEdgeShade(_ ctx: CGContext, rect: CGRect) {
        guard let shade = gradient(
            [PortalColor(r: 0, g: 0, b: 0, a: 0), PortalColor(r: 0, g: 0, b: 0, a: 0.38)],
            locations: [0.78, 1]
        ) else { return }
        ctx.drawRadialGradient(
            shade,
            startCenter: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0,
            endCenter: CGPoint(x: rect.midX, y: rect.midY), endRadius: rect.width / 2,
            options: []
        )
    }

    private static func drawRim(_ ctx: CGContext, disc: CGRect, diameter: CGFloat) {
        guard let rim = gradient([PortalColor.white.withAlpha(0.7), PortalColor.white.withAlpha(0.08)]) else { return }
        ctx.saveGState()
        ctx.setLineWidth(max(1, diameter * 0.012))
        ctx.addEllipse(in: disc.insetBy(dx: 0.4, dy: 0.4))
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        ctx.drawLinearGradient(
            rim,
            start: CGPoint(x: disc.minX, y: disc.maxY),
            end: CGPoint(x: disc.maxX, y: disc.minY),
            options: []
        )
        ctx.restoreGState()
    }

    private static func drawMonogram(_ ctx: CGContext, text: String, in rect: CGRect) {
        let font = CTFontCreateUIFontForLanguage(.system, rect.height * 0.46, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, rect.height * 0.46, nil)
        drawText(ctx, text: text, font: font, color: PortalColor.white.withAlpha(0.92), centeredIn: rect)
    }

    static func drawText(_ ctx: CGContext, text: String, font: CTFont, color: PortalColor, centeredIn rect: CGRect) {
        let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color.cgColor]
        let attributed = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        ctx.textPosition = CGPoint(
            x: rect.midX - bounds.midX,
            y: rect.midY - bounds.midY
        )
        CTLineDraw(line, ctx)
    }

    /// The Midgar mark: seven rounded hexagons in a honeycomb flower on a deep disc.
    static func coreEmblem(diameter: CGFloat, scale: CGFloat, tint: PortalColor) -> CGImage? {
        render(size: CGSize(width: diameter, height: diameter), scale: scale) { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            ctx.saveGState()
            ctx.addEllipse(in: rect.insetBy(dx: 0.5, dy: 0.5))
            ctx.clip()
            if let base = gradient([tint.darkened(0.55), PortalColor.space.mixed(with: tint, 0.12)]) {
                ctx.drawRadialGradient(
                    base,
                    startCenter: CGPoint(x: rect.midX, y: rect.midY + diameter * 0.12), startRadius: 0,
                    endCenter: CGPoint(x: rect.midX, y: rect.midY), endRadius: diameter * 0.62,
                    options: [.drawsAfterEndLocation]
                )
            }
            drawHoneycomb(ctx, rect: rect, tint: tint)
            drawEdgeShade(ctx, rect: rect)
            ctx.restoreGState()
            drawRim(ctx, disc: rect.insetBy(dx: 0.5, dy: 0.5), diameter: diameter)
        }
    }

    private static func drawHoneycomb(_ ctx: CGContext, rect: CGRect, tint: PortalColor) {
        let circumradius = rect.width * 0.135
        let spacing = circumradius * 1.7320508 * 1.1
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        var centres = [centre]
        for step in 0..<6 {
            let angle = CGFloat(step) * .pi / 3
            centres.append(CGPoint(x: centre.x + spacing * cos(angle), y: centre.y + spacing * sin(angle)))
        }
        for (index, point) in centres.enumerated() {
            let isCentre = index == 0
            let fill = isCentre ? PortalColor.white.withAlpha(0.96) : tint.lightened(0.55).withAlpha(0.5)
            ctx.setFillColor(fill.cgColor)
            ctx.setStrokeColor(fill.cgColor)
            ctx.setLineWidth(circumradius * 0.2)
            ctx.setLineJoin(.round)
            ctx.addPath(hexagon(center: point, circumradius: circumradius * 0.86))
            ctx.drawPath(using: .fillStroke)
        }
    }

    static func hexagon(center: CGPoint, circumradius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for corner in 0..<6 {
            let angle = CGFloat.pi / 6 + CGFloat(corner) * .pi / 3
            let point = CGPoint(x: center.x + circumradius * cos(angle), y: center.y + circumradius * sin(angle))
            if corner == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    /// A green disc with a white tick, shown on apps that are already installed.
    static func installedBadge(diameter: CGFloat, scale: CGFloat) -> CGImage? {
        render(size: CGSize(width: diameter, height: diameter), scale: scale) { ctx, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            ctx.setFillColor(PortalColor.white.cgColor)
            ctx.fillEllipse(in: rect)
            ctx.setFillColor(PortalColor(r: 0.19, g: 0.82, b: 0.35).cgColor)
            ctx.fillEllipse(in: rect.insetBy(dx: diameter * 0.07, dy: diameter * 0.07))
            ctx.setStrokeColor(PortalColor.white.cgColor)
            ctx.setLineWidth(diameter * 0.12)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.move(to: CGPoint(x: diameter * 0.3, y: diameter * 0.5))
            ctx.addLine(to: CGPoint(x: diameter * 0.45, y: diameter * 0.34))
            ctx.addLine(to: CGPoint(x: diameter * 0.72, y: diameter * 0.66))
            ctx.strokePath()
        }
    }

    /// A small frosted capsule carrying `text`, used for the "Mac" / "iPhone" platform badge.
    static func pill(text: String, scale: CGFloat, tint: PortalColor) -> CGImage? {
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, 11, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, 11, nil)
        let attributed = CFAttributedStringCreate(
            nil, text as CFString, [kCTFontAttributeName: font] as CFDictionary)!
        let width = ceil(CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(attributed), []).width) + 16
        return render(size: CGSize(width: width, height: 20), scale: scale) { ctx, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
            let path = CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil)
            ctx.addPath(path)
            ctx.setFillColor(PortalColor.space.withAlpha(0.82).cgColor)
            ctx.fillPath()
            ctx.addPath(path)
            ctx.setStrokeColor(tint.lightened(0.4).withAlpha(0.7).cgColor)
            ctx.setLineWidth(1)
            ctx.strokePath()
            drawText(ctx, text: text, font: font, color: PortalColor.white.withAlpha(0.95), centeredIn: CGRect(origin: .zero, size: size))
        }
    }

    /// A soft round star: a bright core fading to nothing.
    static func starDot(diameter: CGFloat, scale: CGFloat, tint: PortalColor) -> CGImage? {
        render(size: CGSize(width: diameter, height: diameter), scale: scale) { ctx, size in
            guard let glow = gradient(
                [tint.withAlpha(1), tint.withAlpha(0.55), tint.withAlpha(0)],
                locations: [0, 0.35, 1]
            ) else { return }
            ctx.drawRadialGradient(
                glow,
                startCenter: CGPoint(x: size.width / 2, y: size.height / 2), startRadius: 0,
                endCenter: CGPoint(x: size.width / 2, y: size.height / 2), endRadius: size.width / 2,
                options: []
            )
        }
    }
}
