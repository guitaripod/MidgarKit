import CoreGraphics
import Foundation
import QuartzCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// How often the portal asks the display to refresh. On a ProMotion screen every animation that
/// names no rate runs at whatever the system picks: 120 Hz on an iPad Pro, 48 Hz on an iPhone Air,
/// even while nothing but the stars moves. Slow ambient motion asks for 30 Hz, which divides both
/// 60 and 120, and anything that follows or answers a finger asks for the display's fastest single
/// rate (a range can settle in between, at 80 Hz).
enum PortalFrameRate {
    static let ambient = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)

    @MainActor static var motion: CAFrameRateRange {
        single(fastest)
    }

    static func single(_ rate: Float) -> CAFrameRateRange {
        CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
    }

    @MainActor static var fastest: Float {
        #if os(visionOS)
        return 90
        #elseif canImport(UIKit)
        return Float(UIScreen.main.maximumFramesPerSecond)
        #else
        return Float(NSScreen.main?.maximumFramesPerSecond ?? 60)
        #endif
    }
}

/// Where a cell was drawn on the last frame, in the canvas's top-left coordinate space.
struct PortalCellFrame: Sendable {
    let center: CGPoint
    let radius: CGFloat
    let depth: CGFloat
}

/// Carries a bitmap between the main actor and a background render. `CGImage` is immutable, so
/// reading it from another thread is safe.
struct PortalImageBox: @unchecked Sendable {
    let image: CGImage?
}

/// Everything an icon bitmap is drawn from: two cells with equal recipes show identical pixels, so
/// a recipe that has not changed is never drawn again.
private struct PortalIconRecipe: Equatable {
    let diameter: CGFloat
    let scale: CGFloat
    let accent: String
    let monogram: String
    let zoom: CGFloat
    let isCore: Bool
    let artwork: ObjectIdentifier?
}

/// One icon to draw away from the main thread.
private struct PortalIconJob: Sendable {
    let artwork: PortalImageBox
    let diameter: CGFloat
    let scale: CGFloat
    let accent: PortalColor
    let monogram: String
    let zoom: CGFloat
    let isCore: Bool

    func render() -> PortalImageBox {
        if isCore {
            return PortalImageBox(image: PortalArt.coreEmblem(diameter: diameter, scale: scale, tint: .midgar))
        }
        return PortalImageBox(image: PortalArt.circularIcon(
            source: artwork.image, diameter: diameter, scale: scale, accent: accent, monogram: monogram, zoom: zoom
        ))
    }
}

/// Draws the portal with Core Animation layers that only ever show bitmaps. Every icon, glow, ring
/// and dot is drawn once (icons on a background thread), so a frame is nothing more than setting
/// position, scale, opacity and depth on existing layers: no paths are rebuilt, nothing is
/// rasterised again, no layer leaves the tree and no layer needs an offscreen pass, which keeps a
/// flick at the display's full rate on an iPhone XS.
@MainActor
final class PortalRenderer {
    private struct Star {
        let layer: CALayer
        let base: CGPoint
        let depth: CGFloat
    }

    private final class CellLayers {
        var cell: PortalCell
        var app: MidgarApp?
        var accent: PortalColor
        let container = CALayer()
        let glow = CALayer()
        let body = CALayer()
        let installed = CALayer()
        let platform = CALayer()
        let marker = CALayer()
        let markerLabel = CALayer()
        var artwork: CGImage?
        var recipe: PortalIconRecipe?

        init(cell: PortalCell, app: MidgarApp?, accent: PortalColor) {
            self.cell = cell
            self.app = app
            self.accent = accent
        }

        var key: String { cell.appID ?? "core" }
    }

    /// A dotted line between two related apps, drawn as one dot repeated along it.
    private final class Link {
        let from: Int
        let to: Int
        let replicator = CAReplicatorLayer()
        let dot = CALayer()
        var isFocused: Bool?

