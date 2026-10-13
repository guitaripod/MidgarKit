import CoreGraphics

/// Where a world-space offset from the camera lands on screen, and how large it is drawn.
struct PortalProjection: Sendable {
    let point: CGPoint
    let scale: CGFloat
}

/// The fisheye that gives the honeycomb its depth: cells near the centre keep their full size and
/// spacing, and everything farther out bunches together and shrinks toward the edges of the
/// screen. The reach is elliptical so a tall phone screen is filled instead of a central disc.
struct PortalLens: Sendable {
    var halfExtent: CGSize
    var minimumScale: CGFloat = 0.3
    var compression: CGFloat = 0.8
    var falloff: CGFloat = 0.85
    var falloffPower: CGFloat = 1.55

    func project(_ offset: CGPoint) -> PortalProjection {
        guard halfExtent.width > 0, halfExtent.height > 0 else { return PortalProjection(point: offset, scale: 1) }
        let nx = offset.x / halfExtent.width
        let ny = offset.y / halfExtent.height
        let distance = hypot(nx, ny)
        guard distance > 0.000_001 else { return PortalProjection(point: .zero, scale: 1) }
        let displayed = (1 - exp(-distance * compression)) / compression
        let ratio = displayed / distance
        return PortalProjection(
            point: CGPoint(x: nx * ratio * halfExtent.width, y: ny * ratio * halfExtent.height),
            scale: scale(atNormalizedDistance: distance)
        )
    }

    func scale(atNormalizedDistance distance: CGFloat) -> CGFloat {
        max(minimumScale, 1 / (1 + falloff * pow(distance, falloffPower)))
    }
}
