# MidgarKit

The doorway between Midgar apps. One card in a host app's Settings opens the **portal**: a full-screen universe in the spirit of the original watchOS home screen, a honeycomb of round app icons that you drag around, with a fisheye that keeps the focused app large and everything else orbiting it. Tap an icon to see what it is, tap it again to install it without leaving the app.

- **Every app, everywhere.** The catalog is hosted, so all Midgar apps appear in every host the moment they ship. The host app itself stays in the universe as the "you are here" marker.
- **Knows what you have.** Installed apps get a tick and an OPEN button, the progress ring around the Midgar emblem counts them, and apps that live on another platform say so ("Mac", "iPhone") and offer to send the link.
- **Related apps sit closest.** The ranking puts apps related to the host nearest the centre and apps the person already has further out.
- **Fast by construction.** The portal is drawn with Core Animation layers only. A frame sets position, scale and opacity on pre-rendered textures, so the GPU does the work and the display link runs only while something moves.
- **Private.** Anonymous, aggregate counts only (portal opens, impressions, taps, per placement and storefront). No IDFA, no identifier, no user data. A privacy manifest ships in the package.
- **Native on every Apple platform.** UIKit on iOS, iPadOS, tvOS and visionOS; AppKit on macOS; SwiftUI wrappers for SwiftUI hosts.

## Install

```swift
.package(url: "https://github.com/guitaripod/MidgarKit", from: "4.0.0")
```

Add `MidgarKit` to every app target that ships. MidgarKit 4.0.0 is one package with several products. `import MidgarKit` keeps working for every 3.x host: the `MidgarKit` product is an umbrella that re-exports all the others, so `MidgarEntryView`, `MidgarEntryCard`, `MidgarStoreView`, `Midgar.present` and `MidgarConfig` are unchanged.

## Products

| Product | Holds | May import |
| --- | --- | --- |
| `MidgarKit` | Umbrella: `@_exported import` of every product below | all products |
| `MidgarCore` | Logging, config, HTTP, identity, signals, `MidgarKitVersion` | Foundation, os, Security, DeviceCheck, MetricKit, CryptoKit (Apple only) |
| `MidgarCommerce` | StoreKit purchases and entitlements | MidgarCore, StoreKit |
| `MidgarAccount` | Sign in with Apple and account linking | MidgarCore, AuthenticationServices |
| `MidgarUI` | Shared UIKit, AppKit and SwiftUI scaffolding | MidgarCore, UIKit, AppKit, SwiftUI, QuartzCore, CoreText, ImageIO |
| `MidgarPortal` | The portal: catalog, entry card and view, `Midgar.present`, telemetry, resources, privacy manifest | MidgarUI, MidgarCore, StoreKit, UIKit, AppKit, SwiftUI, QuartzCore, CoreText, ImageIO |
| `MidgarIntelligence` | On-device and cloud model access, FoundationModels behind `#if canImport(FoundationModels)` | MidgarCore, FoundationModels |
| `MidgarDemo` | Demo mode and seeded data | MidgarCore |

No product re-exports an Apple framework. A host that only wants the portal can depend on `MidgarPortal` and `import MidgarPortal`. Commerce, account, UI, intelligence and demo are placeholders until roadmap tasks P2.02 to P2.06 fill them. Package traits are not used: FoundationModels is gated with `canImport`, which needs no host configuration.

## Integrate a host app

1. **Put the card first in Settings.** UIKit: `MidgarEntryView().embed(in: cell.contentView, verticalInset: 8)` in a clear, non-selecting cell of height `MidgarEntryView.preferredHeight + 16`. SwiftUI: `MidgarEntryCard()` as a clear list row. macOS: `MidgarEntryView()` or `MidgarEntryCard()`. Tapping the card opens the portal itself; there is no handler to write.
2. **Register the schemes.** The host's own URL scheme is its lowercased bundle id, or its reserved slot when the catalog assigns one (`CFBundleURLTypes`), and `LSApplicationQueriesSchemes` lists exactly what `scripts/midgar_schemes.py` prints: 25 entries, the most iOS 27-linked apps may declare (`QUERY_SCHEME_CAP`), made of the 16 legacy bundle-id schemes and `midgar-01` to `midgar-09`. `--yaml` prints an xcodegen fragment. This is how installed apps are detected and opened; macOS needs nothing. `scripts/sync_schemes.py` brings a host's list under the cap: it keeps the host's other entries (the cap counts them too), then writes the Midgar list cut from the end, so the highest slots go first and a legacy scheme never does. It is a dry run unless given `--write`. The portal checks an app's `slot`, its `scheme` and its legacy bundle-id scheme and counts it installed if any answers.
3. **Ship it.** `scripts/audit_hosts.py --app Some.app --bundle-id com.example.app` checks a built app, and without arguments checks every host in `scripts/hosts.json`.

To open the portal from your own button: `Midgar.present(from: viewController, config: MidgarConfig(placement: "profile"), sourceView: button)`. The iris grows out of `sourceView`.

## Adding an app

