import SwiftUI

/// One page of the onboarding pager: a title, a body, artwork and a primary button.
@MainActor
public struct MidgarOnboardingPage: Identifiable {
    public enum Artwork {
        case none
        case symbol(String)
        case image(Image)
        case custom(AnyView)
    }

    public let id: String
    public var title: String
    public var body: String
    public var artwork: Artwork
    public var primaryTitle: String?
    public var primaryAction: (@MainActor @Sendable () async -> Void)?

    /// - Parameters:
    ///   - primaryTitle: The primary button's title. Nil uses "Continue", or "Get Started" on the last page.
    ///   - primaryAction: Runs when the primary button is tapped, before the pager moves on. Use it to ask for a permission.
    public init(
        id: String,
        title: String,
        body: String,
        artwork: Artwork = .none,
        primaryTitle: String? = nil,
        primaryAction: (@MainActor @Sendable () async -> Void)? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.artwork = artwork
        self.primaryTitle = primaryTitle
        self.primaryAction = primaryAction
    }

    /// A page whose artwork is any SwiftUI view.
    public init<Content: View>(
        id: String,
        title: String,
        body: String,
        primaryTitle: String? = nil,
        primaryAction: (@MainActor @Sendable () async -> Void)? = nil,
        @ViewBuilder custom: () -> Content
    ) {
        self.init(
            id: id,
            title: title,
            body: body,
            artwork: .custom(AnyView(custom())),
            primaryTitle: primaryTitle,
            primaryAction: primaryAction
        )
    }
}

/// Where the pager is. A value so the paging rules are testable without a screen.
public struct MidgarOnboardingProgress: Sendable, Hashable {
    public private(set) var index: Int
    public let count: Int

    public init(count: Int, index: Int = 0) {
        self.count = max(count, 0)
        self.index = min(max(index, 0), max(count - 1, 0))
    }

    public var isFirst: Bool { index == 0 }
    public var isLast: Bool { index >= count - 1 }

    /// Moves to the next page, and returns false when already on the last one.
    @discardableResult
    public mutating func advance() -> Bool {
        guard !isLast else { return false }
        index += 1
        return true
    }

    /// Moves to the previous page, and returns false when already on the first one.
    @discardableResult
    public mutating func goBack() -> Bool {
        guard !isFirst else { return false }
        index -= 1
        return true
    }
}
