# MidgarCommerce

The purchase engine (decision D2): StoreKit 2 on the device, the Midgar ledger (`services/ledger`) as the cross-app record. It imports MidgarCore and StoreKit only.

```swift
let identity = MidgarIdentity(httpConfiguration: configuration)
let http = MidgarHTTPClient(configuration: identity.authorizing(configuration))
let store = MidgarStore(
    configuration: MidgarStoreConfiguration(
        appID: "flaccy",
        productIDs: ["app.midgar.flaccy.pro", "app.midgar.flaccy.monthly"],
        entitlementsByProduct: ["app.midgar.flaccy.pro": "pro", "app.midgar.flaccy.monthly": "pro"]
    ),
    identity: identity,
    http: http
)
let result = try await store.purchase("app.midgar.flaccy.pro")
let isPro = await store.isEntitled(to: "pro")
```

The app passes product ids and the entitlement map (later generated from the registry's `[commerce]` table); the package holds no prices and no product decisions. Create one store at launch and keep it for the life of the process.

## Why an actor

The store owns state several tasks touch (the `Transaction.updates` listener, a purchase, a restore, the background retry) and does disk and network I/O. An actor serializes that without blocking the main thread. The UI reads `entitlements` and subscribes to `events()` from its own `@MainActor` model.

## The money path

1. `purchase(_:)` reads the Midgar ID and passes it as `.appAccountToken`. If the identity cannot answer right now the purchase proceeds without the token: a payment must not wait on our backend. Such a transaction is granted from StoreKit on this device; the ledger refuses it (`403 account_mismatch`, a transaction needs the caller's token), so the queue drops it and the entitlement lives in StoreKit only. This is a gap in the ledger contract: it has no way to claim a transaction that carries no token, and the client cannot repair that.
2. A verified transaction is written to the on-disk report queue, then finished, then granted. A crash between the steps cannot lose it: an unfinished transaction is redelivered by `Transaction.updates`.
3. The queue sends `POST /v1/ledger/transactions` with the transaction's JWS. A report leaves the queue when the ledger answers 2xx or refuses it for good (`account_mismatch`, `bundle_mismatch`, `unverifiable_payload`, `invalid_request`). Every other failure keeps it and a background loop retries after 5 s, 30 s, 2 min, 10 min, then hourly, and on every launch, foreground and transaction.
4. An unverified transaction is never granted, finished or reported. `purchase` throws `MidgarStoreError.unverifiedTransaction`; the listener logs it and emits `.refused`.
5. Family Sharing transactions and transactions signed by Xcode's local certificate (StoreKit testing) are never reported: the ledger cannot attribute the first and cannot verify the second. Refunds and revocations are reported (their JWS carries `revocationDate`) so the ledger drops the entitlement before Apple's notification arrives.
6. Transactions for products that are not in `productIDs` are left alone, unfinished: another system (AICredits, RevenueCat) owns them.

## Entitlements

`entitlements` is the union of the ledger's answer for this Midgar ID (cross-app, the source for the Pass) and `Transaction.currentEntitlements` on this device (offline fallback and Family Sharing). Per name the longer-lived grant wins and `sources` says who saw it. The ledger view is refreshed on launch, on foreground and after each transaction. When the ledger is unreachable the last snapshot is used: subscriptions only while the snapshot is at most 7 days old and the expiry (or grace expiry) is ahead, non-consumables for as long as the snapshot exists. The snapshot is cleared when the Midgar ID or the environment changes. Like the ledger, the device grants only non-consumables and auto-renewable subscriptions; consumables and non-renewing subscriptions never grant.

Environment: the ledger is asked for `Sandbox` when `AppTransaction.environment` is `sandbox` (TestFlight, sandbox-signed debug builds) or `xcode`, and for Production otherwise. A transaction seen with a non-production environment overrides it. The legacy `sandboxReceipt` URL rule is not used.

## RevenueCat

- `storekit2` and `rc-observer` apps use `MidgarStoreConfiguration.Mode.purchases` (the default). MidgarCommerce buys, finishes and listens. RevenueCat, where still linked, runs in observer mode (`purchasesAreCompletedBy: .myApp`), so it sees transactions but never finishes them; the ledger forwards App Store notifications to RevenueCat (`RC_FORWARD_<SLUG>`) for its dashboard.
- `rc-full` apps use `Mode.readOnly` until their migration. RevenueCat keeps purchasing and finishing; MidgarCommerce only reads the ledger (and its cache). `purchase`, `restore` and the offer code sheet throw `MidgarStoreError.readOnly`, no listener starts and no transaction is touched.

## Restore and offer codes

`restore()` calls `AppStore.sync()`, re-reads current entitlements, queues each for the ledger again (the ledger ignores known transactions and raises no sale alert for old ones) and refreshes. On iOS and visionOS `presentOfferCodeRedeemSheet(from:)` shows the sheet; the redeemed transaction goes through the same path as an update.

## Platforms

Purchasing uses `Product.purchase(options:)`, which the SDK marks unavailable on visionOS: there `purchase` throws `unsupportedPlatform` until a scene-based variant is added.

## Tests

- `swift test --filter Commerce` runs the unit tests against fakes for StoreKit, the identity and the ledger's HTTP routes (a `URLProtocol` stub). They also run on the iOS Simulator with `xcodebuild test -scheme MidgarKit-Package -destination 'platform=iOS Simulator,id=<udid>' -only-testing:MidgarCommerceTests`.
- `Tests/StoreKitHost` holds the StoreKitTest integration tests (`SKTestSession` with `Products.storekit`: purchase with the account token, renewal on the time rate, refund, Ask to Buy, restore). `SKTestSession` cannot run in the bare `xctest` process SwiftPM uses, so they run from a tiny host app: `cd Tests/StoreKitHost && xcodegen generate && xcodebuild test -project StoreKitHost.xcodeproj -scheme StoreKitHost -destination 'platform=iOS Simulator,id=<udid>'`. The Simulator runtime must match the Xcode SDK (an iOS 26.5 runtime under Xcode 27.1 answers every `SKTestSession` call with `SKInternalErrorDomain` 3). Transactions from a test session are signed by Xcode's local certificate, so the store never reports them to the ledger; ledger reporting is covered by the unit tests.
- Not covered by `SKTestSession`: `expireSubscription` leaves the transaction in `Transaction.currentEntitlements`, so subscription expiry is covered by the unit tests only. The offer code sheet is UI and is covered through the updates path.
