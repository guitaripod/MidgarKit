import Foundation
import Testing
@testable import MidgarUI

@Suite @MainActor struct UsageCountsHostTests {
    @Test func theHostSetsItsOwnTitle() {
        let model = MidgarUsageCountsModel(appID: "flaccy", loader: FakeStatsLoader(.neverAnswers))

        #expect(MidgarUsageCountsViewController(model: model).title == "Usage Counts")
    }

    @Test func theHostBuildsFromTheSlugAlone() {
        #expect(MidgarUsageCountsViewController(appID: "flaccy").title == "Usage Counts")
    }
}
