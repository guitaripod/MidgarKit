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
.package(url: "https://github.com/guitaripod/MidgarKit", from: "3.2.0")
```

Hosts use `from: "3.2.0"` until MidgarKit 4.0.0 is tagged (roadmap P2.18); after that, `from: "4.0.0"`. Add `MidgarKit` to every app target that ships. From 4.0.0 on, MidgarKit is one package with several products (the layout below is the monorepo's). `import MidgarKit` keeps working for every 3.x host: the `MidgarKit` product is an umbrella that re-exports all the others, so `MidgarEntryView`, `MidgarEntryCard`, `MidgarStoreView`, `Midgar.present` and `MidgarConfig` are unchanged.

## Products

| Product | Holds | May import |
| --- | --- | --- |
| `MidgarKit` | Umbrella: `@_exported import` of every product below | all products |
| `MidgarCore` | Logging, config, HTTP, identity, `MidgarKitVersion` (signals planned, P2.06) | Foundation, os, Security, DeviceCheck, MetricKit, CryptoKit (Apple only) |
| `MidgarCommerce` | StoreKit purchases and entitlements | MidgarCore, StoreKit |
| `MidgarCredits` | AI credit packs on the Midgar ID wallet: balance, history, pack purchase and fast-track credit (replaces `AICredits`) | MidgarCore, MidgarCommerce |
| `MidgarAccount` | Sign in with Apple and account linking | MidgarCore, AuthenticationServices |
| `MidgarUI` | Shared UIKit, AppKit and SwiftUI scaffolding | MidgarCore, UIKit, AppKit, SwiftUI, QuartzCore, CoreText, ImageIO |
| `MidgarPortal` | The portal: catalog, entry card and view, `Midgar.present`, telemetry, resources, privacy manifest | MidgarUI, MidgarCore, StoreKit, UIKit, AppKit, SwiftUI, QuartzCore, CoreText, ImageIO |
| `MidgarIntelligence` | On-device and cloud model access, FoundationModels behind `#if canImport(FoundationModels)` | MidgarCore, FoundationModels |
| `MidgarDemo` | Demo mode and seeded data | MidgarCore |

No product re-exports an Apple framework. A host that only wants the portal can depend on `MidgarPortal` and `import MidgarPortal`. `MidgarUI`, `MidgarIntelligence` and `MidgarDemo` are built. `MidgarCommerce` and `MidgarAccount` are still stubs (one placeholder type each) until their roadmap tasks (P2.07 and P2.08 for Commerce, P2.10 for Account) fill them; `MidgarCore` has Logging, HTTP, Config, Identity and Signals. Package traits are not used: FoundationModels is gated with `canImport`, which needs no host configuration.

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

`appID` is the registry slug. The first call anywhere mints the ID (App Attest where supported, unverified otherwise), later apps and devices attach to it through the synchronizable keychain item, and refresh tokens are signed with an App Attest assertion. Add `registry/generated/identity.entitlements` (written by `midgar gen`) to the app's entitlements.

- **Wrong credential.** When `/attach` answers `identity_not_found` or `credential_expired`, the shared item is dead and a new identity replaces it. `invalid_credential` means another device rotated the credential and keychain sync is behind: the shared item stays, the call throws the transient `MidgarIdentityError.credentialPendingSync`, and the attach is retried on a later call, at most once an hour (earlier if sync delivers a different credential). The first failure time lives in the per-app item; only seven days of continuous `invalid_credential` mint a new identity, with a warning in the log.
- **App Attest that does not work** (4.3.1). Where `isSupported` is true but the app lacks the App Attest entitlement or its App ID differs, key generation or attestation fails on the device, or the service answers `attestation_invalid`. The mint or attach then runs again without evidence, so the app still gets a Midgar ID on the `unverified` tier (no free grants; purchases work). The failure is remembered in memory until the process ends, so refreshes and attaches do not generate a key each time, and the next launch tries again. Apple's attestation service being unreachable (`MidgarAttestationError.unavailable`) still throws, because a keyless session stays keyless. Proofs for a key-bound session need an assertion and have no fallback.
- **Linking Sign in with Apple** takes two steps, because the identity token must carry the nonce of a server challenge. `prepareAppleLink()` returns a `MidgarAppleLinkRequest`; put its `nonce` into `ASAuthorizationAppleIDRequest.nonce`, run the sheet, then call `linkApple(identityToken:with:)`. The link is proved with an App Attest assertion for a key-bound session and with the ID credential otherwise. The challenge is spent by the attempt, so a failed link needs a new `prepareAppleLink()`.
- **`deleteIdentity()`** proves itself the same way and is sent exactly once. When the answer is lost, a later call that finds the identity gone counts the deletion as done and clears both keychain items.
- **Tokens.** `identity.authorizing(configuration)` wires the identity in as the token provider and invalidator. A request the service rejects with `token_expired` or `invalid_token` is sent again once with a fresh token; a provider that cannot produce a token fails the request with `MidgarHTTPError.tokenUnavailable(isTransient:)` instead of sending it without `Authorization`. Call `invalidateAccessToken()` yourself when a service outside `MidgarHTTPClient` rejects the token. Expiry is counted from the reply's `expiresIn` on the device clock, so a skewed clock cannot cause a refresh on every call.
- **`midgarId`** is the ID the service last returned to this app's session, and it follows the service after a merge or a recovery. It is not the shared item's ID: after a merge on another device the shared item still names the merged-away ID for up to seven days.
- **Keychain entitlement.** Without the keychain access group entitlement (`errSecMissingEntitlement`, -34018) the identity falls back to an app-local item for that run and logs one warning; such an app has an identity of its own until the entitlement is added. App extensions pass their host app's bundle id as `bundleID`, because the service checks it against the host app's registry entry and App Attest binds to it.

