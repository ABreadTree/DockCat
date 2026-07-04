import XCTest
@testable import DockCat

final class AgentHTTPRequestParserTests: XCTestCase {
    func testParsesValidPostEventRequest() throws {
        let body = #"{"agent":"codex","status":"info","message":"hello"}"#
        let request = makeRequest(
            headers: [
                "Host: 127.0.0.1:8765",
                "Content-Type: application/json",
                "Content-Length: \(body.utf8.count)"
            ],
            body: body
        )

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
        let request = makeRequest(headers: ["Content-Length: \(body.utf8.count)"], body: body)

        XCTAssertEqual(AgentHTTPRequestParser.response(for: request).statusCode, 400)
    }

    func testUnknownResponseStatusDefaultsToInternalServerError() {
        let response = String(decoding: AgentHTTPResponse(statusCode: 418).data, as: UTF8.self)

        XCTAssertTrue(response.hasPrefix("HTTP/1.1 500 Internal Server Error\r\n"))
    }

    func testRejectsNegativeContentLengthWithoutCrashing() {
        let request = makeRequest(headers: ["Content-Length: -1"], body: "{}")

        XCTAssertEqual(AgentHTTPRequestParser.response(for: request).statusCode, 400)
    }

    func testRejectsNonNumericContentLength() {
        let request = makeRequest(headers: ["Content-Length: nope"], body: "{}")

        XCTAssertEqual(AgentHTTPRequestParser.response(for: request).statusCode, 400)
    }

    func testRejectsMissingContentLength() {
        let request = makeRequest(headers: [], body: "{}")

        XCTAssertEqual(AgentHTTPRequestParser.response(for: request).statusCode, 400)
    }

    func testRejectsDuplicateContentLength() {
        let body = #"{"agent":"codex","status":"info"}"#
        let request = makeRequest(
            headers: ["Content-Length: \(body.utf8.count)", "Content-Length: \(body.utf8.count)"],
            body: body
        )

        XCTAssertEqual(AgentHTTPRequestParser.response(for: request).statusCode, 400)
    }

    func testRejectsBodyShorterThanDeclaredContentLength() {
        let request = makeRequest(headers: ["Content-Length: 3"], body: "{}")

        XCTAssertEqual(AgentHTTPRequestParser.response(for: request).statusCode, 400)
    }

    func testAcceptsCaseInsensitiveContentLengthHeaderName() {
        let body = #"{"agent":"codex","status":"info"}"#
        let request = makeRequest(headers: ["content-length: \(body.utf8.count)"], body: body)

        XCTAssertEqual(AgentHTTPRequestParser.response(for: request).statusCode, 204)
    }

    func testParsesMultiByteUTF8BodyUsingByteContentLength() throws {
        let body = #"{"agent":"codex","status":"info","message":"你好"}"#
        let request = makeRequest(headers: ["Content-Length: \(body.utf8.count)"], body: body)

        let result = try AgentHTTPRequestParser.parse(request)

        XCTAssertEqual(result.agentEvent.message, "你好")
    }

    private func makeRequest(
        method: String = "POST",
        path: String = "/agent-events",
        headers: [String],
        body: String
    ) -> Data {
        let headerLines = ([method + " " + path + " HTTP/1.1"] + headers).joined(separator: "\r\n")
        return (headerLines + "\r\n\r\n" + body).data(using: .utf8)!
    }
}
