import Foundation

/// Runs settings rows for both the SwiftUI and the UIKit screen: confirmations, busy rows, failures and toasts.
/// Whoever hosts the engine renders `state` and is told about every change through `onChange`.
@MainActor
final class MidgarSettingsEngine {
    struct PendingConfirmation {
        let row: MidgarSettingsRow
        let handler: MidgarSettingsRow.Handler
        let confirmation: MidgarSettingsRow.Confirmation
    }

    struct State {
        var busyRowIDs: Set<String> = []
        var pending: PendingConfirmation?
        var failureMessage: String?
        var toast: MidgarToast?
        var revision = 0
    }

    private(set) var state = State() {
        didSet { onChange?(state) }
    }

    var onChange: ((State) -> Void)?

    private let system: any MidgarSystemActions

    init(system: any MidgarSystemActions = MidgarLiveSystemActions()) {
        self.system = system
    }

    func activate(_ row: MidgarSettingsRow) async {
        guard !state.busyRowIDs.contains(row.id) else { return }
        await perform(row.kind, rowID: row.id, confirmation: row.confirmation, row: row, successMessage: row.successMessage)
    }

    func activate(_ item: MidgarSettingsRow.MenuItem) async {
        await perform(item.kind, rowID: item.id, confirmation: nil, row: nil, successMessage: item.successMessage)
    }

    func setToggle(_ row: MidgarSettingsRow, to value: Bool) {
        guard case .toggle(_, let set) = row.kind else { return }
        set(value)
        state.revision += 1
        system.play(.selection)
    }

    /// Confirms the pending action in this very turn and returns the task that runs its handler, or nil when nothing is pending. A confirmation button must call this directly: the alert reports its dismissal right after the button, and that dismissal cancels whatever is still pending, so a confirmation that waits for a later turn finds nothing to run.
    @discardableResult
    func beginConfirmedAction() -> Task<Void, Never>? {
        guard let pending = state.pending else { return nil }
        state.pending = nil
        return Task { await run(pending.handler, rowID: pending.row.id, successMessage: pending.row.successMessage) }
    }

    func confirmPending() async {
        await beginConfirmedAction()?.value
    }

    func cancelPending() {
        state.pending = nil
    }

    func dismissFailure() {
        state.failureMessage = nil
    }

    func dismissToast() {
        state.toast = nil
    }

    /// Draws the rows again, because something outside the engine, such as another screen, may have changed what they show.
    func refresh() {
        state.revision += 1
    }

    func show(_ toast: MidgarToast) {
        state.toast = toast
    }

    private func perform(
        _ kind: MidgarSettingsRow.Kind,
        rowID: String,
        confirmation: MidgarSettingsRow.Confirmation?,
        row: MidgarSettingsRow?,
        successMessage: String?
    ) async {
        switch kind {
        case .info, .toggle:
            return
        case .copy(let text):
            system.copy(text)
            system.play(.selection)
            state.toast = .success(successMessage ?? MidgarUIStrings.copied)
        case .link(let url):
            if await !system.open(url) { fail(MidgarUIStrings.linkFailed) }
        case .action(let handler):
            if let confirmation, let row {
                system.play(.warning)
                state.pending = PendingConfirmation(row: row, handler: handler, confirmation: confirmation)
            } else {
                await run(handler, rowID: rowID, successMessage: successMessage)
            }
        }
    }

    private func run(_ handler: MidgarSettingsRow.Handler, rowID: String, successMessage: String?) async {
        state.busyRowIDs.insert(rowID)
        defer { state.busyRowIDs.remove(rowID) }
        do {
            try await handler()
            if let successMessage {
                system.play(.success)
                state.toast = .success(successMessage)
            }
        } catch is CancellationError {
            return
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func fail(_ message: String) {
        system.play(.error)
        state.failureMessage = message
    }
}
