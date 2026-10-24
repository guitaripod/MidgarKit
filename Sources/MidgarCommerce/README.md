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

1. A purchase reads the Midgar ID and passes it as `.appAccountToken`. If the identity cannot answer right now the purchase proceeds without the token: a payment must not wait on our backend. Such a transaction is granted from StoreKit on this device and queued. Once the identity exists the queue reports it, and the ledger binds a token-less transaction to the reporting Midgar ID the first time. One already bound to another ID is refused with `403 account_mismatch` and dropped from the queue; the entitlement then lives in StoreKit only.
2. A verified transaction is written to the on-disk report queue, then finished, then granted. A crash between the steps cannot lose it: an unfinished transaction is redelivered by `Transaction.updates`.
3. The queue sends `POST /v1/ledger/transactions` with the transaction's JWS. A report leaves the queue when the ledger answers 2xx or refuses it for good (`account_mismatch`, `bundle_mismatch`, `unverifiable_payload`, `invalid_request`). Every other failure keeps it and a background loop retries after 5 s, 30 s, 2 min, 10 min, then hourly, and on every launch, foreground and transaction.
4. An unverified transaction is never granted, finished or reported. `purchase` throws `MidgarStoreError.unverifiedTransaction`; the listener logs it and emits `.refused`.
5. Family Sharing transactions and transactions signed by Xcode's local certificate (StoreKit testing) are never reported: the ledger cannot attribute the first and cannot verify the second. Refunds and revocations are reported (their JWS carries `revocationDate`) so the ledger drops the entitlement before Apple's notification arrives.
6. Transactions for products that are not in `productIDs` are left alone, unfinished: another system (AICredits, RevenueCat) owns them.

## Which purchase call

| Platform | Call |
|---|---|
| iOS, tvOS | `purchase(_:)`, or `purchase(_:confirmIn: UIScene)` (iOS 17 and later) to anchor the sheet to a scene |
| macOS | `purchase(_:)`, or `purchase(_:confirmIn: NSWindow)` (macOS 15.2 and later) to anchor the sheet to a window |
| visionOS | `purchase(_:confirmIn: UIScene)` only: StoreKit has no scene-less purchase there, and `purchase(_:)` throws `unsupportedPlatform` |

Every variant goes through the same path: the account token, verification, finish, the report queue, the signal and the events. Where the OS is older than the `confirmIn` overload the plain StoreKit purchase is used.

## Entitlements

`entitlements` is the union of the ledger's answer for this Midgar ID and `Transaction.currentEntitlements` on this device (offline fallback and Family Sharing). The ledger answers for every app of the ID, but only entries whose `app` is this app's registry slug (`appID`) count. Another app's purchase grants nothing here unless its entitlement name is listed in `MidgarStoreConfiguration.crossAppEntitlements`, which is empty by default and is the switch for the cross-app access decision (P4.00, the founder's). Per name the longer-lived grant wins and `sources` says who saw it. The ledger view is refreshed on launch, on foreground and after each transaction. When the ledger is unreachable the last snapshot is used: subscriptions only while the snapshot is at most 7 days old and the expiry (or grace expiry) is ahead, non-consumables for as long as the snapshot exists. The snapshot is cleared when the Midgar ID or the environment changes. Like the ledger, the device grants only non-consumables and auto-renewable subscriptions; consumables and non-renewing subscriptions never grant.

Environment: the ledger is asked for `Sandbox` when `AppTransaction.environment` is `sandbox` (TestFlight, sandbox-signed debug builds) or `xcode`, and for Production otherwise. A transaction seen with a non-production environment overrides it. The legacy `sandboxReceipt` URL rule is not used.

## RevenueCat

- `storekit2` and `rc-observer` apps use `MidgarStoreConfiguration.Mode.purchases` (the default). MidgarCommerce buys, finishes and listens. RevenueCat, where still linked, runs in observer mode (`purchasesAreCompletedBy: .myApp`), so it sees transactions but never finishes them; the ledger forwards App Store notifications to RevenueCat (`RC_FORWARD_<SLUG>`) for its dashboard.
- `rc-full` apps use `Mode.readOnly` until their migration. RevenueCat keeps purchasing and finishing; MidgarCommerce only reads the ledger (and its cache). `purchase`, `restore` and the offer code sheet throw `MidgarStoreError.readOnly`, no listener starts and no transaction is touched.

## Restore and offer codes

