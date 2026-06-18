# Midgar

A beautiful, drop-in **in-app App Store** for cross-promoting your other apps. One line to embed; the catalog updates without an app release.

- **UIKit, native, in-app.** A polished list with live icons, ratings, prices, and screenshots — installs happen inside your app via `SKStoreProductViewController`, users never leave.
- **Curated, always current.** A hosted catalog (Cloudflare Worker) decides which apps, in what order, with editorial taglines and featured flags. Every entry is enriched at runtime with live App Store data for the user's region.
- **Resilient.** Last-good catalog and a fully-enriched snapshot are cached on disk; a bundled fallback ships in the package, so the store renders instantly and works offline.
- **Self-aware.** The host app's own bundle id is excluded automatically — an app never advertises itself.
- **Private by default.** Anonymous, opt-out tap/impression counts only; ships a privacy manifest; no tracking, no IDFA, no user data.

## Install

Swift Package Manager:

```swift
.package(url: "https://github.com/guitaripod/Midgar", from: "1.0.0")
```

Then add `Midgar` to your app target.

## Use

Midgar is **UIKit-only** — one call presents the storefront from anywhere.

From a UIKit settings/about screen (e.g. on a row tap):

```swift
import Midgar

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

iOS 16+ · Swift 5.9+
