import XCTest
@testable import DockCat

final class AgentHTTPServerSettingsTests: XCTestCase {
    func testSecondServerOnSamePortReportsNotRunning() {
        let port = UInt16(18_765)
        let first = AgentHTTPServer(port: port) { _ in }
        let second = AgentHTTPServer(port: port) { _ in }
        defer {
            first.stop()
            second.stop()
        }

        first.start()
        second.start()

        XCTAssertTrue(first.isRunning)
        XCTAssertFalse(second.isRunning)
        XCTAssertEqual(second.lastStartError, .bindFailed)
    }
}
