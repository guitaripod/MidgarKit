import Foundation
import Testing
@testable import MidgarCore

@Suite struct LogDirectoryTests {
    @Test func linuxLogsGoUnderTheXDGStateDirectory() {
        let url = LogConfiguration.linuxStateDirectory(environment: ["HOME": "/home/ada", "XDG_STATE_HOME": "/var/state/ada"], processName: "Crucible")
        #expect(url.path == "/var/state/ada/crucible/logs")
    }

    @Test func linuxLogsFallBackToTheHomeStateDirectory() {
        let unset = LogConfiguration.linuxStateDirectory(environment: ["HOME": "/home/ada"], processName: "crucible")
        #expect(unset.path == "/home/ada/.local/state/crucible/logs")
        let relative = LogConfiguration.linuxStateDirectory(environment: ["HOME": "/home/ada", "XDG_STATE_HOME": "state"], processName: "crucible")
        #expect(relative.path == "/home/ada/.local/state/crucible/logs")
    }
}
