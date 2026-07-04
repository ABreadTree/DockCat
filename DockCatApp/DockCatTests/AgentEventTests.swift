import XCTest
@testable import DockCat

final class AgentEventTests: XCTestCase {
    func testDecodesValidMultiAgentEvent() throws {
        let data = """
        {
          "agent": "codex",
          "session": "task-123",
          "status": "working",
          "message": "Updating tests",
          "hint": "I am checking the build now."
        }
        """.data(using: .utf8)!

        let event = try AgentEvent.decode(from: data)

        XCTAssertEqual(event.agent, "codex")
        XCTAssertEqual(event.session, "task-123")
        XCTAssertEqual(event.status, .working)
        XCTAssertEqual(event.message, "Updating tests")
        XCTAssertEqual(event.hint, "I am checking the build now.")
    }

    func testRejectsBlankAgent() {
        let data = #"{"agent":" ","status":"info","message":"hello"}"#.data(using: .utf8)!

        XCTAssertThrowsError(try AgentEvent.decode(from: data)) { error in
            XCTAssertEqual(error as? AgentEvent.ValidationError, .missingAgent)
        }
    }

    func testRejectsUnknownStatus() {
        let data = #"{"agent":"codex","status":"dancing"}"#.data(using: .utf8)!

        XCTAssertThrowsError(try AgentEvent.decode(from: data)) { error in
            XCTAssertEqual(error as? AgentEvent.ValidationError, .unknownStatus("dancing"))
        }
    }

    func testTrimsAndCapsMessageAndHint() throws {
        let longMessage = String(repeating: "x", count: 240)
        let longHint = String(repeating: "y", count: 240)
        let data = """
        {"agent":" codex ","session":" task ","status":"info","message":"  \(longMessage)  ","hint":"  \(longHint)  "}
        """.data(using: .utf8)!

        let event = try AgentEvent.decode(from: data)

        XCTAssertEqual(event.agent, "codex")
        XCTAssertEqual(event.session, "task")
        XCTAssertEqual(event.message?.count, AgentEvent.maxTextLength)
        XCTAssertEqual(event.hint?.count, AgentEvent.maxTextLength)
        XCTAssertEqual(event.hint, String(longHint.prefix(AgentEvent.maxTextLength)))
    }
}
