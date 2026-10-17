# MidgarCommerceUI

The paywall parts of every Midgar app (roadmap P2.08), on top of MidgarCommerce and MidgarUI. SwiftUI and UIKit, Apple platforms only (iOS 17, macOS 14, tvOS 17, visionOS 1; the package floor is lower, so every type is `@available`).

```swift
MidgarPaywall(
    groupID: "21345678",
    store: store,
    links: MidgarPaywallLinks(termsOfUse: termsURL, privacyPolicy: privacyURL),
    title: "Go Pro",
    subtitle: "Everything unlocked.",
    systemImage: "sparkles"
) { event in
    if event.isSuccess { dismiss() }
}
```

## Parts

- `MidgarPaywall`: a subscription group on `SubscriptionStoreView`, themed from `MidgarTheme`. StoreKit draws the plans, prices, periods and the offer text for an eligible customer.
- `MidgarStorefront`: one-time products on `StoreView`, each drawn as a `MidgarPlanCard`.
- `MidgarPlanCard` and `MidgarPlanProductViewStyle`: the card (title, price and period, detail, badge, selected and purchased states) and the `ProductViewStyle` that gives any `StoreView` or `ProductView` that face.
- `MidgarPaywallScreen` and `MidgarPaywallConfiguration`: one entry point for either kind.
- `MidgarPaywallViewController`: the UIKit host, a view controller around a `UIHostingController` that calls its completion once with `.purchased`, `.restored` or `.dismissed`.
- `.midgarPurchases(store:onEvent:)`: the modifier that makes the purchases of any StoreKit view below it belong to the store.

## Guideline 3.1.2

The footer is outside the scrolling StoreKit view and always present: each plan's price and period (from StoreKit, with the introductory offer from `MidgarTrialPolicy` when the customer is eligible), the auto-renew terms, Terms of Use and Privacy Policy links the app passes in, and Restore Purchases. StoreKit's own Restore and policy buttons are hidden so there is one of each. The storefront for one-time products states no auto-renew terms.

## Which purchase hook

The StoreKit views run the purchase, so `MidgarStore.purchase(_:)` is not called. `.inAppPurchaseOptions` supplies the Midgar ID as `appAccountToken` (`MidgarStore.purchaseOptions()`), and `.onInAppPurchaseCompletion` hands the result to `MidgarStore.complete(_:)`, which runs the money path of `purchase(_:)`. A completion action also replaces StoreKit's failure alert, so failures arrive as `MidgarPaywallEvent.failed` and the paywall shows its own. `.onInAppPurchaseStart` was not used: it reports the product only and gets no result. `\.purchase` is for custom buttons and cannot be applied to the buttons inside `SubscriptionStoreView`.

visionOS needs no scene-based call: the StoreKit view confirms in its own scene. Use `MidgarStore.purchase(_:confirmIn:)` only for a custom purchase button of your own there.

Restore runs `MidgarStore.restore()`, so restored purchases reach the ledger.

## Tests

- `swift test --filter Paywall` runs the logic tests and renders the plan cards and the footer on macOS (`MIDGAR_SNAPSHOT_DIR` collects the PNGs). On the iOS Simulator: `xcodebuild test -scheme MidgarKit-Package -destination 'platform=iOS Simulator,id=<udid>' -only-testing:MidgarCommerceUITests`.
- The paywall and storefront over the real StoreKit views need StoreKit testing and an app scene, so they run from the StoreKit host (`Tests/StoreKitHost`, see the MidgarCommerce README): `TEST_RUNNER_MIDGAR_SNAPSHOT_DIR=<dir> xcodebuild test -project StoreKitHost.xcodeproj -scheme StoreKitHost -destination <iPhone, iPad or platform=macOS> -only-testing:StoreKitHostTests/PaywallSnapshotTests`. They use `Tests/MidgarCommerceUITests/Paywall.storekit`.