1. **Publish it.** The worker reads the developer's App Store page every six hours and adds any live app it does not know, with its name, subtitle, icon and platform. It shows up in every host on the next catalog refresh. No host app changes and no release.
2. **Curate it (optional).** Add an entry to `worker/catalog.meta.json` for a better tagline, accent colour, topics, related apps, `featured` and `value`, then `python3 -I worker/scripts/gen_catalog.py` and `wrangler deploy`.
3. **Make it read as installed (optional).** Give the entry a reserved `scheme` such as `"midgar-07"` and register that scheme in the new app's own `CFBundleURLTypes`. `scheme` is only for apps whose sole scheme is a slot: releases 3.0 and 3.1 query nothing else for an app that has one. Hosts may declare at most 25 `LSApplicationQueriesSchemes` entries, so the slots are a budget, not a free reserve: `audit_hosts.py` fails any host above 25.

Migration path: today each of the 16 apps has a `slot` in `worker/catalog.meta.json` (`midgar-01` to `midgar-16`, a separate key so older hosts keep querying the bundle-id scheme) but still answers on its bundle-id scheme. Each app registers its own slot in `CFBundleURLTypes` at its next release. Hosts list the 16 legacy schemes plus `midgar-01` to `midgar-09` until every app has shipped that; after that, hosts list `midgar-01` to `midgar-25` only and the legacy schemes drop out.

## Identity (MidgarCore)

`MidgarIdentity` is the client of the Midgar ID (D12). Create one per app and let it authorize the app's HTTP client:

```swift
let http = MidgarHTTPConfiguration(appID: "solar-beam")
let identity = MidgarIdentity(httpConfiguration: http, bundleID: "com.midgarcorp.solarbeam")
let client = MidgarHTTPClient(configuration: identity.authorizing(http))
let appAccountToken = UUID(uuidString: try await identity.midgarId)
```

`appID` is the registry slug. The first call anywhere mints the ID (App Attest where supported, unverified otherwise), later apps and devices attach to it through the synchronizable keychain item, and refresh tokens are signed with an App Attest assertion. Add `registry/generated/identity.entitlements` (written by `midgar gen`) to the app's entitlements. `linkApple(identityToken:)`, `deleteIdentity()` and `export()` cover Sign in with Apple merging, erasure and the data export.

## Configuration

```swift
MidgarConfig(
    endpoint: MidgarConfig.defaultEndpoint, // catalog and telemetry service
    excludedBundleIDs: [],                  // apps to leave out of the portal
    enableTelemetry: true,                  // anonymous counts
    storefront: nil,                        // nil uses the device region
    placement: "settings",                  // reported with every event and the App Store campaign token
    providerToken: MidgarConfig.defaultProviderToken
)
```

Product pages open with a campaign token `<host>-<placement>` and the provider token, so App Store Connect can credit installs to the host and placement that drove them. Only people who share analytics with developers are counted, so treat the numbers as a lower bound.

## The catalog service

[`worker/`](worker/) is a Cloudflare Worker with a D1 database.

| Route | Purpose |
| --- | --- |
| `GET /v1/catalog` | The curated catalog (from `catalog.json`, overridable through the `catalog` KV key) plus auto-discovered apps |
| `GET /v1/discovered` | The apps the scheduled lookup found, as stored in the `discovered` KV key |
| `POST /v1/event` | Anonymous counters: `portal_open`, `impression`, `tap`, `loaded`, `launch`, by host, storefront, placement and day |
| `GET /v1/stats?by=app\|source\|storefront\|placement\|day&since=YYYY-MM-DD` | Aggregates; send the stats key as `Authorization: Bearer <key>` |

Apps live on the App Store appear in every host automatically: a scheduled run every 6 hours looks up the developer's apps and adds any that the curated catalog lacks, with sensible defaults (`auto: true`; inspect them at `GET /v1/discovered`). `catalog.meta.json` is only needed to improve them (tagline, accent, topics, related, platforms, value, featured/order) or to add `hide` (an array of bundle ids kept out of the portal) or `staged` entries; curated entries always win.

Edit `worker/catalog.meta.json` (taglines, accents, topics, related apps, platforms, value), then `python3 -I worker/scripts/gen_catalog.py` merges it with live App Store data, rewrites `catalog.json`, the bundled fallback and the fallback icons. `worker/scripts/audit_catalog.py` fails when a live app is missing from the catalog. Deploy with `wrangler deploy` from `worker/`.

## Developing

- `swift test` runs the portal engine tests (lattice, lens, camera physics, ranking, controller) in `MidgarPortalTests` and a module test per product.
- `MIDGAR_SNAPSHOT_DIR=/tmp/shots swift test --filter MidgarPortalTests.PortalSnapshotTests` renders the portal and the entry card to PNGs on the Mac (`MIDGAR_SNAPSHOT_SIZE=393x852`, `MIDGAR_SNAPSHOT_PLATFORM=mac`, `MIDGAR_SNAPSHOT_HOST=<bundle id>`).
- `scripts/install-demo.sh` builds `Examples/MidgarDemo`, installs it on the iPhone Air, runs a scripted self test (frame pacing and screenshots, Debug builds only) and collects the report.
- `scripts/check_strings.py` validates the string catalog.

## Requirements

iOS 16, macOS 13, tvOS 16, visionOS 1, Swift 6.0 (the package builds in Swift 6 language mode). Liquid Glass is used on iOS, macOS and tvOS 26 and later.
