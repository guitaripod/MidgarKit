# MidgarKit

A beautiful, drop-in **in-app App Store** for cross-promoting your other apps. One line to embed; the catalog updates without an app release.

- **Native on every Apple platform.** UIKit on iOS / iPadOS / visionOS / Mac Catalyst, AppKit on native macOS, with thin SwiftUI wrappers (`MidgarStoreView`, `.midgarStore(isPresented:)`) for SwiftUI hosts. A polished list with live icons, ratings, prices, and screenshots — on iOS installs happen inside the app via `SKStoreProductViewController`; on macOS it opens the Mac App Store.
- **Curated, always current.** A hosted catalog (Cloudflare Worker) decides which apps, in what order, with editorial taglines and featured flags. Every entry is enriched at runtime with live App Store data for the user's region.
- **Resilient.** Last-good catalog and a fully-enriched snapshot are cached on disk; a bundled fallback ships in the package, so the store renders instantly and works offline.
- **Self-aware.** The host app's own bundle id is excluded automatically — an app never advertises itself.
- **Private by default.** Anonymous, opt-out tap/impression counts only; ships a privacy manifest; no tracking, no IDFA, no user data.

## Install

Swift Package Manager:

```swift
.package(url: "https://github.com/guitaripod/MidgarKit", from: "2.0.0")
```

Then add `MidgarKit` to your app target.

## Use

Midgar is **UIKit-only** — one call presents the storefront from anywhere.

From a UIKit settings/about screen (e.g. on a row tap):

```swift
import MidgarKit

func didTapMoreApps() {
    Midgar.present(from: self)
}
```

Embed or push the controller yourself:

```swift
let store = Midgar.makeStoreViewController(config: .init(accent: .systemPink))
present(store, animated: true)
```

From a SwiftUI host — no presenter needed, it finds the top view controller:

```swift
Button("More Apps") { Midgar.present() }
```

## Configure

Everything has a production-ready default.

```swift
MidgarConfig(
    endpoint: MidgarConfig.defaultEndpoint, // catalog + telemetry service
    accent: nil,                            // nil inherits the presenter's tint
    title: "More Apps",
    excludedBundleIDs: [],                  // own bundle id is always excluded
    enableTelemetry: true,                  // anonymous tap/impression counts
    storefront: nil                         // nil uses the device region
)
```

## Telemetry & privacy

Midgar reports **anonymous, aggregate** impression/tap counts per promoted app (no IDFA/IDFV, no user identifier, no cross-app linkage) so you can see which apps your cross-promotion drives. It ships a `PrivacyInfo.xcprivacy` declaring `Product Interaction` (not linked, not tracking, analytics purpose).

Telemetry is on by default. Disable it per host app:

```swift
Midgar.present(from: self, config: MidgarConfig(enableTelemetry: false))
```

The package only ever promotes the catalog owner's own apps: the host app's own bundle id is auto-excluded, and any catalog entry whose live App Store `artistId` doesn't match the catalog's developer is dropped client-side.

## Catalog service

The default catalog lives in [`worker/`](worker/) — a Cloudflare Worker exposing:

| Route | Purpose |
| --- | --- |
| `GET /v1/catalog?exclude=<bundleId>` | Curated, ordered catalog (KV-overridable, inline default) |
| `POST /v1/event` | Anonymous impression/tap counters |
| `GET /v1/stats` | Aggregated counters |

Update the curated list by editing [`worker/catalog.json`](worker/catalog.json) and redeploying, or by writing a `catalog` key to the `MIDGAR` KV namespace — no app release required.

## How the data flows

```
host app ──bundleId──▶ Worker /v1/catalog   (curated: ids, order, tagline, featured)
                           │
                           ▼
            enrich each id ▶ iTunes lookup (user's storefront: icon, ★rating, screenshots, price)
                           │
                           ▼
            missing / region-locked / offline ▶ disk snapshot ▶ bundled fallback
                           │
                           ▼
                    native storefront sheet
```

## Requirements

iOS 16+ · macOS 13+ · visionOS 1+ · Swift 5.9+
