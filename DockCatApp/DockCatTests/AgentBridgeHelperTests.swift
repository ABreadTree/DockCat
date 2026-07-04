import XCTest
@testable import DockCat

final class AgentBridgeHelperTests: XCTestCase {
    func testGeneratedHelperUsesLoopbackAndSafeChaining() {
        let script = AgentBridgeHelper.script(defaultPort: 8765)

        XCTAssertTrue(script.contains("127.0.0.1"))
        XCTAssertTrue(script.contains("--chain"))
        XCTAssertFalse(script.contains("eval "))
        XCTAssertFalse(script.contains("sh -c"))
    }

    func testCodexWrapperArgumentsPreservePreviousNotifyAfterChainSeparator() throws {
        let oldNotify = ["/usr/local/bin/notify", "old", "arg"]
        let arguments = AgentBridgeHelper.commandArguments(
            helperPath: "/Users/test/Library/Application Support/DockCat/AgentBridge/dockcat-agent-event",
            agent: .codex,
            port: 8765,
            session: "session-1",
            chainedCommand: oldNotify
        )

        let chainIndex = try XCTUnwrap(arguments.firstIndex(of: "--chain"))
        XCTAssertEqual(arguments[chainIndex + 1], "--")
        XCTAssertEqual(Array(arguments.dropFirst(chainIndex + 2)), oldNotify)
    }
}
