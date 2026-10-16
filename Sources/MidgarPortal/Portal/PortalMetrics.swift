import CoreGraphics

/// One factor that makes the portal's fixed sizes read at the viewing distance of the platform:
/// a television is seen from across a room, everything else from arm's length.
enum PortalMetrics {
    static let scale: CGFloat = {
        #if os(tvOS)
        return 2
        #else
        return 1
        #endif
    }()
}