        init(from: Int, to: Int) {
            self.from = from
            self.to = to
            replicator.addSublayer(dot)
        }
    }

    private enum Depth {
        static let stars: CGFloat = 0
        static let ghosts: CGFloat = 1
        static let links: CGFloat = 2
        static let cells: CGFloat = 10
    }

    static let flipsY: Bool = {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }()

    static let ghostSide: CGFloat = 6.8

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
    private var ghosts: [CALayer] = []
    private var links: [Link] = []
    private var points: [CGPoint] = []
    private var installedBundleIDs: Set<String> = []
    private var focusedIndex: Int?
    private var hostBundleID: String?
    private var progressFraction: CGFloat = 0
    private var hasViewport = false
    private let textures = PortalTextureCache()
    private let focusRing = CAShapeLayer()
    private let focusPing = CAShapeLayer()
    private let progressRing = CALayer()

    init(layout: PortalLayout, scale: CGFloat, reduceMotion: Bool) {
        self.layout = layout
        self.scale = scale
        self.reduceMotion = reduceMotion
        rootLayer.masksToBounds = false
        rootLayer.contentsScale = scale
        progressRing.contentsScale = scale
        progressRing.contentsGravity = .resize
        for (layer, width) in [(focusRing, 2.5), (focusPing, 2.0)] {
            layer.fillColor = nil
            layer.lineWidth = width
            layer.contentsScale = scale
        }
    }

    var baseDiameter: CGFloat { diameter }

    func setReduceMotion(_ value: Bool) {
        reduceMotion = value
        for entry in cells { applyIdleMotion(to: entry) }
    }

