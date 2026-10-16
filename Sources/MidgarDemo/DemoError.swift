import Foundation

/// Failures in the demo launch contract. Each message names the bad input and the valid choices, so a
/// typo in a screenshot command fails the run instead of quietly capturing the wrong screen.
public enum DemoError: Error, Equatable, Sendable, LocalizedError {
    case missingValue(argument: String)
    case malformedDate(String)
    case duplicateWorld(String)
    case unknownWorld(String, valid: [String])
    case unknownScene(world: String, scene: String, valid: [String])
    case noScenes(world: String)

    public var errorDescription: String? {
        switch self {
        case .missingValue(let argument):
            "Demo launch argument \(argument) needs a value."
        case .malformedDate(let text):
            "Demo date \"\(text)\" is not ISO-8601 with a time zone, for example 2026-10-16T09:41:00Z."
        case .duplicateWorld(let id):
            "Demo world \"\(id)\" is already registered."
        case .unknownWorld(let id, let valid):
            "Unknown demo world \"\(id)\". Valid worlds: \(Self.listing(valid))."
        case .unknownScene(let world, let scene, let valid):
            "Unknown scene \"\(scene)\" in demo world \"\(world)\". Valid scenes: \(Self.listing(valid))."
        case .noScenes(let world):
            "Demo world \"\(world)\" declares no scenes."
        }
    }

    /// Joins ids for an error message, or says there are none.
    private static func listing(_ ids: [String]) -> String {
        ids.isEmpty ? "none" : ids.joined(separator: ", ")
    }
}
