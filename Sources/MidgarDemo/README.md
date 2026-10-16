# MidgarDemo

One launch-argument contract for screenshot and layout runs. A process launched with the contract
activates one demo world at one scene, seeds the app's state for it, and freezes the clock, so every
run of the same command captures the same pixels.

The module depends only on MidgarCore and Foundation, and builds on Linux.

## The contract

| Argument | Environment variable | Meaning |
|---|---|---|
| `-MidgarDemo <world>` | `MIDGAR_DEMO` | Turns demo mode on and names the world. Use the app's registry slug, for example `solar-beam`. |
| `-MidgarDemoScene <scene>` | `MIDGAR_DEMO_SCENE` | The scene to pose. Defaults to the world's first scene. |
| `-MidgarDemoDate <ISO-8601>` | `MIDGAR_DEMO_DATE` | The frozen "now". Must carry a time zone, for example `2026-10-16T09:41:00Z`. Fractional seconds are allowed. A bare date is rejected. Defaults to the activation time. |
| `-MidgarDemoLocale <identifier>` | `MIDGAR_DEMO_LOCALE` | The locale the world should present in, for example `fi_FI`. Defaults to `Locale.current`. |

Rules:

- Arguments win over environment variables, key by key.
- An empty environment variable counts as unset.
- An argument with no value, or followed by another `-` key, is an error (`missingValue`).
- A malformed date is an error even outside demo mode, so a broken command never runs quietly.
- Scene, date and locale do nothing without a world. Demo mode is on exactly when a world is named.
- The `-MidgarDemo` spelling matches the argument exactly, so `-MidgarDemoScene` never activates a world on its own.

`DemoLaunch.current` reads the process. `DemoLaunch.parse(arguments:environment:)` is the pure form the tests use.

## Gating

Demo mode fakes data and freezes the clock, so a shipping build must never enter it because of a launch argument or an environment variable. `activate` only honours the contract when `DemoGate.isPermitted` is true: always in DEBUG builds, and in a release build only when the app's Info.plist sets `MidgarDemoEnabled` to `YES`. Give the screenshot configuration of an app that key (an xcconfig-driven `INFOPLIST_KEY_MidgarDemoEnabled` or a plist merge) and leave it out of the App Store configuration. A build that is not permitted ignores the contract, writes one notice to the log and returns nil, so the app starts normally.

## Worlds, scenes and context

```swift
public protocol DemoWorld: Sendable {
    var id: String { get }
    var scenes: [DemoScene] { get }
    func prepare(_ scene: DemoScene, context: DemoContext) async throws
}
```

- `id` is the value `-MidgarDemo` selects. Ids must be unique within an app.
- `scenes` lists what the world can pose, in capture order. The first is the default.
- `prepare` seeds the app for one scene. It runs once per launch, before the first screen appears, and
  must produce the same state on every launch. It should wipe what an earlier launch left behind.

`DemoContext` carries what the world may assume:

| Property | Default in demo mode | Meaning |
|---|---|---|
| `date` | the frozen date | Use it for every date-driven value. |
| `locale` | the launch locale | The locale to present in. |
| `skipOnboarding` | `true` | Mark first-run onboarding complete. |
| `hidePaywall` | `true` | Do not present purchase UI on its own. |
| `suppressReviewPrompts` | `true` | Do not ask for an App Store review. |
| `suppressNetwork` | `true` | Answer network requests from fixtures, not the live backend. |

The flags default to the demo values, so a world that reads them never has to ask whether it is in a
screenshot run.

## Registry and activation

```swift
var registry = DemoRegistry()
try registry.register(DailyWorld())
try registry.register(SoloWorld())

let activation = try await registry.activate()
```

`activate()` returns a `DemoActivation` (the world, the scene and the context), or nil outside demo mode.
Each call first clears the frozen clock, so a failed or non-demo activation never leaves a stale date
behind. The clock freezes only after `prepare` succeeds, and a `prepare` that throws leaves it live, so `prepare` reads its date from `context.date`, never from `DemoClock`. Call it once, at launch, before the first scene is built.

