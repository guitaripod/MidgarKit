import CoreGraphics

/// The camera that pans across the portal. All motion is plain arithmetic on a clock so it can be
/// stepped by a display link, a test, or a snapshot renderer alike: finger drags with rubber-band
/// resistance past the edge, and a critically damped spring that snaps to a cell.
struct PortalCamera: Sendable {
    private enum Phase {
        case resting
        case dragging(origin: CGPoint)
        case gliding(target: CGPoint)
    }

    static let angularFrequency: CGFloat = 12
    static let decayRate: CGFloat = 6
    static let restSpeed: CGFloat = 4
    static let restDistance: CGFloat = 0.25
    static let substep: CGFloat = 1.0 / 240.0

    private(set) var position: CGPoint
    private(set) var velocity: CGPoint = .zero
    var bound: CGFloat
    private var phase: Phase = .resting

    init(position: CGPoint = .zero, bound: CGFloat) {
        self.position = position
        self.bound = bound
    }

    var isMoving: Bool {
        if case .resting = phase { return false }
        return true
    }

    var isDragging: Bool {
        if case .dragging = phase { return true }
        return false
    }

    mutating func beginDrag() {
        phase = .dragging(origin: position)
        velocity = .zero
    }

    /// Follows the finger. `translation` is how far the finger has travelled since `beginDrag`.
    mutating func drag(translation: CGPoint) {
        guard case .dragging(let origin) = phase else { return }
        position = rubberBanded(CGPoint(x: origin.x - translation.x, y: origin.y - translation.y))
    }

    /// Lets go: finds the cell a flick of `velocity` (screen points per second) would coast to and
    /// springs there without overshooting it.
    mutating func endDrag(velocity screenVelocity: CGPoint, snapPoints: [CGPoint]) {
        let worldVelocity = CGPoint(x: -screenVelocity.x, y: -screenVelocity.y)
        let projected = CGPoint(
            x: position.x + worldVelocity.x / Self.decayRate,
            y: position.y + worldVelocity.y / Self.decayRate
        )
        let target = nearest(to: projected, in: snapPoints) ?? position
        glide(to: target, initialVelocity: worldVelocity)
    }

    /// Starts a spring toward `target`, keeping at most the speed that arrives exactly on it.
    mutating func glide(to target: CGPoint, initialVelocity: CGPoint = .zero) {
        let dx = target.x - position.x
        let dy = target.y - position.y
        let distance = hypot(dx, dy)
        guard distance > 0.000_1 else {
            position = target
            velocity = .zero
            phase = .resting
            return
        }
        let direction = CGPoint(x: dx / distance, y: dy / distance)
        let along = initialVelocity.x * direction.x + initialVelocity.y * direction.y
        let limit = Self.angularFrequency * distance
        let allowed = min(max(along, -limit), limit * 0.98)
        velocity = CGPoint(x: direction.x * allowed, y: direction.y * allowed)
        phase = .gliding(target: target)
    }

    /// Moves the camera by a scroll-wheel or trackpad delta, which arrives without a drag session.
    mutating func nudge(by delta: CGPoint) {
        phase = .dragging(origin: position)
        position = rubberBanded(CGPoint(x: position.x - delta.x, y: position.y - delta.y))
    }

    /// Ends a nudge sequence by snapping to the closest cell.
    mutating func settle(snapPoints: [CGPoint]) {
        let target = nearest(to: position, in: snapPoints) ?? position
        glide(to: target)
    }

    /// Advances the simulation. Returns `true` while the camera is still moving.
    @discardableResult
    mutating func step(_ interval: CGFloat) -> Bool {
        guard case .gliding(let target) = phase else { return isMoving }
        var remaining = min(interval, 0.1)
        while remaining > 0 {
            let dt = min(remaining, Self.substep)
            remaining -= dt
            let omega = Self.angularFrequency
            let ax = -omega * omega * (position.x - target.x) - 2 * omega * velocity.x
            let ay = -omega * omega * (position.y - target.y) - 2 * omega * velocity.y
            velocity.x += ax * dt
            velocity.y += ay * dt
            position.x += velocity.x * dt
            position.y += velocity.y * dt
        }
        let speed = hypot(velocity.x, velocity.y)
        let gap = hypot(position.x - target.x, position.y - target.y)
        if speed < Self.restSpeed && gap < Self.restDistance {
            position = target
            velocity = .zero
            phase = .resting
        }
        return isMoving
    }

    private func nearest(to point: CGPoint, in points: [CGPoint]) -> CGPoint? {
        points.min {
            hypot($0.x - point.x, $0.y - point.y) < hypot($1.x - point.x, $1.y - point.y)
        }
    }

    /// Past `bound` the camera follows the finger at a diminishing rate, like a scroll view edge.
    private func rubberBanded(_ raw: CGPoint) -> CGPoint {
        let distance = hypot(raw.x, raw.y)
        guard distance > bound, distance > 0 else { return raw }
        let excess = distance - bound
        let softness = max(bound * 0.45, 40)
        let damped = softness * (1 - 1 / (0.6 * excess / softness + 1))
        let scale = (bound + damped) / distance
        return CGPoint(x: raw.x * scale, y: raw.y * scale)
    }
}
