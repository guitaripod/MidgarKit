import CoreGraphics
import Foundation
import QuartzCore

/// Where a cell was drawn on the last frame, in the canvas's top-left coordinate space.
struct PortalCellFrame: Sendable {
    let center: CGPoint
    let radius: CGFloat
    let depth: CGFloat
}

/// Draws the portal with Core Animation layers only. Every cell is a handful of pre-rendered
/// textures; a frame is nothing more than setting position, scale and opacity on those layers, so
/// the GPU does all the drawing and a flick stays smooth at the display's full refresh rate.
@MainActor
final class PortalRenderer {
    private struct Star {
        let layer: CALayer
        let base: CGPoint
        let depth: CGFloat
    }

    private final class CellLayers {
        let cell: PortalCell
        let app: MidgarApp?
        let accent: PortalColor
        let container = CALayer()
        let glow = CAGradientLayer()
        let body = CALayer()
        let installed = CALayer()
        let platform = CALayer()
        let marker = CAShapeLayer()
        let markerLabel = CALayer()
        var artwork: CGImage?

        init(cell: PortalCell, app: MidgarApp?, accent: PortalColor) {
            self.cell = cell
            self.app = app
            self.accent = accent
        }
    }

    static let flipsY: Bool = {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }()

    let rootLayer = CALayer()

    private(set) var frames: [Int: PortalCellFrame] = [:]
    private(set) var layout: PortalLayout
    private let scale: CGFloat
    private var reduceMotion: Bool
    private var size: CGSize = .zero
    private var center: CGPoint = .zero
    private var diameter: CGFloat = 100
    private var lens = PortalLens(halfExtent: CGSize(width: 1, height: 1))
    private var cells: [CellLayers] = []
    private var stars: [Star] = []
    private var links: [(Int, Int)] = []
    private var installedBundleIDs: Set<String> = []
    private var focusedIndex: Int?
    private var drawOrder: [Int] = []
    private var hostBundleID: String?
    private let ghostLayer = CAShapeLayer()
    private let linkLayer = CAShapeLayer()
    private let focusLinkLayer = CAShapeLayer()
    private let focusRing = CAShapeLayer()
    private let focusPing = CAShapeLayer()
    private let progressTrack = CAShapeLayer()
    private let progressArc = CAShapeLayer()

    init(layout: PortalLayout, scale: CGFloat, reduceMotion: Bool) {
        self.layout = layout
        self.scale = scale
        self.reduceMotion = reduceMotion
        rootLayer.masksToBounds = false
        rootLayer.contentsScale = scale
        configureShapeLayers()
    }

    var baseDiameter: CGFloat { diameter }

    func setReduceMotion(_ value: Bool) {
        reduceMotion = value
        for entry in cells { applyIdleMotion(to: entry) }
    }

    /// Rebuilds every cell for a new set of apps.
    func configure(
        layout: PortalLayout,
        apps: [String: MidgarApp],
        hostBundleID: String?,
        installed: Set<String>
    ) {
        self.layout = layout
        self.hostBundleID = hostBundleID?.lowercased()
        self.installedBundleIDs = installed
        let previousArtwork = Dictionary(uniqueKeysWithValues: cells.compactMap { entry in
            entry.cell.appID.flatMap { id in entry.artwork.map { (id, $0) } }
        })
        for entry in cells { entry.container.removeFromSuperlayer() }
        drawOrder = []
        cells = layout.cells.map { cell in
            let app = cell.appID.flatMap { apps[$0] }
            let accent = app.map { PortalColor(hex: $0.accentHex) } ?? .midgar
            let entry = CellLayers(cell: cell, app: app, accent: accent)
            entry.artwork = cell.appID.flatMap { previousArtwork[$0] }
            return entry
        }
        links = buildLinks(apps: apps)
        for entry in cells {
            buildLayers(for: entry)
            rootLayer.addSublayer(entry.container)
        }
        rebuildTextures()
        refreshBadges()
    }

    func setViewport(size: CGSize, center: CGPoint, halfExtent: CGSize, diameter: CGFloat) {
        self.size = size
        self.center = center
        self.diameter = diameter
        lens = PortalLens(halfExtent: halfExtent)
        rootLayer.bounds = CGRect(origin: .zero, size: size)
        rootLayer.position = CGPoint(x: size.width / 2, y: size.height / 2)
        layoutStars()
        for entry in cells { sizeLayers(of: entry) }
        rebuildTextures()
        refreshBadges()
    }

