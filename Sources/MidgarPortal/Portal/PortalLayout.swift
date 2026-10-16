import MidgarUI

/// One spot in the portal: the Midgar core at the centre, or an app on the lattice around it.
struct PortalCell: Hashable, Sendable {
    enum Content: Hashable, Sendable {
        case core
        case app(String)
    }

    let index: Int
    let hex: HexCoordinate
    let world: CGPoint
    let content: Content

    var appID: String? {
        if case .app(let id) = content { return id }
        return nil
    }

    var isCore: Bool { content == .core }
}

/// Where everything sits in world space. The core owns the origin; ranked apps fill the rings
/// outward so the most relevant ones are the nearest neighbours of the core.
struct PortalLayout: Sendable {
    let pitch: CGFloat
    let cells: [PortalCell]
    let ghosts: [CGPoint]
    let reach: CGFloat

    var core: PortalCell { cells[0] }

    func cell(forApp appID: String) -> PortalCell? {
        cells.first { $0.appID == appID }
    }

    func nearestCell(to point: CGPoint) -> PortalCell {
        cells.min { squaredDistance($0.world, point) < squaredDistance($1.world, point) } ?? core
    }

    /// The closest cell lying within a cone around `direction`, for keyboard and remote
    /// navigation. `nil` when nothing lies that way.
    func neighbor(of cell: PortalCell, toward direction: CGVector) -> PortalCell? {
        let length = hypot(direction.dx, direction.dy)
        guard length > 0 else { return nil }
        let unit = CGVector(dx: direction.dx / length, dy: direction.dy / length)
        let cone = cos(CGFloat.pi / 3)
        return cells
            .filter { $0 != cell }
            .compactMap { candidate -> (PortalCell, CGFloat)? in
                let dx = candidate.world.x - cell.world.x
                let dy = candidate.world.y - cell.world.y
                let distance = hypot(dx, dy)
                guard distance > 0, (dx * unit.dx + dy * unit.dy) / distance >= cone else { return nil }
                return (candidate, distance)
            }
            .min { $0.1 < $1.1 }?.0
    }

    var snapPoints: [CGPoint] { cells.map(\.world) }

    /// Lays out `appIDs`, already ranked best first, around the core.
    static func make(appIDs: [String], pitch: CGFloat, rowStretch: CGFloat = 1, ghostRings: Int = 2) -> PortalLayout {
        var cells = [PortalCell(index: 0, hex: .origin, world: .zero, content: .core)]
        var remaining = appIDs[...]
        var ring = 1
        while !remaining.isEmpty {
            let slots = HexLattice.ring(ring)
            let used = HexLattice.evenlySpaced(slots, count: min(remaining.count, slots.count))
            for hex in used {
                guard let id = remaining.popFirst() else { break }
                cells.append(PortalCell(
                    index: cells.count,
                    hex: hex,
                    world: HexLattice.worldPoint(of: hex, pitch: pitch, rowStretch: rowStretch),
                    content: .app(id)
                ))
            }
            ring += 1
        }

        let occupied = Set(cells.map(\.hex))
        let outer = max(ring - 1, 1) + ghostRings
        let ghosts = HexLattice.spiral(rings: outer)
            .filter { !occupied.contains($0) }
            .map { HexLattice.worldPoint(of: $0, pitch: pitch, rowStretch: rowStretch) }
        let reach = cells.map { hypot($0.world.x, $0.world.y) }.max() ?? 0
        return PortalLayout(pitch: pitch, cells: cells, ghosts: ghosts, reach: reach)
    }

    private func squaredDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
    }
}