    /// Lays out a new set of apps. Cells whose app was already shown keep their layers and their
    /// drawn icon, so a refreshed catalog or a rotation never flashes or draws an icon again.
    func configure(
        layout: PortalLayout,
        apps: [String: MidgarApp],
        hostBundleID: String?,
        installed: Set<String>
    ) {
        self.layout = layout
        self.hostBundleID = hostBundleID?.lowercased()
        self.installedBundleIDs = installed
        detachFocus()
        var previous = Dictionary(cells.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        cells = layout.cells.map { cell in
            let app = cell.appID.flatMap { apps[$0] }
            let accent = app.map { PortalColor(hex: $0.accentHex) } ?? .midgar
            if let reused = previous.removeValue(forKey: cell.appID ?? "core") {
                reused.cell = cell
                reused.app = app
                reused.accent = accent
                reused.glow.opacity = 0.22
                return reused
            }
            let entry = CellLayers(cell: cell, app: app, accent: accent)
            buildLayers(for: entry)
            rootLayer.addSublayer(entry.container)
            return entry
        }
        for stale in previous.values { stale.container.removeFromSuperlayer() }
        frames = [:]
        points = Array(repeating: .zero, count: cells.count)
        rebuildLinks(apps: apps)
        rebuildGhosts()
        for entry in cells {
            applyIdleMotion(to: entry)
            guard hasViewport else { continue }
            sizeLayers(of: entry)
            requestIcon(for: entry)
        }
        if hasViewport { refreshBadges() }
    }

    func setViewport(size: CGSize, center: CGPoint, halfExtent: CGSize, diameter: CGFloat) {
        let firstViewport = !hasViewport
        let sizeChanged = size != self.size
        let diameterChanged = diameter != self.diameter || firstViewport
        guard sizeChanged || diameterChanged || center != self.center || halfExtent != lens.halfExtent else { return }
        hasViewport = true
        self.size = size
        self.center = center
        self.diameter = diameter
        lens = PortalLens(halfExtent: halfExtent)
        rootLayer.bounds = CGRect(origin: .zero, size: size)
        rootLayer.position = CGPoint(x: size.width / 2, y: size.height / 2)
        if sizeChanged { layoutStars() }
        guard diameterChanged else { return }
        for entry in cells {
            sizeLayers(of: entry)
            requestIcon(for: entry)
        }
        refreshBadges()
        if let focusedIndex, cells.indices.contains(focusedIndex) { attachFocusRing(to: cells[focusedIndex]) }
    }

    func setArtwork(_ image: CGImage, forApp appID: String) {
        guard let entry = cells.first(where: { $0.cell.appID == appID }) else { return }
        entry.artwork = image
        requestIcon(for: entry)
    }

    func setInstalled(_ bundleIDs: Set<String>) {
        guard bundleIDs != installedBundleIDs else { return }
        installedBundleIDs = bundleIDs
        refreshBadges()
    }

    /// Moves the focus ring and its pulse onto `index` and gives the cell a small pop.
    func setFocus(_ index: Int?, animated: Bool) {
        guard focusedIndex != index else { return }
        let previous = focusedIndex
        focusedIndex = index
        if let previous, cells.indices.contains(previous) { fade(cells[previous].glow, to: 0.22, animated: animated) }
        restyleLinks()
        guard let index, cells.indices.contains(index) else {
            detachFocus()
            return
        }
        let entry = cells[index]
        fade(entry.glow, to: 0.9, animated: animated)
        attachFocusRing(to: entry)
        if animated && !reduceMotion { pop(entry.body) }
    }

    func setProgress(_ fraction: CGFloat) {
        let clamped = max(0, min(1, fraction))
        guard clamped != progressFraction else { return }
        progressFraction = clamped
        if let core = cells.first(where: { $0.cell.isCore }) { attachProgress(to: core) }
    }

    /// Renders one frame. `intro` is the seconds since the portal opened.
    func render(camera: CGPoint, intro: TimeInterval) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        for (slot, entry) in cells.enumerated() {
            let progress = introProgress(of: entry.cell.index, elapsed: intro)
            let projection = lens.project(CGPoint(x: entry.cell.world.x - camera.x, y: entry.cell.world.y - camera.y))
            let point = CGPoint(
                x: center.x + projection.point.x * progress.travel,
                y: center.y + projection.point.y * progress.travel
            )
            let cellScale = projection.scale * progress.size
            points[slot] = point
            place(entry, at: point, scale: cellScale, alpha: progress.alpha * depthAlpha(projection.scale))
            frames[entry.cell.index] = PortalCellFrame(
                center: point,
                radius: diameter * cellScale / 2,
                depth: projection.scale
            )
        }
        moveGhosts(camera: camera, intro: intro)
        moveLinks()
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

    /// Nearer cells draw above farther ones through `zPosition`, which the compositor sorts, so the
    /// layer tree itself never changes while the camera moves.
    private func place(_ entry: CellLayers, at point: CGPoint, scale: CGFloat, alpha: CGFloat) {
        entry.container.position = layerPoint(point)
        entry.container.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        entry.container.opacity = Float(alpha)
        entry.container.zPosition = Depth.cells + scale
    }

    private func layerPoint(_ point: CGPoint) -> CGPoint {
        Self.flipsY ? CGPoint(x: point.x, y: size.height - point.y) : point
    }

    private func localPoint(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        Self.flipsY ? CGPoint(x: x, y: diameter - y) : CGPoint(x: x, y: y)
    }

    private func rebuildLinks(apps: [String: MidgarApp]) {
        for link in links { link.replicator.removeFromSuperlayer() }
        var seen = Set<String>()
        let byBundle = Dictionary(
            layout.cells.compactMap { cell -> (String, Int)? in
                cell.appID.flatMap { apps[$0] }.map { ($0.bundleId.lowercased(), cell.index) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        links = []
        for cell in layout.cells {
            guard let app = cell.appID.flatMap({ apps[$0] }) else { continue }
            for other in app.related {
                guard let target = byBundle[other.lowercased()], target != cell.index else { continue }
                let key = "\(min(cell.index, target))-\(max(cell.index, target))"
                guard seen.insert(key).inserted else { continue }
                let link = Link(from: cell.index, to: target)
                link.replicator.zPosition = Depth.links
                link.dot.contentsScale = scale
                rootLayer.addSublayer(link.replicator)
                links.append(link)
            }
        }
        restyleLinks()
    }

    /// Links that touch the focused cell are drawn as brighter dots in its colour, the rest as faint
    /// dashes. Only links whose role changed are touched.
    private func restyleLinks() {
        let accent = focusedIndex.flatMap { cells.indices.contains($0) ? cells[$0].accent : nil } ?? .midgar
        for link in links {
            let focused = link.from == focusedIndex || link.to == focusedIndex
            guard focused != link.isFocused || focused else { continue }
            link.isFocused = focused
            if focused {
                link.dot.bounds = CGRect(x: 0, y: 0, width: 2.6, height: 1.6)
                link.dot.cornerRadius = 0.8
                link.dot.backgroundColor = accent.lightened(0.3).withAlpha(0.75).cgColor
                link.replicator.instanceTransform = CATransform3DMakeTranslation(7, 0, 0)
            } else {
                link.dot.bounds = CGRect(x: 0, y: 0, width: 2, height: 1)
                link.dot.cornerRadius = 0.5
                link.dot.backgroundColor = PortalColor.white.withAlpha(0.1).cgColor
                link.replicator.instanceTransform = CATransform3DMakeTranslation(8, 0, 0)
            }
        }
    }

    private func moveLinks() {
        for link in links {
            guard points.indices.contains(link.from), points.indices.contains(link.to) else { continue }
            let from = layerPoint(points[link.from])
            let to = layerPoint(points[link.to])
            let dx = to.x - from.x
            let dy = to.y - from.y
            let spacing: CGFloat = link.isFocused == true ? 7 : 8
            link.replicator.position = from
            link.replicator.setAffineTransform(CGAffineTransform(rotationAngle: atan2(dy, dx)))
            link.replicator.instanceCount = max(0, Int(hypot(dx, dy) / spacing))
        }
    }

    private func rebuildGhosts() {
        let texture = textures.image("ghost") {
            PortalArt.dot(diameter: Self.ghostSide, scale: scale, color: PortalColor.white.withAlpha(0.28))
        }
        while ghosts.count < layout.ghosts.count {
            let layer = CALayer()
            layer.bounds = CGRect(x: 0, y: 0, width: Self.ghostSide, height: Self.ghostSide)
            layer.contents = texture
            layer.contentsScale = scale
            layer.zPosition = Depth.ghosts
            rootLayer.addSublayer(layer)
            ghosts.append(layer)
        }
        while ghosts.count > layout.ghosts.count {
            ghosts.removeLast().removeFromSuperlayer()
        }
    }

    private func moveGhosts(camera: CGPoint, intro: TimeInterval) {
        let reveal = reduceMotion ? 1 : CGFloat(max(0, min(1, (intro - 0.3) / 0.8)))
        for (layer, world) in zip(ghosts, layout.ghosts) {
            let projection = lens.project(CGPoint(x: world.x - camera.x, y: world.y - camera.y))
            let point = layerPoint(CGPoint(x: center.x + projection.point.x, y: center.y + projection.point.y))
            let visible = reveal > 0 && point.x > -20 && point.x < size.width + 20 && point.y > -20 && point.y < size.height + 20
            layer.isHidden = !visible
            guard visible else { continue }
            let radius = max(1.2, 3.4 * projection.scale) * reveal
            let factor = radius * 2 / Self.ghostSide
            layer.position = point
            layer.setAffineTransform(CGAffineTransform(scaleX: factor, y: factor))
        }
    }

    private func buildLayers(for entry: CellLayers) {
        let container = entry.container
        container.contentsScale = scale
        container.masksToBounds = false
        container.allowsGroupOpacity = false
        for layer in [entry.glow, entry.body, entry.installed, entry.platform, entry.marker, entry.markerLabel] {
            layer.contentsScale = scale
            layer.contentsGravity = .resize
            container.addSublayer(layer)
        }
        entry.glow.opacity = 0.22
        entry.installed.isHidden = true
        entry.platform.isHidden = true
        entry.marker.isHidden = true
        entry.markerLabel.isHidden = true
    }

    private func sizeLayers(of entry: CellLayers) {
        let d = diameter
        let middle = CGPoint(x: d / 2, y: d / 2)
        entry.container.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        entry.glow.bounds = CGRect(x: 0, y: 0, width: d * 1.9, height: d * 1.9)
        entry.glow.position = middle
        entry.glow.contents = textures.image("glow|\(d)|\(entry.accent.hashKey)") {
            PortalArt.glow(diameter: d * 1.9, scale: 1, accent: entry.accent)
        }
        entry.body.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        entry.body.position = middle
        entry.marker.bounds = CGRect(x: 0, y: 0, width: d + 20, height: d + 20)
        entry.marker.position = middle
        entry.marker.contents = textures.image("marker|\(d)") {
            PortalArt.ring(side: d + 20, radius: d / 2 + 7, lineWidth: 1.6, scale: scale, color: PortalColor.white.withAlpha(0.7), dash: [3, 6])
        }
        let badge = max(20, d * 0.24)
        entry.installed.bounds = CGRect(x: 0, y: 0, width: badge, height: badge)
        entry.installed.position = localPoint(d * 0.82, d * 0.82)
        entry.installed.contents = textures.image("installed|\(badge)") {
            PortalArt.installedBadge(diameter: badge, scale: scale)
        }
        if entry.cell.isCore { attachProgress(to: entry) }
    }

    /// Asks for the icon bitmap when what it is drawn from has changed. It is drawn on a background
    /// thread and fades in when ready; an answer for a recipe that has since changed is dropped.
    private func requestIcon(for entry: CellLayers) {
        let zoom: CGFloat = (entry.app?.platforms == [.mac]) ? 1.2 : 1.0
        let recipe = PortalIconRecipe(
            diameter: diameter,
            scale: scale,
            accent: entry.accent.hashKey,
            monogram: entry.app?.monogram ?? "M",
            zoom: zoom,
            isCore: entry.cell.isCore,
            artwork: entry.artwork.map(ObjectIdentifier.init)
        )
        guard hasViewport, entry.recipe != recipe else { return }
        entry.recipe = recipe
        let job = PortalIconJob(
            artwork: PortalImageBox(image: entry.artwork),
            diameter: diameter,
            scale: scale,
            accent: entry.accent,
            monogram: recipe.monogram,
            zoom: zoom,
            isCore: recipe.isCore
        )
        Task { @MainActor [weak entry] in
            let drawn = await Task.detached(priority: .userInitiated) { job.render() }.value
            guard let entry, entry.recipe == recipe, let image = drawn.image else { return }
            entry.body.contents = image
        }
    }

    private func attachProgress(to entry: CellLayers) {
        let side = diameter + 24
        progressRing.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        progressRing.position = CGPoint(x: diameter / 2, y: diameter / 2)
        progressRing.contents = PortalArt.progressRing(
            side: side, radius: diameter / 2 + 9, fraction: progressFraction, scale: scale, tint: .midgar
        )
        if progressRing.superlayer !== entry.container { entry.container.addSublayer(progressRing) }
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
               let pill = textures.image("pill|\(foreign.rawValue)|\(entry.accent.hashKey)", {
                   PortalArt.pill(text: foreign.badgeLabel, scale: scale, tint: entry.accent)
               }) {
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
        let label = textures.image("here|\(entry.accent.hashKey)") {
            PortalArt.pill(text: MidgarStrings.youAreHere, scale: scale, tint: entry.accent)
        }
        entry.markerLabel.contents = label
        let width = CGFloat(label?.width ?? 0) / scale
        entry.markerLabel.bounds = CGRect(x: 0, y: 0, width: width, height: 20)
        entry.markerLabel.position = localPoint(diameter / 2, diameter * 1.1)
        if reduceMotion {
            entry.marker.removeAnimation(forKey: "spin")
        } else if entry.marker.animation(forKey: "spin") == nil {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = Double.pi * 2
            spin.duration = 30
            spin.repeatCount = .infinity
            spin.preferredFrameRateRange = PortalFrameRate.ambient
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
        bob.preferredFrameRateRange = PortalFrameRate.ambient
        entry.body.add(bob, forKey: "bob")
    }

    private func detachFocus() {
        focusRing.removeFromSuperlayer()
        focusPing.removeFromSuperlayer()
        focusPing.removeAllAnimations()
        focusedIndex = nil
    }

    /// The ring and its pulse are one stroked circle each, shaped once per size: moving the focus to
    /// an app of another colour only changes the stroke colour, with no bitmap drawn on this thread.
    private func attachFocusRing(to entry: CellLayers) {
        let radius = diameter / 2 + 5
        let side = radius * 2
        let ring = entry.accent.lightened(0.25)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        focusRing.strokeColor = ring.withAlpha(0.95).cgColor
        focusPing.strokeColor = ring.withAlpha(0.6).cgColor
        for layer in [focusRing, focusPing] {
            if layer.bounds.width != side {
                layer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
                layer.path = CGPath(ellipseIn: layer.bounds, transform: nil)
            }
            layer.position = CGPoint(x: diameter / 2, y: diameter / 2)
            if layer.superlayer !== entry.container {
                layer.removeFromSuperlayer()
                entry.container.insertSublayer(layer, above: entry.body)
            }
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
        group.preferredFrameRateRange = PortalFrameRate.ambient
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
        spring.preferredFrameRateRange = PortalFrameRate.motion
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
        animation.preferredFrameRateRange = PortalFrameRate.motion
        layer.add(animation, forKey: "focusGlow")
    }

    private func layoutStars() {
        for star in stars { star.layer.removeFromSuperlayer() }
        stars.removeAll()
        guard size.width > 0, size.height > 0 else { return }
        var generator = SeededGenerator(seed: 0x4D49_4447_4152)
        let tints = [PortalColor.white, PortalColor(r: 0.75, g: 0.85, b: 1), PortalColor(r: 1, g: 0.9, b: 0.75)]
        let count = Int(min(90, max(40, size.width * size.height / 9000)))
        let starTextures = tints.map { tint in
            textures.image("star|\(tint.hashKey)") { PortalArt.starDot(diameter: 8, scale: scale, tint: tint) }
        }
        for index in 0..<count {
            let depth = [0.05, 0.1, 0.18][index % 3]
            let layer = CALayer()
            let side = CGFloat.random(in: 2.5...(5 + CGFloat(index % 3) * 2), using: &generator)
            layer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            layer.contents = starTextures[Int.random(in: 0..<starTextures.count, using: &generator)]
            layer.contentsScale = scale
            layer.contentsGravity = .resize
            layer.zPosition = Depth.stars
            layer.opacity = Float.random(in: 0.25...0.9, using: &generator)
            let twinkleTo = Float.random(in: 0.1...0.4, using: &generator)
            let twinkleFor = Double.random(in: 1.8...4.2, using: &generator)
            let twinkleAt = Double.random(in: 0...3, using: &generator)
            if !reduceMotion {
                let twinkle = CABasicAnimation(keyPath: "opacity")
                twinkle.fromValue = layer.opacity
                twinkle.toValue = twinkleTo
                twinkle.duration = twinkleFor
                twinkle.autoreverses = true
                twinkle.repeatCount = .infinity
                twinkle.timeOffset = twinkleAt
                twinkle.preferredFrameRateRange = PortalFrameRate.ambient
                layer.add(twinkle, forKey: "twinkle")
            }
            rootLayer.addSublayer(layer)
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
