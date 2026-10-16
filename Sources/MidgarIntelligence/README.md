# MidgarIntelligence

The one seam for language-model calls. An app asks `MidgarIntelligence` and never learns which model answered unless it looks at `MidgarCompletion.route`.

Depends on MidgarCore and, where the SDK has it, FoundationModels. Builds on Linux, where the on-device model reports `.unavailable(.platformUnsupported)`.

## Use

```swift
let intelligence = MidgarIntelligence(client: httpClient, configStore: configStore)

let completion = try await intelligence.respond(
    to: MidgarPrompt(instructions: "Answer in one sentence.", text: question, maxOutputTokens: 120)
)
completion.text
completion.route            // .onDevice or .cloud
completion.creditsCharged   // nil on device, mako's charge in the cloud

for try await delta in intelligence.streamResponse(to: prompt) { ... }
```

## Routing

1. Kill switch `intelligence` on: every call throws `.disabled`.
2. `requirement == .cloudOnly`, or the prompt carries an image: cloud. With `intelligence.cloud` killed it throws `.cloudDisabled`.
3. On-device model available: it answers. If it fails with anything but cancellation, the cloud answers instead. With `intelligence.cloud` killed the failure throws as `.onDeviceFailed`.
4. On-device model unavailable (`.deviceNotEligible`, `.appleIntelligenceNotEnabled`, `.modelNotReady`, `.operatingSystemTooOld`, `.platformUnsupported`, `.unknown`): cloud. With `intelligence.cloud` killed it throws `.onDeviceUnavailable(reason)`.

The kill switch snapshot is read on every call. A cancelled call never falls back. A stream falls back only before its first delta, because splicing two models into one answer is worse than an error.

## The cloud

`MidgarCloudModel` posts mako's plain chat completion through the gateway:

| Call | Gateway path | mako path |
|---|---|---|
| `respond`, `streamResponse` | `POST /v1/intelligence/v1/run/chat.completion` | `POST /v1/run/chat.completion` |
| `balance()` | `GET /v1/intelligence/v1/credits/balance` | `GET /v1/credits/balance` |

The gateway forwards the path after `/v1/intelligence`, so mako's own `/v1/` prefix appears twice. Request: `{messages, images?, model?}`. Response: `{content, model, credits_charged, usage}`. 402 becomes `.needsCredits`, 429 becomes `.rateLimited(retryAfter:)`, anything else `.cloudFailed(MidgarHTTPError)`. POSTs are never retried, so a slow answer is never charged twice.

Limits of mako today:

- It answers in one piece, so the cloud "stream" is one delta.
- Its plain chat endpoint ignores `maxOutputTokens` and `temperature`. Those hints reach the on-device model only.
- Free grants need an `app_attest` identity (D12). An `unverified` identity gets `.needsCredits` until it buys credits or a Pass.

## Metering

On-device calls are free and not metered. Cloud calls are metered by mako, which reports `credits_charged` per call. `MidgarCloudModel.balance()` reads the per-app balance and weekly free buckets. TODO(P3.07): read the Pass allowance and the per-Midgar-ID wallet once the intelligence service exposes an endpoint for it.

## Logging

Routing decisions log through `MidgarLog` (category `intelligence`) as route names and error type names. Prompt, instructions and completion text are never logged. Pass `logger:` to capture the lines.

## Foundation Models and traits

The package is at swift-tools-version 6.0, which has no package traits (they start at 6.1). The on-device code sits behind `#if canImport(FoundationModels) && !os(tvOS)` and `#available(iOS 26, macOS 26, visionOS 26, *)` instead. Move to a `FoundationModels` trait when the tools version moves to 6.1.

## Migrating from AICredits

| AICredits | MidgarIntelligence |
|---|---|
| `client.run(.chat(messages:images:responseJSON:))` | `intelligence.respond(to: MidgarPrompt(instructions:text:images:))` |
| `client.stream(.chat(...))` | `intelligence.streamResponse(to:)`. Deltas are text, not `JSONValue` events. |
| `CapabilityResult` body `content` | `MidgarCompletion.text` |
| `credits_charged` in the result | `MidgarCompletion.creditsCharged` |
| `client.balance()` | `MidgarCloudModel.balance()` |
| `AICreditsError.insufficientCredits` | `MidgarIntelligenceError.needsCredits` (no required and available counts: the gateway error does not carry them) |
| `AICreditsError.rateLimited(retryAfter:)` | `MidgarIntelligenceError.rateLimited(retryAfter:)` |
| `client.bootstrap()`, `link`, `signOut` | MidgarCore identity |
| `packs()`, `catalog()`, `purchase(_:)`, `transactions(limit:)` | MidgarCommerce (P2.09) |
| `estimate(_:)`, image capabilities, realtime | Not covered here: images and realtime stay on AICredits until their seams exist |
| `responseJSON: true` | Not supported yet. Put the format in `instructions`. |