Errors name the bad input and the valid choices:

- `unknownWorld` lists the registered worlds.
- `unknownScene` lists the world's scenes.
- `noScenes` means the world declares no scenes and none was named.
- `duplicateWorld` means two worlds share an id.

## Clock

```swift
let today = DemoClock.now
```

`DemoClock.now` is the frozen date while a demo world is active, and `Date()` otherwise. Code that
shows dates in a screenshot should read `DemoClock.now`, not `Date()`. The frozen value is set by
`activate`, so it is stable for the whole run.

## Current demo modes and their migration

Six apps have hand-written demo modes. The table records what each one switches today, found by
reading its repo (read only), and the contract it maps to. Repos are the `repo` values in
`registry/apps/*.toml`. World ids are the registry slugs.

| App (world id) | Repo | Today | Fake data | Frozen date | Onboarding, paywall, locale |
|---|---|---|---|---|---|
| Solar Beam (`solar-beam`) | `~/Dev/ios/solarbeam` | Env `SB_DEMO=1` or argument `-demoData 1`. Route `SB_ROUTE` or `-screenshotRoute`. Action `SB_ACTION` or `-screenshotAction`. Read in `ios/App/DemoMode.swift`, DEBUG only. `scripts/shots-ios.py` sets the `SIMCTL_CHILD_SB_*` variables. | A URL protocol answers every worker request from fixtures in `marketing/fixtures/demo`, so the run is offline. | No. APOD dates are rebased to `Date()`. | Onboarding is marked complete unless the route is `onboarding`. No paywall switch found. |
| Master of Flags (`master-of-flags`) | `~/Dev/ios/master-of-flags` | Arguments `-screenshotRoute` (play, daily, learn, train, you, country, paywall, gate, tipjar, settings, privacy), `-screenshotState`, `-screenshotSeed` (design, pro, empty), `-screenshotCountry`, `-screenshotRegion`. Environment equivalents are the upper-case names (`SCREENSHOT_ROUTE`). Parsed in `Packages/MofUI/.../IOSScreenshotRequest.swift`. `scripts/store/shoot.sh` also passes `-AppleLanguages` and `-AppleLocale`. | Seeded fixtures in `CouchFixtures` and the Daily history. | Not checked. | Paywall, gate and tipjar are routes. Locale is set by `-AppleLocale`, not by the app. |
| flaccy (`flaccy`) | `~/Dev/ios/flaccy` | Launch argument `--seed-screenshots` (DEBUG, Simulator only) and `--debut`. Environment `FLACCY_ROUTE` (songs, artists, album, artist, now-playing, equalizer and variants, lyrics, queue, charts), with `FLACCY_ALBUM`, `FLACCY_PLAYING`, `FLACCY_EQ`, `FLACCY_DEBUT`. `marketing/tools/capture_iphone.py` sets them per shot. | `ScreenshotSeeder` builds a fictional library. `DemoMode.primeCaches` fills portraits, tags and similar artists so the network is not needed. `DemoMode.version` erases stale content. | No. Seeds use `Date()`. | Not checked. `PaywallShot.swift` exists and was not read. |
| PayDay (`pay-day`) | `~/Dev/ios/PayDay` | Environment `PAYDAY_DEMO=<screen>` (dashboard, list, editor, preview, line, clients, client, settings, business, paywall, setup, onboarding). Record selectors `PAYDAY_DEMO_DOC` (number suffix) and `PAYDAY_DEMO_CLIENT` (name fragment). `PAYDAY_DEMO_COUNTRY` is set by the script. Read in `App/DemoRouting.swift`. | `Repositories/DemoWorld.swift` wipes and reseeds the database on every launch: a fictional seller, clients and invoices in every status. | No. `Format.today()` is live. | `AppSettings.hasOnboarded = true` is set. Paywall is a screen that is presented on top of the dashboard. Locale is set by `-AppleLocale`. |
| Embr (`embr`) | `~/Dev/ios/embr` | Environment `EMBR_DEMO=1` or argument `-embrDemo` (`DemoWorld.isActive`). Route `-screenshotRoute` or `SHOT_ROUTE`, with `-screenshotChannel`, `-screenshotFavorites`, `-screenshotGame`, `-screenshotQuery`, `-screenshotSkip`, `-screenshotTheme`, `-screenshotAuth`, `-screenshotStatusBar`, `-screenshotOrientation`, `-screenshotSidebar`, `-screenshotPopAfter`. Read in `App/ScreenshotRouter.swift`. `scripts/capture-store-shots.py` passes them per panel. | `Demo/DemoWorld.swift` (fictional channels), `DemoTransport`, `DemoChat`, `DemoVideoPlayer`. No live network. | No. Watch times are `Date()` minus a fixed offset. | Onboarding is marked complete unless the route is `onboarding`. Status bar and orientation are chrome, set by the router. |
| Helia (`helia`) | `~/Dev/ios/Helia` | Argument `-duoDemo` (DEBUG), `-duoCity <id>` (casaverano, halden, solmar, kestrel, tarn), `-duoPro 0` for the free tier. Read in `Features/Dev/DemoWorld.swift`. Separate `-uitestLAGallery` for one gallery. | Network, location, HealthKit and the on-device model are replaced by fixtures. | No. The city longitude is chosen at launch so local solar time is 13:00 on the live clock. | `DemoSubscriptionBacking` backs the paywall. Onboarding not checked. |

