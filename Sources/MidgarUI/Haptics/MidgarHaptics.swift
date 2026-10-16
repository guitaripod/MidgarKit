import Foundation

#if canImport(UIKit) && !os(tvOS)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The strength of an impact haptic.
public enum MidgarImpactStyle: Sendable, Hashable, CaseIterable {
    case light
    case medium
    case heavy
    case soft
    case rigid
}

/// One haptic in the shared vocabulary.
public enum MidgarHapticEvent: Sendable, Hashable {
    case success
    case warning
    case error
    case selection
    case impact(MidgarImpactStyle)
}

/// Whatever makes the device taptic. The live player talks to UIKit or AppKit; tests and platforms without haptics use another.
@MainActor
public protocol MidgarHapticPlaying {
    var isSupported: Bool { get }
    func prepare()
    func play(_ event: MidgarHapticEvent)
}

/// Plays haptics when the platform has them and does nothing on Apple TV, Vision Pro and Macs without a Force Touch trackpad.
@MainActor
public final class MidgarHaptics {
    public static let shared = MidgarHaptics()

    /// Follows the haptics switch in an app's settings. A haptic is never the only signal, so off is always safe.
    public var isEnabled = true

    private let player: any MidgarHapticPlaying

    public init(player: any MidgarHapticPlaying = MidgarHaptics.livePlayer()) {
        self.player = player
    }

    public var isSupported: Bool {
        player.isSupported
    }

    /// Wakes the haptic engine so the first haptic after a pause does not lag.
    public func prepare() {
        guard isEnabled, player.isSupported else { return }
        player.prepare()
    }

    public func play(_ event: MidgarHapticEvent) {
        guard isEnabled, player.isSupported else { return }
        player.play(event)
    }

    public func success() { play(.success) }
    public func warning() { play(.warning) }
    public func error() { play(.error) }
    public func selection() { play(.selection) }
    public func impact(_ style: MidgarImpactStyle = .medium) { play(.impact(style)) }

    /// The player for the platform this code runs on.
    public static func livePlayer() -> any MidgarHapticPlaying {
        #if canImport(UIKit) && !os(tvOS) && !os(visionOS)
        UIKitHapticPlayer()
        #elseif canImport(AppKit)
        AppKitHapticPlayer()
        #else
        MidgarSilentHapticPlayer()
        #endif
    }
}

/// A player for platforms without haptics: it reports itself unsupported and ignores every event.
@MainActor
public struct MidgarSilentHapticPlayer: MidgarHapticPlaying {
    public init() {}
    public var isSupported: Bool { false }
    public func prepare() {}
    public func play(_ event: MidgarHapticEvent) {}
}

#if canImport(UIKit) && !os(tvOS) && !os(visionOS)
@MainActor
private final class UIKitHapticPlayer: MidgarHapticPlaying {
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private var impactGenerators: [MidgarImpactStyle: UIImpactFeedbackGenerator] = [:]

    var isSupported: Bool {
        #if targetEnvironment(macCatalyst)
        false
        #else
        true
        #endif
    }

    func prepare() {
        selectionGenerator.prepare()
        notificationGenerator.prepare()
    }

    func play(_ event: MidgarHapticEvent) {
        switch event {
        case .success: notificationGenerator.notificationOccurred(.success)
        case .warning: notificationGenerator.notificationOccurred(.warning)
        case .error: notificationGenerator.notificationOccurred(.error)
        case .selection: selectionGenerator.selectionChanged()
        case .impact(let style): impactGenerator(for: style).impactOccurred()
        }
    }

    /// Generators are kept per style so repeated impacts stay prepared.
    private func impactGenerator(for style: MidgarImpactStyle) -> UIImpactFeedbackGenerator {
        if let existing = impactGenerators[style] { return existing }
        let generator = UIImpactFeedbackGenerator(style: style.uiKit)
        impactGenerators[style] = generator
        return generator
    }
}

private extension MidgarImpactStyle {
    var uiKit: UIImpactFeedbackGenerator.FeedbackStyle {
        switch self {
        case .light: .light
        case .medium: .medium
        case .heavy: .heavy
        case .soft: .soft
        case .rigid: .rigid
        }
    }
}
#elseif canImport(AppKit)
@MainActor
private struct AppKitHapticPlayer: MidgarHapticPlaying {
    var isSupported: Bool { true }

    func prepare() {}

    func play(_ event: MidgarHapticEvent) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern(for: event), performanceTime: .now)
    }

    private func pattern(for event: MidgarHapticEvent) -> NSHapticFeedbackManager.FeedbackPattern {
        switch event {
        case .success, .selection: .levelChange
        case .warning, .error: .alignment
        case .impact: .generic
        }
    }
}
#endif
