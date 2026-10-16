import MidgarUI

/// An axial coordinate on a pointy-top hexagonal lattice, the same arrangement as the original
/// watchOS home screen: rows of circles, every other row offset by half a cell.
struct HexCoordinate: Hashable, Sendable {
    let q: Int
    let r: Int

    static let origin = HexCoordinate(q: 0, r: 0)

    static let directions: [HexCoordinate] = [
        HexCoordinate(q: 1, r: 0), HexCoordinate(q: 1, r: -1), HexCoordinate(q: 0, r: -1),
        HexCoordinate(q: -1, r: 0), HexCoordinate(q: -1, r: 1), HexCoordinate(q: 0, r: 1),
    ]

    /// Number of steps between this cell and the origin.
    var ringIndex: Int { max(abs(q), abs(r), abs(q + r)) }

    func adding(_ other: HexCoordinate) -> HexCoordinate {
        HexCoordinate(q: q + other.q, r: r + other.r)
    }

    func scaled(by factor: Int) -> HexCoordinate {
        HexCoordinate(q: q * factor, r: r * factor)
    }
}

enum HexLattice {
    static let rowRatio: CGFloat = 0.8660254037844386

    /// Centre of `hex` in world space for neighbouring cells exactly `pitch` apart. A `rowStretch`
    /// above 1 spaces the rows out, which suits a tall portrait screen.
    static func worldPoint(of hex: HexCoordinate, pitch: CGFloat, rowStretch: CGFloat = 1) -> CGPoint {
        CGPoint(
            x: pitch * (CGFloat(hex.q) + CGFloat(hex.r) / 2),
            y: pitch * rowRatio * rowStretch * CGFloat(hex.r)
        )
    }

    /// The cells exactly `radius` steps from the origin, walked once around starting at the
    /// bottom-left corner.
    static func ring(_ radius: Int) -> [HexCoordinate] {
        guard radius > 0 else { return [.origin] }
        var cell = HexCoordinate.directions[4].scaled(by: radius)
        var cells: [HexCoordinate] = []
        cells.reserveCapacity(6 * radius)
        for direction in HexCoordinate.directions {
            for _ in 0..<radius {
                cells.append(cell)
                cell = cell.adding(direction)
            }
        }
        return cells
    }

    /// The origin followed by every ring up to `rings`, so a cell is never farther from the
    /// origin than any cell after it.
    static func spiral(rings: Int) -> [HexCoordinate] {
        (0...max(rings, 0)).flatMap { ring($0) }
    }

    /// Smallest ring count whose spiral holds `count` cells.
    static func ringsNeeded(forCells count: Int) -> Int {
        var rings = 0
        while cellCount(rings: rings) < count { rings += 1 }
        return rings
    }

    static func cellCount(rings: Int) -> Int {
        1 + 3 * rings * (rings + 1)
    }

    /// Picks `count` of the `cells` so the unused ones are spread around the ring instead of
    /// leaving one gap.
    static func evenlySpaced(_ cells: [HexCoordinate], count: Int) -> [HexCoordinate] {
        guard count < cells.count else { return cells }
        guard count > 0 else { return [] }
        return (0..<count).map { index in cells[index * cells.count / count] }
    }
}
