import Foundation

/// One fictional world an app can show: the data, dates and settings behind a set of screenshots.
public protocol DemoWorld: Sendable {
    /// The identifier `-MidgarDemo` selects. Use the app's registry slug.
    var id: String { get }

    /// The scenes this world can pose, in capture order. The first one is the default.
    var scenes: [DemoScene] { get }

    /// Seeds the app's state for one scene. Runs once per launch, before the first screen is shown.
    func prepare(_ scene: DemoScene, context: DemoContext) async throws
}

/// One posed screen or state of a demo world, such as `daily-result` or `album`.
public struct DemoScene: Sendable, Hashable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}
