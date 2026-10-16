import Foundation

/// The worlds an app can show in demo mode. The app registers its worlds once, at its composition root,
/// then calls `activate` on launch.
public struct DemoRegistry: Sendable {
    public private(set) var worlds: [any DemoWorld]

    public init() {
        worlds = []
    }

    /// Adds a world. Two worlds with one id would make `-MidgarDemo` ambiguous, so that is an error.
    public mutating func register(_ world: any DemoWorld) throws {
        guard !worlds.contains(where: { $0.id == world.id }) else {
            throw DemoError.duplicateWorld(world.id)
        }
        worlds.append(world)
    }

    /// Activates the contract of this process. Returns nil outside demo mode, where the clock stays live.
    public func activate(now: Date = Date()) async throws -> DemoActivation? {
        try await activate(launch: DemoLaunch.current, now: now)
    }

    /// Activates a parsed contract: freezes `DemoClock`, prepares the chosen scene and returns what was chosen.
    /// Every call first clears the frozen clock, so a failed or non-demo activation never leaves a stale date behind.
    public func activate(launch: DemoLaunch, now: Date = Date()) async throws -> DemoActivation? {
        DemoClockStore.shared.freeze(nil)
        guard let worldID = launch.world else { return nil }
        let world = try resolveWorld(worldID)
        let scene = try resolveScene(launch.scene, in: world)
        let context = DemoContext(
            date: launch.date ?? now,
            locale: launch.locale.map { Locale(identifier: $0) } ?? Locale.current
        )
        DemoClockStore.shared.freeze(context.date)
        try await world.prepare(scene, context: context)
        return DemoActivation(world: world, scene: scene, context: context)
    }

    /// The registered world with this id, or an error listing the ids that exist.
    private func resolveWorld(_ id: String) throws -> any DemoWorld {
        guard let world = worlds.first(where: { $0.id == id }) else {
            throw DemoError.unknownWorld(id, valid: worlds.map(\.id))
        }
        return world
    }

    /// The named scene, or the world's first scene when none is named. A world without scenes can only be
    /// activated with a scene name, and that name is reported as unknown.
    private func resolveScene(_ id: String?, in world: any DemoWorld) throws -> DemoScene {
        guard let id else {
            guard let first = world.scenes.first else { throw DemoError.noScenes(world: world.id) }
            return first
        }
        guard let scene = world.scenes.first(where: { $0.id == id }) else {
            throw DemoError.unknownScene(world: world.id, scene: id, valid: world.scenes.map(\.id))
        }
        return scene
    }
}

/// The world, scene and context a process was activated with.
public struct DemoActivation: Sendable {
    public let world: any DemoWorld
    public let scene: DemoScene
    public let context: DemoContext
}
