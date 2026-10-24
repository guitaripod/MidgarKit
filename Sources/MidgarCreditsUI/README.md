# MidgarCreditsUI

The credit store of every app that sells AI credit packs on the Midgar ID wallet (roadmap P2.09), on top of MidgarCredits, MidgarCommerceUI and MidgarUI. It is its own target, so a paywall-only app links no credits code and an app that sells credits links this one. The `MidgarKit` umbrella re-exports it.

`MidgarCreditStoreView` is the screen of an app that sells AI credit packs on the Midgar ID wallet (MidgarCredits, roadmap P2.09). It takes the app's `MidgarCredits` (through the small `MidgarCreditStoreSource` protocol, so previews and tests pass a fake) and needs no other setup:

```swift
MidgarCreditStoreView(credits: credits, shortfall: 40, allowanceTitles: ["reading.v2": "Readings"])
```

UIKit hosts it with `UIHostingController(rootView: MidgarCreditStoreView(credits: credits))`.

- **What it shows.** The balance, and the free allowances that renew when mako reports any (a name from `allowanceTitles` or the allowance id, how much is left of the limit, a gauge and the reset date). One row per pack of `credits.offers()`: the credits the pack grants, the StoreKit display name and, on the buy button, StoreKit's display price. A pack StoreKit does not sell has no row.
- **Buying.** A tap runs `credits.buy(_:)`. The tapped button turns into a spinner and the other buttons are disabled until it ends, so only one purchase runs at a time. `credited` updates the balance and says how many credits arrived; `creditPending` adds a "your purchase is being confirmed" row that stays until `credits.events()` reports a credit (a purchase an earlier launch left unconfirmed shows the same row, by `unconfirmedPurchases`); `awaitingApproval` says the purchase waits for approval (Ask to Buy); `cancelled` shows nothing; a failure is one short message: offline, wallet unavailable (nothing was charged), session expired, too many requests, purchase could not be verified (contact support), packs not available, or the generic purchase failure.
- **Shortfall.** With `shortfall: N` a banner says the person needs N more credits and the smallest pack that covers it is marked "Enough for this". Zero or a negative number is ignored.
- **When the packs cannot load.** The balance still shows, the list says the packs are unavailable and Try again loads them again.
- **Layout.** One column, at most 560 points wide and centered, in the theme's surface, hairline and accent, so it reads the same in an iPhone sheet, an iPad or Mac window and every window of an iPhone Duo. An accessibility text size stacks each row and gives the buy button the full width; text uses the Midgar text styles and never truncates.
- **Colors.** The buy button's label color on the accent comes from `MidgarOnAccentLabel`, which MidgarCommerceUI shares with its paywall through `package` access.

## Languages

The string catalog carries English and de, es, fr, it, ja, ko, pl, pt-BR, zh-Hans and zh-Hant, as MidgarCommerceUI's does. Counts of credits take the plural form of each language (Polish has kredyt, kredyty and kredytów). Other languages fall back to English.

## Tests

`swift test --filter MidgarCreditsUITests` runs the model tests against a scripted wallet, checks every string in every language of the catalog (the plural forms of credits included) and renders the view on macOS in the layouts above, in light and dark; `MIDGAR_SNAPSHOT_DIR` collects the PNGs. On the iOS Simulator, where the accessibility text size is real: `xcodebuild test -scheme MidgarKit-Package -destination 'platform=iOS Simulator,id=<udid>' -only-testing:MidgarCreditsUITests`.
