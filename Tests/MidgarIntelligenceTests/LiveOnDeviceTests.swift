import Foundation
import Testing
@testable import MidgarIntelligence

@Suite struct LiveOnDeviceTests {
    /// Runs one real prompt through Foundation Models. Opt in with `MIDGAR_LIVE_FM=1` on a Mac or device with Apple Intelligence on.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MIDGAR_LIVE_FM"] == "1"))
    func realPromptAnswersOnDevice() async throws {
        let model = MidgarOnDeviceModel()
        guard case .available = model.availability else {
            Issue.record("Foundation Models unavailable here: \(model.availability)")
            return
        }
        let completion = try await model.respond(to: MidgarPrompt(text: "Reply with the single word: ready"))
        #expect(completion.route == .onDevice)
        #expect(!completion.text.isEmpty)
    }
}