`deleteIdentity()` and `export()` cover erasure and the data export.

`midgarTokenHeader(within:)` (4.3.0) answers the `X-Midgar-Token` header with the current access token, or nil when the identity does not answer within the timeout. It never throws and never waits longer than the timeout, so a call that carries the header is never held up by it. `AsyncTimeout.run(for:operation:)` is the public primitive behind it. Handing mako the Midgar ID on every AICredits call is one line:

```swift
let credits = AICreditsConfig(
    baseURL: backendURL,
    appID: "myapp",
    additionalHeaders: { await identity.midgarTokenHeader(within: .seconds(2)).map { [$0.name: $0.value] } ?? [:] }
)
```

## Errors and public enums

`MidgarHTTPError` keeps the envelope's `code` for 401, 402, 404 and 429 (`.unauthorized(code:)`, `.paymentRequired(code:)`, `.notFound(code:)`, `.rateLimited(retryAfter:code:)`); `serverCode` reads it for every case that has one, and a pattern without the payload (`case .unauthorized:`) ignores it.

MidgarKit adds cases to its public enums in minor releases (`MidgarHTTPError`, `MidgarIdentityError`, `MidgarIntelligenceError`, `MidgarConfigError`, `MidgarAttestationError`, `MidgarKeychainSlot`, the demo and routing enums). Clients must switch over them with `@unknown default`:

```swift
switch error {
case .offline, .timeout:
    retryLater()
@unknown default:
    show(error.localizedDescription)
}
```

## Demo mode

MidgarDemo enters demo mode only in DEBUG builds, or in a release build whose Info.plist sets `MidgarDemoEnabled` to `YES`. Any other build ignores the launch contract. Details in `Sources/MidgarDemo/README.md`.

## Config

`MidgarConfigStore` verifies every document against the pinned keys, rejects a document whose `minVersion` or `kill` has the wrong type, and keeps the highest accepted version in a `UserDefaults` suite (`cc.midgarcorp.midgarkit.config`) apart from the cache file, so deleting or swapping the cache cannot roll the app back. On Linux verification still fails closed, because it needs CryptoKit; follow-up: add swift-crypto so Linux clients can verify.

## Signals

`MidgarSignals` (in MidgarCore) is the anonymous analytics client (D7): no vendor SDK, no Midgar ID, no device id, no `Authorization` header. It queues named events with a few props and sends them in batches to `POST /v1/signals/events`; the server (`services/signals`) keeps daily counts per app, event and platform.

```swift
MidgarSignals.configure(
    configuration: MidgarHTTPConfiguration(appID: "dream-eater"),
    config: { configStore.current }
)
await MidgarSignals.shared?.record("paywall.view", props: ["placement": "settings"])
```

- Props are `String`, `Int`, `Double` or `Bool` (`MidgarSignalValue` takes literals). Strings are cut to 64 characters. Only names and props from the server schema are kept; the server drops an event with an unknown name or prop and counts it.
- Events go out when 20 are queued, every 60 seconds while any wait, and at least 10 seconds apart, in batches of at most 50 events and 32 KB. The queue holds 500 events (oldest dropped first) and is saved to `Application Support/Midgar/signals-<app>.json`, so unsent events survive a relaunch.
- Offline, a timeout and 5xx keep the events. 429 keeps them and waits for `Retry-After` (60 seconds without one). Any other 4xx drops the batch and logs once.
- Call `await MidgarSignals.shared?.flush()` when the app moves to the background (for example on `scenePhase == .background`): the OS may suspend the app before the next timer. `flush()` sends everything queued and ignores the 10 second spacing, but still waits out a `Retry-After`.
- The `signals` key in the app's remote config `kill` list turns `record` into a no-op and empties the queue. Pass `config: { store.current }` so the client reads it.
- `X-Platform` comes from the OS (`ios`, `ipados`, `macos`, `tvos`, `visionos`, `watchos`, `android`, `linux`) and `X-App-Version` from `CFBundleShortVersionString`.
- iOS and macOS: `await MidgarSignals.shared?.startCollectingMetrics()` subscribes to MetricKit. Each daily metrics payload becomes one `metrics.daily` event (`coldLaunchMs`, `hangSecondsPerHour`, `foregroundSeconds`, `peakMemoryMB`) and each diagnostic payload one `metrics.diagnostics` event (`crashes`, `hangs`, `diskWrites`, `cpuExceptions`).
- The portal reports `portal_open`, `impression`, `tap`, `loaded` and `launch` through `MidgarSignals.shared` with the props `appId`, `storefront` and `placement`. It sends nothing, and keeps working, until the host calls `MidgarSignals.configure`. The host app is identified by the client's `X-App-ID`, so a host must configure signals with its registry slug.

Tests: `swift test --filter Signals`. `MIDGAR_LIVE_SIGNALS=1 swift test --filter SignalsLive` sends one real `app.launch` for `dream-eater` to production, which leaves a row in `daily` that must be deleted afterwards.

## Logging

Logs go to `Library/Logs/app.log` with rotation. A log file that is deleted while the app runs is created again on the next write, and the `Library/Logs` directory is excluded from iCloud and device backups.

## Configuration

```swift
MidgarConfig(
    endpoint: MidgarConfig.defaultEndpoint, // catalog service
    excludedBundleIDs: [],                  // apps to leave out of the portal
    enableTelemetry: true,                  // anonymous counts, sent through MidgarSignals
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
