import XCTest
@testable import DockCat

final class AgentHTTPRequestParserTests: XCTestCase {
    func testParsesValidPostEventRequest() throws {
        let body = #"{"agent":"codex","status":"info","message":"hello"}"#
        let request = (
            "POST /agent-events HTTP/1.1\r\n" +
            "Host: 127.0.0.1:8765\r\n" +
            "Content-Type: application/json\r\n" +
            "Content-Length: \(body.utf8.count)\r\n" +
            "\r\n" +
            body
        ).data(using: .utf8)!

        let result = try AgentHTTPRequestParser.parse(request)

        XCTAssertEqual(result.agentEvent.agent, "codex")
        XCTAssertEqual(result.agentEvent.status, .info)
    }

    func testRejectsWrongPath() {
        let request = "POST /wrong HTTP/1.1\r\nContent-Length: 2\r\n\r\n{}".data(using: .utf8)!

        XCTAssertEqual(AgentHTTPRequestParser.response(for: request).statusCode, 404)
    }

    func testRejectsWrongMethod() {
        let request = "GET /agent-events HTTP/1.1\r\nContent-Length: 0\r\n\r\n".data(using: .utf8)!

        XCTAssertEqual(AgentHTTPRequestParser.response(for: request).statusCode, 405)
    }

    func testRejectsOversizedBody() {
        let body = String(repeating: "x", count: AgentHTTPRequestParser.maxBodyBytes + 1)
        let request = (
            "POST /agent-events HTTP/1.1\r\n" +
            "Content-Length: \(body.utf8.count)\r\n" +
            "\r\n" +
            body
        ).data(using: .utf8)!

        XCTAssertEqual(AgentHTTPRequestParser.response(for: request).statusCode, 400)
    }

    func testUnknownResponseStatusDefaultsToInternalServerError() {
        let response = String(decoding: AgentHTTPResponse(statusCode: 418).data, as: UTF8.self)

        XCTAssertTrue(response.hasPrefix("HTTP/1.1 500 Internal Server Error\r\n"))
    }
}