`restore()` calls `AppStore.sync()`, re-reads current entitlements, queues each for the ledger again (the ledger ignores known transactions and raises no sale alert for old ones) and refreshes. `reportPurchaseHistory()` does the same without the sync and its sign-in, once per install (`historyReportedAt` in the state file): an app moving its purchases onto the store calls it at launch so customers who bought through RevenueCat or plain StoreKit reach their Midgar ID. On iOS and visionOS `presentOfferCodeRedeemSheet(from:)` shows the sheet; the redeemed transaction goes through the same path as an update.

## Promoted in-app purchases

A purchase the customer starts on the App Store product page reaches the running app as a StoreKit `PurchaseIntent` (iOS 16.4, macOS 14.4, visionOS), and nothing is charged until the app buys it. In purchases mode the store listens for intents from launch and buys an intent for one of its products through the same path as `purchase(_:)`, with the Midgar ID as `appAccountToken`, then publishes `purchaseApproved(productID:)`, since no call of the app started it. A credit pack bought this way is credited by the ledger-fed grant (it carries the Midgar ID), and MidgarCredits reads the balance again on the event. An intent for a product the store does not sell is ignored; a read-only store does not listen. tvOS has no purchase intents.


## StoreKit views

`SubscriptionStoreView`, `StoreView` and `ProductView` run their own purchase sheet. Two calls make the store own the result: `purchaseOptions()` returns `.appAccountToken(<Midgar ID>)` for the view's `.inAppPurchaseOptions`, and `complete(_:)` takes the `Product.PurchaseResult` from `.onInAppPurchaseCompletion` through the same path as `purchase(_:)` (verification, report queue, finish, signal, events). `complete` refuses a product the store is not configured with. MidgarCommerceUI wraps both in `.midgarPurchases(store:onEvent:)`.

## Trial policy

`MidgarTrialPolicy` is the one rule for introductory offers: present one exactly when `Product.SubscriptionInfo.isEligibleForIntroOffer(for:)` says the customer is eligible for the subscription group, and nothing else (no local flag, counter or date). `presentations(for:)` returns, per product with an offer the customer may use, a `MidgarTrialPresentation` whose `summary` (`1 week free, then $39.99/year`), `badge` and renewal text come from the product's own offer data (kind, period, period count, price) and renewal price. The policy keeps no cache, because eligibility changes after a purchase and a restore. The wording lives in this module's string catalog under `trial.*`, `price.*` and `unit.*` keys.

## Review policy

`MidgarReviewPolicy` decides when the app may call StoreKit's `requestReview`; it never calls it. All rules must hold: the app reported a positive moment this session with `noteSuccess()`; more than 3 days since the first launch and more than 5 sessions (`beginSession()` once per launch); not within 120 days of the last prompt and not on the app version that already prompted; not within 7 days of a purchase failure (`notePurchaseFailure()`) or a refund (`noteRefund()`) the app reported. `noteSuccess()` returns whether to ask now; after asking, call `notePrompted()`. State is a JSON file per app (`review-<app>.json` beside the commerce state), the clock and storage are injectable, and `evaluate()` returns the reason when it holds back. It records no `review.prompt` signal: the signals schema (`services/signals/src/schema.ts`) has no such event, so adding one is a schema change first.

## Tests

- `swift test --filter Commerce` runs the unit tests against fakes for StoreKit, the identity and the ledger's HTTP routes (a `URLProtocol` stub). They also run on the iOS Simulator with `xcodebuild test -scheme MidgarKit-Package -destination 'platform=iOS Simulator,id=<udid>' -only-testing:MidgarCommerceTests`.
- `Tests/StoreKitHost` holds the StoreKitTest integration tests (`SKTestSession` with `Products.storekit`: purchase with the account token, renewal on the time rate, refund, Ask to Buy, restore). `SKTestSession` cannot run in the bare `xctest` process SwiftPM uses, so they run from a tiny host app: `cd Tests/StoreKitHost && xcodegen generate && xcodebuild test -project StoreKitHost.xcodeproj -scheme StoreKitHost -destination 'platform=iOS Simulator,id=<udid>'`. The Simulator runtime must match the Xcode SDK (an iOS 26.5 runtime under Xcode 27.1 answers every `SKTestSession` call with `SKInternalErrorDomain` 3). The first run on a freshly created Simulator stalls at the first purchase; stop it and run again. Transactions from a test session are signed by Xcode's local certificate, so the store never reports them to the ledger; ledger reporting is covered by the unit tests.
- Not covered by `SKTestSession`: `expireSubscription` leaves the transaction in `Transaction.currentEntitlements`, so subscription expiry is covered by the unit tests only. The offer code sheet is UI and is covered through the updates path.
