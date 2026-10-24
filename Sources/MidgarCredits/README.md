# MidgarCredits

AI credit packs on the Midgar ID wallet (roadmap P2.09, decision D2). It replaces the `AICredits` package for MidgarKit 4 apps: the balance, the pack purchase and the credit all go through mako's wallet for the Midgar ID, partitioned per app.

It is its own target, not part of MidgarCommerce, so an app that sells no credits links none of it. It depends on MidgarCore and MidgarCommerce. The `MidgarKit` umbrella re-exports it.

```swift
let identity = MidgarIdentity(httpConfiguration: configuration)
let http = MidgarHTTPClient(configuration: identity.authorizing(configuration))
let packs = [
    MidgarCreditsPack(id: "starter", productID: "app.midgar.dreameater.credits.starter", credits: 150),
    MidgarCreditsPack(id: "plus", productID: "app.midgar.dreameater.credits.plus", credits: 700)
]
let creditsConfiguration = MidgarCreditsConfiguration(packs: packs)
let store = MidgarStore(
    configuration: MidgarStoreConfiguration(
        appID: "dream-eater",
        productIDs: ["app.midgar.dreameater.pro"] + creditsConfiguration.productIDs,
        entitlementsByProduct: ["app.midgar.dreameater.pro": "pro"]
    ),
    identity: identity,
    http: http
)
let credits = MidgarCredits(
    configuration: creditsConfiguration,
    http: configuration,
    identity: identity,
    purchasing: store
)

let balance = try await credits.refresh()
let offers = try await credits.offers()
switch try await credits.buy("starter") {
case .credited(_, let added, let balance): ...
case .creditPending: ...
case .awaitingApproval, .cancelled: ...
}
for await event in await credits.events() { ... }
```

Pass the app's base `MidgarHTTPConfiguration` (no token provider) as `http`: MidgarCredits authorizes it itself, because a legacy API key and the Midgar token travel in different headers.

## Free allowances

`MidgarCreditsBalance.allowances` lists the free allowances mako sends next to the balance (`weekly` on `GET /v1/credits/balance`, keyed by the capability or alias id): `MidgarCreditsAllowance(id:remaining:limit:resetsAt:)`, sorted by id. The array is empty when mako sends none, so an app without allowances sees no change. A bucket that cannot be read is skipped instead of failing the balance, a negative `remaining` is read as 0, and `resetsAt` is nil when mako sends no date. `balanceChanged` also fires when only an allowance changed.

## Apple Ads attribution