    func setArtwork(_ image: CGImage, forApp appID: String) {
        guard let entry = cells.first(where: { $0.cell.appID == appID }) else { return }
        entry.artwork = image
        applyIcon(to: entry)
    }

    func setInstalled(_ bundleIDs: Set<String>) {
        installedBundleIDs = bundleIDs
        refreshBadges()
    }

    /// Moves the focus ring and its pulse onto `index` and gives the cell a small pop.
    func setFocus(_ index: Int?, animated: Bool) {
        guard focusedIndex != index else { return }
        let previous = focusedIndex
        focusedIndex = index
        if let previous, cells.indices.contains(previous) { fade(cells[previous].glow, to: 0.22, animated: animated) }
        guard let index, cells.indices.contains(index) else {
            focusRing.removeFromSuperlayer()
            focusPing.removeFromSuperlayer()
            return
        }
        let entry = cells[index]
        fade(entry.glow, to: 0.9, animated: animated)
        attachFocusRing(to: entry)
        if animated && !reduceMotion { pop(entry.body) }
    }

    func setProgress(_ fraction: CGFloat) {
        progressArc.strokeEnd = max(0.001, min(1, fraction))
    }

    /// Renders one frame. `intro` is the seconds since the portal opened.
    func render(camera: CGPoint, intro: TimeInterval) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        var projected: [Int: (point: CGPoint, scale: CGFloat)] = [:]
        projected.reserveCapacity(cells.count)
        for entry in cells {
            let progress = introProgress(of: entry.cell.index, elapsed: intro)
            let projection = lens.project(CGPoint(x: entry.cell.world.x - camera.x, y: entry.cell.world.y - camera.y))
            let point = CGPoint(
                x: center.x + projection.point.x * progress.travel,
                y: center.y + projection.point.y * progress.travel
            )
            let cellScale = projection.scale * progress.size
            projected[entry.cell.index] = (point, cellScale)
            place(entry, at: point, scale: cellScale, alpha: progress.alpha * depthAlpha(projection.scale))
            frames[entry.cell.index] = PortalCellFrame(
                center: point,
                radius: diameter * cellScale / 2,
                depth: projection.scale
            )
        }
        orderCells(by: projected.mapValues(\.scale))
        drawGhosts(camera: camera, intro: intro)
        drawLinks(projected: projected)
        moveStars(camera: camera)
    }

    func cell(at point: CGPoint) -> PortalCell? {
        let hit = frames
            .sorted { $0.value.depth > $1.value.depth }
            .first { entry in
                let frame = entry.value
                return hypot(point.x - frame.center.x, point.y - frame.center.y) <= max(frame.radius + 6, 26)
                    && cells.indices.contains(entry.key)
            }
        return hit.map { cells[$0.key].cell }
    }

    func isIntroComplete(at elapsed: TimeInterval) -> Bool {
        elapsed >= introDuration
    }

    var introDuration: TimeInterval {
        reduceMotion ? 0 : 0.035 * Double(cells.count) + 0.6
    }

    private func introProgress(of index: Int, elapsed: TimeInterval) -> (travel: CGFloat, size: CGFloat, alpha: CGFloat) {
        guard !reduceMotion else { return (1, 1, 1) }
        let raw = max(0, min(1, (elapsed - 0.035 * Double(index)) / 0.55))
        let eased = CGFloat(1 - pow(1 - raw, 3))
        let overshoot = CGFloat(raw) < 1 ? eased * (1 + 0.08 * sin(CGFloat(raw) * .pi)) : 1
        return (eased, overshoot, min(1, CGFloat(raw) * 2.2))
    }

    private func depthAlpha(_ lensScale: CGFloat) -> CGFloat {
        let t = max(0, min(1, (lensScale - lens.minimumScale) / (0.8 - lens.minimumScale)))
        return 0.5 + 0.5 * t * t * (3 - 2 * t)
    }

    private func place(_ entry: CellLayers, at point: CGPoint, scale: CGFloat, alpha: CGFloat) {
        entry.container.position = layerPoint(point)
        entry.container.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        entry.container.opacity = Float(alpha)
    }

    /// Keeps larger, nearer cells above smaller ones by ordering sublayers, and only touches the
    /// layer tree when the order actually changes.
    private func orderCells(by scales: [Int: CGFloat]) {
        let wanted = cells.indices.sorted { (scales[$0] ?? 0) < (scales[$1] ?? 0) }
        guard wanted != drawOrder else { return }
        drawOrder = wanted
        for index in wanted {
            cells[index].container.removeFromSuperlayer()
            rootLayer.addSublayer(cells[index].container)
        }
    }

    private func layerPoint(_ point: CGPoint) -> CGPoint {
        Self.flipsY ? CGPoint(x: point.x, y: size.height - point.y) : point
    }

    private func localPoint(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        Self.flipsY ? CGPoint(x: x, y: diameter - y) : CGPoint(x: x, y: y)
    }

    private func configureShapeLayers() {
        ghostLayer.fillColor = PortalColor.white.withAlpha(0.28).cgColor
        ghostLayer.strokeColor = nil
        linkLayer.fillColor = nil
        linkLayer.strokeColor = PortalColor.white.withAlpha(0.1).cgColor
        linkLayer.lineWidth = 1
        linkLayer.lineDashPattern = [2, 6]
        linkLayer.lineCap = .round
        focusLinkLayer.fillColor = nil
        focusLinkLayer.lineWidth = 1.6
        focusLinkLayer.lineDashPattern = [1, 6]
        focusLinkLayer.lineCap = .round
        focusRing.fillColor = nil
        focusRing.lineWidth = 2.5
        focusPing.fillColor = nil
        focusPing.lineWidth = 2
        progressTrack.fillColor = nil
        progressTrack.lineWidth = 3
        progressTrack.strokeColor = PortalColor.white.withAlpha(0.12).cgColor
        progressArc.fillColor = nil
        progressArc.lineWidth = 3
        progressArc.lineCap = .round
        progressArc.strokeEnd = 0.001
        for layer in [ghostLayer, linkLayer, focusLinkLayer] { rootLayer.addSublayer(layer) }
    }

    private func buildLinks(apps: [String: MidgarApp]) -> [(Int, Int)] {
        var seen = Set<String>()
        var pairs: [(Int, Int)] = []
        let byBundle = Dictionary(uniqueKeysWithValues: layout.cells.compactMap { cell -> (String, Int)? in
            cell.appID.flatMap { apps[$0] }.map { ($0.bundleId.lowercased(), cell.index) }
        })
        for cell in layout.cells {
            guard let app = cell.appID.flatMap({ apps[$0] }) else { continue }
            for other in app.related {
                guard let target = byBundle[other.lowercased()], target != cell.index else { continue }
                let key = "\(min(cell.index, target))-\(max(cell.index, target))"
                if seen.insert(key).inserted { pairs.append((cell.index, target)) }
            }
        }
        return pairs
    }

    private func buildLayers(for entry: CellLayers) {
        let container = entry.container
        container.contentsScale = scale
        container.masksToBounds = false
        entry.glow.type = .radial
        entry.glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        entry.glow.endPoint = CGPoint(x: 1, y: 1)
        entry.glow.colors = [
            entry.accent.withAlpha(0.55).cgColor,
            entry.accent.withAlpha(0.18).cgColor,
            entry.accent.withAlpha(0).cgColor,
        ]
        entry.glow.locations = [0, 0.45, 1]
        entry.glow.opacity = 0.22
        entry.body.contentsScale = scale
        entry.body.contentsGravity = .resize
        entry.installed.contentsScale = scale
        entry.installed.isHidden = true
        entry.platform.contentsScale = scale
        entry.platform.isHidden = true
        entry.marker.fillColor = nil
        entry.marker.strokeColor = PortalColor.white.withAlpha(0.7).cgColor
        entry.marker.lineWidth = 1.6
        entry.marker.lineDashPattern = [3, 6]
        entry.marker.lineCap = .round
        entry.marker.isHidden = true
        entry.markerLabel.contentsScale = scale
        entry.markerLabel.isHidden = true
        for layer in [entry.glow, entry.body, entry.installed, entry.platform, entry.marker, entry.markerLabel] {
            container.addSublayer(layer)
        }
        sizeLayers(of: entry)
        applyIdleMotion(to: entry)
    }

    private func sizeLayers(of entry: CellLayers) {
        let d = diameter
        entry.container.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        entry.glow.bounds = CGRect(x: 0, y: 0, width: d * 1.9, height: d * 1.9)
        entry.glow.position = CGPoint(x: d / 2, y: d / 2)
        entry.body.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        entry.body.position = CGPoint(x: d / 2, y: d / 2)
        entry.marker.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        entry.marker.position = CGPoint(x: d / 2, y: d / 2)
        let markerRect = CGRect(x: -7, y: -7, width: d + 14, height: d + 14)
        entry.marker.path = CGPath(ellipseIn: markerRect, transform: nil)
        let badge = max(20, d * 0.24)
        entry.installed.bounds = CGRect(x: 0, y: 0, width: badge, height: badge)
        entry.installed.position = localPoint(d * 0.82, d * 0.82)
        entry.installed.contents = PortalArt.installedBadge(diameter: badge, scale: scale)
    }

    private func rebuildTextures() {
        for entry in cells { applyIcon(to: entry) }
    }

    private func applyIcon(to entry: CellLayers) {
        if entry.cell.isCore {
            let image = PortalArt.coreEmblem(diameter: diameter, scale: scale, tint: .midgar)
            entry.body.contents = image
            attachProgress(to: entry)
            return
        }
        let zoom: CGFloat = (entry.app?.platforms == [.mac]) ? 1.2 : 1.0
        entry.body.contents = PortalArt.circularIcon(
            source: entry.artwork,
            diameter: diameter,
            scale: scale,
            accent: entry.accent,
            monogram: entry.app?.monogram ?? "M",
            zoom: zoom
        )
    }

    private func attachProgress(to entry: CellLayers) {
        let path = progressPath(radius: diameter / 2 + 9)
        for layer in [progressTrack, progressArc] {
            layer.removeFromSuperlayer()
            layer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            layer.position = CGPoint(x: diameter / 2, y: diameter / 2)
            layer.path = path
            entry.container.addSublayer(layer)
        }
        progressArc.strokeColor = PortalColor.midgar.lightened(0.45).cgColor
    }

    /// A circle that starts at twelve o'clock and runs clockwise on screen, built from points so it
    /// reads the same whichever way the platform's layer coordinates point.
    private func progressPath(radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let segments = 120
        for step in 0...segments {
            let angle = CGFloat(step) / CGFloat(segments) * 2 * .pi
            let point = localPoint(diameter / 2 + radius * sin(angle), diameter / 2 - radius * cos(angle))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    private func refreshBadges() {
        for entry in cells {
            guard let app = entry.app else { continue }
            let isHost = app.bundleId.lowercased() == hostBundleID
            entry.installed.isHidden = isHost || !installedBundleIDs.contains(app.bundleId.lowercased())
            entry.marker.isHidden = !isHost
            entry.markerLabel.isHidden = !isHost
            if isHost { configureHostMarker(entry) }
            if let foreign = app.foreignPlatform,
               let pill = PortalArt.pill(text: foreign.badgeLabel, scale: scale, tint: entry.accent) {
                entry.platform.contents = pill
                entry.platform.bounds = CGRect(x: 0, y: 0, width: CGFloat(pill.width) / scale, height: 20)
                entry.platform.position = localPoint(diameter / 2, diameter * 0.96)
                entry.platform.isHidden = false
            } else {
                entry.platform.isHidden = true
            }
        }
    }

    private func configureHostMarker(_ entry: CellLayers) {
        let label = PortalArt.pill(text: "You are here", scale: scale, tint: entry.accent)
        entry.markerLabel.contents = label
        let width = CGFloat(label?.width ?? 0) / scale
        entry.markerLabel.bounds = CGRect(x: 0, y: 0, width: width, height: 20)
        entry.markerLabel.position = localPoint(diameter / 2, diameter * 1.1)
        if !reduceMotion, entry.marker.animation(forKey: "spin") == nil {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = Double.pi * 2
            spin.duration = 30
            spin.repeatCount = .infinity
            entry.marker.add(spin, forKey: "spin")
        }
    }

    private func applyIdleMotion(to entry: CellLayers) {
        entry.body.removeAnimation(forKey: "bob")
        guard !reduceMotion, !entry.cell.isCore else { return }
        let bob = CABasicAnimation(keyPath: "transform.translation.y")
        bob.fromValue = -2.4
        bob.toValue = 2.4
        bob.duration = 3.0 + Double(entry.cell.index % 5) * 0.37
        bob.autoreverses = true
        bob.repeatCount = .infinity
        bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        bob.timeOffset = Double(entry.cell.index) * 0.61
        entry.body.add(bob, forKey: "bob")
    }

    private func attachFocusRing(to entry: CellLayers) {
        let r = diameter / 2 + 5
        let rect = CGRect(x: diameter / 2 - r, y: diameter / 2 - r, width: r * 2, height: r * 2)
        let path = CGPath(ellipseIn: rect, transform: nil)
        for layer in [focusRing, focusPing] {
            layer.removeFromSuperlayer()
            layer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            layer.position = CGPoint(x: diameter / 2, y: diameter / 2)
            layer.path = path
            layer.strokeColor = entry.accent.lightened(0.25).withAlpha(layer === focusRing ? 0.95 : 0.6).cgColor
            entry.container.insertSublayer(layer, above: entry.body)
        }
        focusPing.removeAllAnimations()
        guard !reduceMotion else { return }
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1.0
        grow.toValue = 1.32
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.8
        fade.toValue = 0.0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 1.9
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        focusPing.add(group, forKey: "ping")
    }

    private func pop(_ layer: CALayer) {
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = 0.9
        spring.toValue = 1.0
        spring.mass = 1
        spring.stiffness = 220
        spring.damping = 9
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "pop")
    }

    private func fade(_ layer: CALayer, to value: Float, animated: Bool) {
        let from = layer.presentation()?.opacity ?? layer.opacity
        layer.opacity = value
        guard animated, !reduceMotion else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = value
        animation.duration = 0.35
        layer.add(animation, forKey: "focusGlow")
    }

    private func drawGhosts(camera: CGPoint, intro: TimeInterval) {
        let path = CGMutablePath()
        let reveal = reduceMotion ? 1 : CGFloat(max(0, min(1, (intro - 0.3) / 0.8)))
        for world in layout.ghosts {
            let projection = lens.project(CGPoint(x: world.x - camera.x, y: world.y - camera.y))
            let point = layerPoint(CGPoint(x: center.x + projection.point.x, y: center.y + projection.point.y))
            guard point.x > -20, point.x < size.width + 20, point.y > -20, point.y < size.height + 20 else { continue }
            let radius = max(1.2, 3.4 * projection.scale) * reveal
            path.addEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        }
        ghostLayer.path = path
    }

    private func drawLinks(projected: [Int: (point: CGPoint, scale: CGFloat)]) {
        let base = CGMutablePath()
        let focus = CGMutablePath()
        for (a, b) in links {
            guard let from = projected[a], let to = projected[b] else { continue }
            let target = (a == focusedIndex || b == focusedIndex) ? focus : base
            target.move(to: layerPoint(from.point))
            target.addLine(to: layerPoint(to.point))
        }
        linkLayer.path = base
        focusLinkLayer.path = focus
        if let index = focusedIndex, cells.indices.contains(index) {
            focusLinkLayer.strokeColor = cells[index].accent.lightened(0.3).withAlpha(0.75).cgColor
        }
    }

    private func layoutStars() {
        for star in stars { star.layer.removeFromSuperlayer() }
        stars.removeAll()
        guard size.width > 0, size.height > 0 else { return }
        var generator = SeededGenerator(seed: 0x4D49_4447_4152)
        let tints = [PortalColor.white, PortalColor(r: 0.75, g: 0.85, b: 1), PortalColor(r: 1, g: 0.9, b: 0.75)]
        let count = Int(min(90, max(40, size.width * size.height / 9000)))
        let textures = tints.map { PortalArt.starDot(diameter: 8, scale: scale, tint: $0) }
        for index in 0..<count {
            let depth = [0.05, 0.1, 0.18][index % 3]
            let layer = CALayer()
            let side = CGFloat.random(in: 2.5...(5 + CGFloat(index % 3) * 2), using: &generator)
            layer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            layer.contents = textures[Int.random(in: 0..<textures.count, using: &generator)]
            layer.contentsScale = scale
            layer.opacity = Float.random(in: 0.25...0.9, using: &generator)
            if !reduceMotion {
                let twinkle = CABasicAnimation(keyPath: "opacity")
                twinkle.fromValue = layer.opacity
                twinkle.toValue = Float.random(in: 0.1...0.4, using: &generator)
                twinkle.duration = Double.random(in: 1.8...4.2, using: &generator)
                twinkle.autoreverses = true
                twinkle.repeatCount = .infinity
                twinkle.timeOffset = Double.random(in: 0...3, using: &generator)
                layer.add(twinkle, forKey: "twinkle")
            }
            rootLayer.insertSublayer(layer, at: 0)
            stars.append(Star(
                layer: layer,
                base: CGPoint(
                    x: CGFloat.random(in: 0...size.width, using: &generator),
                    y: CGFloat.random(in: 0...size.height, using: &generator)
                ),
                depth: CGFloat(depth)
            ))
        }
    }

    private func moveStars(camera: CGPoint) {
        let width = size.width + 40
        let height = size.height + 40
        for star in stars {
            var x = (star.base.x - camera.x * star.depth).truncatingRemainder(dividingBy: width)
            var y = (star.base.y - camera.y * star.depth).truncatingRemainder(dividingBy: height)
            if x < 0 { x += width }
            if y < 0 { y += height }
            star.layer.position = layerPoint(CGPoint(x: x - 20, y: y - 20))
        }
    }
}

/// A small deterministic generator so the starfield looks the same every time the portal opens.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
