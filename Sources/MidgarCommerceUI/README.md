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

## The plan paywall

`MidgarPlanPaywall` is the paywall of the tuned apps (roadmap P2.19, matched to Solar Beam's): one plan picker for auto-renewable subscriptions and a one-time product, on the plain StoreKit API instead of `SubscriptionStoreView`. The app passes a `MidgarPlanPaywallConfiguration` (the product ids in display order, the Terms and Privacy links, a `MidgarPaywallHero` with the title, subtitle, symbol or image and benefit rows, and optionally the featured plan and an accent).

```swift
MidgarPlanPaywall(
    configuration: MidgarPlanPaywallConfiguration(
        productIDs: [yearly, monthly, lifetime],
        links: MidgarPaywallLinks(termsOfUse: termsURL, privacyPolicy: privacyURL),
        hero: MidgarPaywallHero(
            title: "Go Pro",
            subtitle: "Everything unlocked.",
            artwork: .symbol("sparkles"),
            features: [MidgarPaywallFeature(symbol: "photo.stack", title: "The full library")]
        ),
        accent: MidgarColor(hex: 0x2A9D8F)
    ),
    store: store
) { event in
    if event.isSuccess { dismiss() }
}
```

UIKit apps use `MidgarPaywallViewController(plans:store:completion:)`.

- **Plans and captions.** A product that is an auto-renewable subscription is sold as a subscription, any other as a one-time purchase. Every caption comes from `StoreProduct.price` and the storefront's currency and locale: `Save 33%` on a plan longer than a month against the monthly plan (whole percent, plain rounding), `Just $3.33 a month, billed yearly`, and `2 years of Yearly costs $79.98. Lifetime is $79.99 and never renews.` (the years round down to a half year, so the line understates what the subscription costs, and it needs the lifetime price to be at least one and a half yearly prices). Without a monthly plan there is no saving; without a yearly plan or a currency there is no comparison. Nothing is a constant.
- **Trial timeline.** `MidgarTrialTimeline` (public, usable alone) shows today, the reminder day and the day billing starts for a free trial that `MidgarTrialPolicy` presents, so only to a customer StoreKit says may use it. The reminder step is shown only when `promisesTrialReminder` is true (the default; set it false when the app posts no reminder) and never on tvOS. The button reads `Try 1 week free` for such a plan and `Continue` otherwise.
- **Layout.** The content scrolls above a pinned purchase bar (the selected plan's offer line, the button and the 3.1.2 footer), in a safe-area inset with an opaque background, so nothing runs behind the offer line or the button. With 700 points of width or more (iPad, an unfolded iPhone Duo, a Mac sheet, a TV) the pitch and the purchase sit in two columns; the width the paywall is given decides, so Split View and resized windows follow. A window under 640 points tall pins only the footer links and moves the auto-renew terms to the end of the content, and an accessibility text size moves the terms and the links there too. The button is Liquid Glass in the accent on iOS, macOS and tvOS 26 and later, bordered-prominent before that and on visionOS. On tvOS the selection follows the focus, the focused plan is lifted with a bright border, the timeline and the legal text sit under the pitch (tvOS cannot open web pages, so Terms and Privacy show their addresses), and a press moves focus to the button. visionOS draws the paywall on materials over the window's glass, with 60 point plan rows and a hover effect; its purchase bar is part of the window, not an ornament.
- **Purchases.** The selected plan is bought with the `\.purchase` action using `MidgarStore.purchaseOptions()` (the Midgar ID as `appAccountToken`) and the result goes to `MidgarStore.complete(_:)`, for subscriptions and the one-time product alike, so verification, the report queue and the entitlements are those of `MidgarStore.purchase(_:)`, and visionOS needs no scene. Restore runs `MidgarStore.restore()`. Outcomes arrive as `MidgarPaywallEvent`.

## Parts

- `MidgarPlanPaywall`, `MidgarPlanPaywallConfiguration`, `MidgarPaywallHero`, `MidgarPaywallFeature`, `MidgarPaywallArtwork` and `MidgarTrialTimeline`: the plan paywall above.
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
- The paywall and storefront over the real StoreKit views need StoreKit testing and an app scene, so they run from the StoreKit host (`Tests/StoreKitHost`, see the MidgarCommerce README): `TEST_RUNNER_MIDGAR_SNAPSHOT_DIR=<dir> xcodebuild test -project StoreKitHost.xcodeproj -scheme StoreKitHost -destination <iPhone, iPad or platform=macOS> -only-testing:StoreKitHostTests/PaywallSnapshotTests`. They use `Tests/MidgarCommerceUITests/Paywall.storekit`. The host builds for iOS, macOS, tvOS and visionOS (`-destination 'platform=tvOS Simulator,id=<udid>'`, `'platform=visionOS Simulator,id=<udid>'`), and the plan paywall renders in the layouts of each: an iPhone and a small window, an iPad plus the windows of an unfolded iPhone Duo (951 x 669, 669 x 951, 466 x 678), a Mac sheet and a wide Mac window, a TV (and the focus state) and a visionOS window, in light and dark where the platform has both, plus the scrolled end and an accessibility text size on iOS. Two traps: StoreKit testing reads the prices of `Paywall.storekit` in the Simulator's region, so a Simulator with a comma-decimal region (`en_US@rg=fizzzz`) reports `Product.price` 39 for 39.99; set it with `xcrun simctl spawn <udid> defaults write -g AppleLocale -string en_US` and reboot it. And on macOS StoreKit testing does not grant a purchase to `Transaction.currentEntitlements` (the `MidgarStore` integration tests fail there the same way), so the purchase tests skip their entitlement checks on macOS.
