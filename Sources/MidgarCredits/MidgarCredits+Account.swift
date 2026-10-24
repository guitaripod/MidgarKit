import Foundation

extension MidgarCredits {
    /// Deletes the app's old per-app account at mako (`DELETE /v1/identity`, authorized by the legacy API key) for an app that still holds `legacyAPIKey`. An app's Delete Account calls this before it deletes the Midgar ID, because the key is the only way to name the old account.
    ///
    /// With no `legacyAPIKey`, or a closure that returns no key, it returns without sending anything. 200, 204, 401 and 404 count as done: a rejected key or a missing account means there is nothing left to delete. The wallet balance read in this process is forgotten once the account is gone.
    ///
    /// - Throws: ``MidgarCreditsError`` for any other answer or when the network fails, so the app can stop and let the person try again; `CancellationError` when cancelled.
    public func deleteLegacyAccount() async throws {
        guard try await api.deleteLegacyIdentity() else {
            return
        }
        cachedBalance = nil
    }
}