What a migration does, per app:

1. Replace the app's own switch (`SB_DEMO`, `PAYDAY_DEMO`, `--seed-screenshots`, `EMBR_DEMO`, `-duoDemo`,
   `-screenshotRoute` and so on) with `-MidgarDemo <slug>`. Keep the old switch only where a DEBUG
   tool still needs it, and mark it for removal.
2. Map the route or screen to the scene: `-screenshotRoute daily -screenshotState result` becomes
   `-MidgarDemo master-of-flags -MidgarDemoScene daily-result`. `PAYDAY_DEMO=editor` becomes
   `-MidgarDemoScene editor`.
3. Move the seeding into the world's `prepare`. Keep the fixtures and the reseed logic, and drop the
   parts that read the launch arguments.
4. Replace `Date()` with `context.date` or `DemoClock.now` in fixture code. Solar Beam's APOD rebase,
   Embr's watch times, PayDay's `Format.today()` and Helia's solar longitude all need this, or the frozen
   date does nothing for them.
5. Keep genuinely app-specific keys as app keys when they are not scenes. Examples: `FLACCY_ALBUM` picks
   the album for the `album` scene, `PAYDAY_DEMO_DOC` picks the invoice, `-screenshotChannel` picks the
   channel. Put them in the scene id (`album-parallax-hours`) when the set is small and fixed. Leave them
   as keys when it is open-ended.
6. Run the app's screenshot script through `midgar shots` with the new arguments, then diff the output
   against the pre-migration captures before deleting the old switch.

## Screenshot tooling

`ops/midgar/commands/` has no `shots` command yet (it has `arch`, `config`, `gen`, `ship`, `sync`), so
nothing was added there. When `midgar shots` lands, it passes these arguments for every shot of a run,
using the same date and locale for all of them:

```
-MidgarDemo <slug> -MidgarDemoScene <scene> -MidgarDemoDate <ISO-8601 with zone> -MidgarDemoLocale <identifier>
```

Through `xcrun simctl launch`, the arguments follow the bundle id. The environment form needs the
`SIMCTL_CHILD_` prefix, for example `SIMCTL_CHILD_MIDGAR_DEMO=<slug>`. Pass one form, not both, so a
reader of the command can see which keys are in effect.

## Tests

`swift test --filter MidgarDemoTests` covers parsing (arguments, environment, precedence, empty values,
malformed dates, missing values), registry activation (known and unknown worlds and scenes, worlds
without scenes, demo mode off, duplicate ids), the frozen and live clock, and the context flags. The
registry and clock tests share the process-wide clock, so they run in one serialized suite.
