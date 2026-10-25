import Foundation
import MidgarCore

/// One row of a settings screen. Build rows with the standard factories or `custom`, `link`, `toggle` and `info`.
public struct MidgarSettingsRow: Identifiable, Sendable {
    public typealias Handler = @MainActor @Sendable () async throws -> Void
    public typealias ToggleGetter = @MainActor @Sendable () -> Bool
    public typealias ToggleSetter = @MainActor @Sendable (Bool) -> Void

    public enum Role: Sendable, Hashable {
        case standard
        case destructive
    }

    /// What a tap on the row does.
    public enum Kind: Sendable {
        case info
        case action(Handler)
        case link(URL)
        case copy(String)
        case toggle(get: ToggleGetter, set: ToggleSetter)
    }

    /// The question asked before a destructive action runs.
    public struct Confirmation: Sendable, Hashable {
        public var title: String
        public var message: String
        public var confirmTitle: String

        public init(title: String, message: String, confirmTitle: String) {
            self.title = title
            self.message = message
            self.confirmTitle = confirmTitle
        }
    }

    /// An extra action in the row's context menu.
    public struct MenuItem: Identifiable, Sendable {
        public let id: String
        public var title: String
        public var systemImage: String?
        public var kind: Kind
        public var successMessage: String?

        public init(id: String, title: String, systemImage: String? = nil, kind: Kind, successMessage: String? = nil) {
            self.id = id
            self.title = title
            self.systemImage = systemImage
            self.kind = kind
            self.successMessage = successMessage
        }
    }

    public let id: String
    public var title: String
    public var subtitle: String?
    public var detail: String?
    public var systemImage: String?
    public var role: Role
    public var kind: Kind
    public var showsDisclosure: Bool
    public var confirmation: Confirmation?
    public var successMessage: String?
    public var menu: [MenuItem]

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        detail: String? = nil,
        systemImage: String? = nil,
        role: Role = .standard,
        kind: Kind = .info,
        showsDisclosure: Bool = false,
        confirmation: Confirmation? = nil,
        successMessage: String? = nil,
        menu: [MenuItem] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.systemImage = systemImage
        self.role = role
        self.kind = kind
        self.showsDisclosure = showsDisclosure
        self.confirmation = confirmation
        self.successMessage = successMessage
        self.menu = menu
    }

    public var isInteractive: Bool {
        if case .info = kind { return !menu.isEmpty }
        return true
    }
}

extension MidgarSettingsRow {
    /// A row that runs an app-specific action, such as pushing a detail screen.
    public static func custom(
        id: String,
        title: String,
        subtitle: String? = nil,
        detail: String? = nil,
        systemImage: String? = nil,
        showsDisclosure: Bool = true,
        perform: @escaping Handler
    ) -> MidgarSettingsRow {
        MidgarSettingsRow(
            id: id,
            title: title,
            subtitle: subtitle,
            detail: detail,
            systemImage: systemImage,
            kind: .action(perform),
            showsDisclosure: showsDisclosure
        )
    }

    /// A row that opens a URL outside the app.
    public static func link(
        id: String,
        title: String,
        systemImage: String? = nil,
        url: URL
    ) -> MidgarSettingsRow {
        MidgarSettingsRow(id: id, title: title, systemImage: systemImage, kind: .link(url), showsDisclosure: true)
    }

    /// A row with a switch. The getter is read every time the screen is drawn.
    public static func toggle(
        id: String,
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        isOn: @escaping ToggleGetter,
        setOn: @escaping ToggleSetter
    ) -> MidgarSettingsRow {
        MidgarSettingsRow(
            id: id,
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            kind: .toggle(get: isOn, set: setOn)
        )
    }

    /// A row that only shows a value.
    public static func info(
        id: String,
        title: String,
        detail: String,
        systemImage: String? = nil
    ) -> MidgarSettingsRow {
        MidgarSettingsRow(id: id, title: title, detail: detail, systemImage: systemImage)
    }
}

extension MidgarSettingsRow {
    /// Restores earlier App Store purchases. The handler throws when the restore fails.
    public static func restorePurchases(perform: @escaping Handler) -> MidgarSettingsRow {
        MidgarSettingsRow(
            id: "midgar.restorePurchases",
            title: MidgarUIStrings.restorePurchases,
            systemImage: "arrow.triangle.2.circlepath",
            kind: .action(perform),
            successMessage: MidgarUIStrings.purchasesRestored
        )
    }

