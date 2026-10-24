import Foundation
import MidgarCore

extension CreditsAPI: AdAttributionSubmitting {}

extension MidgarCredits {
    /// Reports the Apple Ads install attribution to mako, once per install. Call it at launch, after the first frame is on screen: it captures the AdServices token, posts it to `POST /v1/attribution` with the same credentials as every other call here, and remembers mako's final verdict so no later launch does anything.
    ///
    /// Nothing happens when ``MidgarCreditsConfiguration/isProductionLaunch`` says no, when AdServices has no token (the Simulator), or once an earlier launch settled the install. A network failure leaves it open, and the next launch tries again with a fresh token. The call never throws and never delays the caller beyond the request itself.
    ///
    /// - Returns: What this pass did; log ``MidgarAdAttributionResult/logDescription``, which never holds the token.
    @discardableResult
    public func reportAdAttributionOnce() async -> MidgarAdAttributionResult {
        await adAttribution.reportIfNeeded()
    }
}
