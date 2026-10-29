import Foundation
import MidgarCore
@testable import MidgarUI

/// A shortened copy of the public stats answer: the keys the screen reads, the ones it ignores, and the shapes the server really uses (a number, `"<10"`, a retention share).
let publicStatsJSON = #"""
{
  "generated_at": "2026-10-29T22:22:36.144Z",
  "rules": { "min_count": 10, "weeks": 12, "months": 6, "note": "Each figure covers a finished ISO week." },
  "portfolio": { "weeks": [{ "period": "2026-10-19", "wau": 12, "new_installs": "<10", "purchases": "<10", "refunds": "<10", "ai_requests": "<10", "active_subscriptions": "<10" }], "months": [], "retention": [] },
  "apps": {
    "dream-eater": {
      "weeks": [
        { "period": "2026-10-12", "wau": "<10", "new_installs": "<10", "purchases": "<10", "refunds": "<10", "ai_requests": 14, "active_subscriptions": "<10" },
        { "period": "2026-10-19", "wau": "<10", "new_installs": "<10", "purchases": "<10", "refunds": "<10", "ai_requests": "<10", "active_subscriptions": "<10" }
      ],
      "months": [{ "period": "2026-09-01", "mau": "<10", "purchases": "<10", "refunds": "<10", "ai_requests": "<10", "active_subscriptions": "<10" }],
      "retention": [{ "cohort": "2026-08-03", "w1": "<10", "w4": null }]
    },
    "flaccy": {
      "weeks": [
        { "period": "2026-10-12", "wau": 9, "new_installs": 31, "purchases": "<10", "refunds": "<10", "ai_requests": "<10", "active_subscriptions": "<10" },
        { "period": "2026-10-19", "wau": 12, "new_installs": "<10", "purchases": "<10", "refunds": "<10", "ai_requests": "<10", "active_subscriptions": "<10" }
      ],
      "months": [],
      "retention": []
    }
  },
  "metrics": [{ "id": "wau", "title": "Weekly active installs", "unit": "installs", "caveat": "Counts installs, not people." }]
}
"""#

func decodePublicStats(_ json: String = publicStatsJSON) throws -> MidgarPublicStats {
    try JSONDecoder().decode(MidgarPublicStats.self, from: Data(json.utf8))
}

/// A loader that answers from a script and counts how often it was asked.
actor FakeStatsLoader: MidgarPublicStatsLoading {
    enum Script {
        case stats(MidgarPublicStats)
        case failure(any Error)
        case neverAnswers
    }

    private let script: Script
    private(set) var requests = 0

    init(_ script: Script) {
        self.script = script
    }

    func loadStats() async throws -> MidgarPublicStats {
        requests += 1
        switch script {
        case .stats(let stats): return stats
        case .failure(let error): throw error
        case .neverAnswers:
            try await Task.sleep(for: .seconds(600))
            throw CancellationError()
        }
    }
}

/// The on/off state of a fake switch, so a test can flip it the way the person would.
@MainActor
final class FakeSwitch {
    var isOn: Bool

    init(isOn: Bool = true) {
        self.isOn = isOn
    }

    var row: MidgarSettingsRow {
        .toggle(id: "midgar.usageCounts", title: "Share anonymous usage counts", isOn: { self.isOn }, setOn: { self.isOn = $0 })
    }
}

extension MidgarSettingsSection {
    func toggleSetter() -> MidgarSettingsRow.ToggleSetter? {
        guard case .toggle(_, let set)? = rows.first?.kind else {
            return nil
        }
        return set
    }
}

let fixtureCatalog: [MidgarSignalCatalog.Entry] = [
    .init(name: "fixture.active", purpose: "Daily, weekly and monthly active installs.", uniqueness: .perPeriod, carriesCohort: true),
    .init(name: "fixture.view", purpose: "How often the purchase screen is shown, and from where in the app.", uniqueness: .each),
    .init(name: "fixture.alpha", purpose: "Only alpha sends this.", uniqueness: .daily, apps: ["alpha"]),
    .init(name: "fixture.beta", purpose: "Only beta sends this.", uniqueness: .lifetime, apps: ["beta"]),
    .init(name: "fixture.reserved", purpose: "Nothing sends this yet.", uniqueness: .each, isReserved: true)
]
