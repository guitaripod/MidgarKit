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
4. mako answers 500 ("will be credited shortly"), 502 to 504, 503 or 400 "could not be verified" while the purchase has not reached its verifier: validation is retried after 2, 5 and 15 seconds. Still unconfirmed: the result is `creditPending`, the receipt stays on disk, and it is retried in the background after 30 s, 2 min, 10 min and 30 min, on every `refresh()` and on every launch. A receipt older than a week is dropped (the webhook has had every chance by then). A 400 "already processed" counts as credited. Any other 4xx is final: the receipt is dropped and `buy` throws `purchaseRejected`.
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

- The 402 body carries the balance only inside the message text (`Insufficient credits. Need 6 credits, have 5`); a `balance` field would save the extra read.
- "Will be credited shortly" is a masked 500 (`internal_error`) and "already processed" a 400 with text only; the client matches the text. Stable codes (`credit_pending`, `already_processed`, `purchase_not_verified`) would replace that.
- `signed_transaction` is sent but not read. The route verifies through RevenueCat's REST API, so a pack bought without RevenueCat observing the customer is only credited once mako verifies the JWS itself (the ledger-fed grant, step 9 of the wallet design, still off).

## Tests

`swift test --filter Credits` runs the unit tests against a scripted gateway (a `URLProtocol` stub) and a fake store and identity.