    /// Shows the support address as text. A tap copies it; the context menu copies it or starts an email.
    public static func support(address: String, subject: String? = nil) -> MidgarSettingsRow {
        var menu = [
            MenuItem(
                id: "midgar.support.copy",
                title: MidgarUIStrings.copyAddress,
                systemImage: "doc.on.doc",
                kind: .copy(address),
                successMessage: MidgarUIStrings.addressCopied
            )
        ]
        if let mailto = mailtoURL(address: address, subject: subject) {
            menu.append(
                MenuItem(id: "midgar.support.mail", title: MidgarUIStrings.sendEmail, systemImage: "envelope", kind: .link(mailto))
            )
        }
        return MidgarSettingsRow(
            id: "midgar.support",
            title: MidgarUIStrings.support,
            detail: address,
            systemImage: "lifepreserver",
            kind: .copy(address),
            successMessage: MidgarUIStrings.addressCopied,
            menu: menu
        )
    }

    public static func privacyPolicy(url: URL) -> MidgarSettingsRow {
        link(id: "midgar.privacy", title: MidgarUIStrings.privacyPolicy, systemImage: "hand.raised", url: url)
    }

    public static func termsOfUse(url: URL) -> MidgarSettingsRow {
        link(id: "midgar.terms", title: MidgarUIStrings.termsOfUse, systemImage: "doc.text", url: url)
    }

    /// Shows version and build. A tap copies the app name, version and build.
    public static func version(_ info: MidgarVersionInfo = MidgarVersionInfo()) -> MidgarSettingsRow {
        MidgarSettingsRow(
            id: "midgar.version",
            title: MidgarUIStrings.version,
            detail: info.display,
            systemImage: "info.circle",
            kind: .copy(info.copyText),
            successMessage: MidgarUIStrings.versionCopied
        )
    }

    /// The switch for anonymous usage counts, "Share anonymous usage counts". It reads and sets ``MidgarSignals/isEnabled``: off stops `MidgarSignals` sending and deletes its queue and uniqueness ledger. Use ``MidgarSettingsSection/usageCounts(id:)`` to get it with its footer.
    public static func usageCounts() -> MidgarSettingsRow {
        MidgarSettingsRow(
            id: "midgar.usageCounts",
            title: MidgarUIStrings.usageCounts,
            systemImage: "chart.bar",
            kind: .toggle(get: { MidgarSignals.isEnabled }, set: { MidgarSignals.isEnabled = $0 })
        )
    }

    /// Deletes the account after a confirmation. The handler throws when the deletion fails.
    public static func deleteAccount(
        confirmation: Confirmation = .deleteAccount,
        perform: @escaping Handler
    ) -> MidgarSettingsRow {
        MidgarSettingsRow(
            id: "midgar.deleteAccount",
            title: MidgarUIStrings.deleteAccount,
            systemImage: "trash",
            role: .destructive,
            kind: .action(perform),
            confirmation: confirmation
        )
    }

    /// `mailto:` for an address, or nil when the address cannot form a URL.
    static func mailtoURL(address: String, subject: String?) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = trimmed
        if let subject, !subject.isEmpty {
            components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        }
        return components.url
    }
}

extension MidgarSettingsRow.Confirmation {
    public static var deleteAccount: MidgarSettingsRow.Confirmation {
        MidgarSettingsRow.Confirmation(
            title: MidgarUIStrings.deleteAccountTitle,
            message: MidgarUIStrings.deleteAccountMessage,
            confirmTitle: MidgarUIStrings.deleteAccount
        )
    }
}

/// A titled group of rows.
public struct MidgarSettingsSection: Identifiable, Sendable {
    public let id: String
    public var title: String?
    public var footer: String?
    public var rows: [MidgarSettingsRow]

    public init(id: String, title: String? = nil, footer: String? = nil, rows: [MidgarSettingsRow]) {
        self.id = id
        self.title = title
        self.footer = footer
        self.rows = rows
    }
}

extension MidgarSettingsSection {
    /// A section holding ``MidgarSettingsRow/usageCounts()`` with a one-line footer that says what is shared.
    public static func usageCounts(id: String = "midgar.usageCounts") -> MidgarSettingsSection {
        MidgarSettingsSection(id: id, footer: MidgarUIStrings.usageCountsFooter, rows: [.usageCounts()])
    }
}