`MidgarAdAttribution` ports the reporting of `AICredits` (the AdServices token, exchanged by mako with Apple and kept against the Midgar ID's partition). The app calls it once per launch, after the first frame is on screen:

```swift
let credits = MidgarCredits(
    configuration: MidgarCreditsConfiguration(
        packs: packs,
        isProductionLaunch: { !isDebugBuild && !isUITest && !isDemoMode }
    ),
    ...
)
Task { await credits.reportAdAttributionOnce() }
```

- **Who decides.** `isProductionLaunch` is asked on every call; false means nothing is captured or sent (a debug build, a UI test, demo mode). It defaults to true, so an app that runs any of those must pass its answer. The token source is `MidgarAdServicesTokenProvider` (`AAAttribution.attributionToken()`); `attributionTokenProvider` replaces it in tests.
- **Request.** `POST /v1/intelligence/v1/attribution` with `{"attribution_token": "<token>"}`, the body `AICredits` sends, authorized like every other call here: the Midgar access token as the bearer, or the legacy key as the bearer plus `X-Midgar-Token` when the app passes `legacyAPIKey`. Timeout 20 seconds, because the token is short-lived.
- **Once per install.** `<directory>/attribution-<app>.json` holds mako's final verdict (`attributed`, `organic` or `duplicate`); after that no launch captures or sends anything. The file is in the app's container, so a reinstall is a new install. The token itself is never written or logged.
- **Retries.** A network failure, a server error or a `pending` or `invalid` verdict leave the install open and the next launch captures a fresh token. `pending` is also retried inside the launch (up to 3 submissions, after mako's `retry_after_seconds` when that is 10 seconds or less). Launches that reached mako without a verdict stop after 5; being offline does not count.
- **Nothing to send.** A token call that throws (the Simulator, no attribution record yet), no token, or a token that mako's shape check would refuse (16 to 8192 characters of base64) sends nothing and counts for nothing.
- **Result.** `reportAdAttributionOnce()` never throws and returns a `MidgarAdAttributionResult` (`settled`, `alreadySettled`, `deferred`, `skipped`, `noToken`, `exhausted`) whose `logDescription` is safe for the app's file log.

## Which pack, which product

Pack ids, product ids and credit amounts come from the app, never from the code: `MidgarCreditsPack(id:productID:credits:)`. `id` is the pack id in mako's catalog for the app; mako requires the product id to be the app's `rc_product_prefix` plus that id, and rejects a receipt for another pack. `credits` is what the pack grants, bonus included; mako's answer is authoritative and the value is used for display and while a credit is pending. The pack product ids must also be in `MidgarStoreConfiguration.productIDs`, or the store leaves the transaction alone and `buy` throws `notConfigured(.productNotSold)`.

## Authentication

mako resolves two kinds of caller (`services/intelligence/docs/p3.07-wallet-design.md`, section 4):

| Mode | Headers | When |
|---|---|---|
| Midgar-ID-native | `Authorization: Bearer <access JWT>` | The default. mako finds or creates the user for the Midgar ID. |
| Legacy key | `Authorization: Bearer <api key>` and `X-Midgar-Token: <access JWT>` | The app passes `legacyAPIKey`, a closure read on every request, and it returns a key. The first such request links the key's user and its old balance into the wallet. |

If the legacy key is set and the identity cannot give a token, the request fails with `identityUnavailable` instead of going out with the key alone, because mako would then answer from the old per-app balance.

`X-App-ID` is the registry slug from the HTTP configuration; mako accepts it next to its own tenant ids.

## Buying a pack

1. `MidgarStore.purchaseReceipt(_:)` buys the consumable with the Midgar ID as `appAccountToken`, finishes it, queues the ledger report and returns the verified transaction (id, product, signed JWS).
2. MidgarCredits writes the receipt to `credits-<app>.json` (StoreKit has finished the consumable, so this file is the only local record that it was paid for and not yet credited).
3. `POST /v1/intelligence/v1/credits/purchase/revenuecat/validate` with `pack_id`, `purchase_token` (the transaction id), `product_id`, `platform: "ios"` and the signed transaction. mako verifies, then credits the wallet under the key `tx:<transaction id>`, the same key the RevenueCat webhook uses, so the credit lands once however it arrives.
4. mako's error code decides. `credit_pending` (409) and `unverifiable_purchase` (400), like a 502 to 504, a 503 or a 500, mean the purchase has not reached its verifier or its credit yet: validation is retried after 2, 5 and 15 seconds. Still unconfirmed: the result is `creditPending`, the receipt stays on disk, and it is retried in the background after 30 s, 2 min, 10 min and 30 min, on every `refresh()` and on every launch. A receipt older than a week is dropped (the webhook has had every chance by then). `already_processed` (400) counts as credited. Any other 4xx is final: the receipt is dropped and `buy` throws `purchaseRejected`. An answer without a code (a mako that predates them) is read by status and text as before: a 500, or a 400 saying "could not be verified", is retried, and a 400 saying "already been processed" counts as credited.
5. The balance is read again and `purchaseCredited` and `balanceChanged` are published. If that read fails the validation's `new_balance` stands in.

An Ask to Buy purchase approved later has no receipt in this process: the store's `purchaseApproved` event triggers a `refresh()` and the webhook does the credit. A purchase made through a StoreKit view (`complete(_:)`) is credited by the webhook the same way; use `purchaseReceipt` and `redeem(_:)` where the fast credit matters.

## Errors

`MidgarCreditsError`, switched with `@unknown default`:

| Case | Cause |
|---|---|
| `offline` | No network, or a timeout |
| `insufficientCredits(balance:)` | A 402. The balance is read afterwards (`MidgarHTTPError` drops the message that holds it) and is nil only when that read failed |
| `walletUnavailable` | 503: the wallet cannot be reached. Nothing was charged |
| `notConfigured(_)` | No packs, an unknown pack, a product the store does not sell, a read-only store |
| `unauthorized`, `identityUnavailable`, `rateLimited` | 401, no access token, 429 |
| `purchaseRejected(message:)` | mako will never credit the purchase |
| `store(_)`, `server(...)`, `invalidResponse` | StoreKit failed, another status, an unreadable answer |

A 402 comes from a metered call, which is MidgarIntelligence's, not MidgarCredits's. Map it with `await credits.creditsError(for:)`, which reads the balance for the 402.

## What mako does not have yet

- The 402 body now carries the balance as a number (`error.balance`, next to `code: "insufficient_credits"`), but `MidgarHTTPError.paymentRequired(code:)` drops the body, so the client still reads the balance afterwards. Carrying `balance` on `.paymentRequired` in MidgarCore would save that read.
- Stable codes exist (`credit_pending` 409, `already_processed` and `unverifiable_purchase` 400); the client prefers them and keeps the status and text matching as a fallback for a mako that has no codes.
- `signed_transaction` is read: mako has the ledger verify the JWS (bundle, product, consumable, not revoked, `appAccountToken` equal to the Midgar ID in the token) and credits the pack without RevenueCat, under the same `tx:<transaction id>` key as the webhook. The request needs the Midgar token (`X-Midgar-Token` or the native bearer); a purchase without one is a 401.

## Tests

`swift test --filter Credits` runs the unit tests against a scripted gateway (a `URLProtocol` stub) and a fake store and identity.
