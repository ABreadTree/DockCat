import XCTest
import Darwin
@testable import DockCat

final class AgentHTTPRequestParserTests: XCTestCase {
    func testServerCanBeConstructedWithoutStarting() {
        let server = AgentHTTPServer(port: 8765) { _ in }

        XCTAssertFalse(server.isRunning)
    }

    func testServerAcceptsLoopbackAgentEvent() throws {
        let port: UInt16 = 18765
        let eventStore = CapturedAgentEvent()
        let server = AgentHTTPServer(port: port) { event in
            eventStore.set(event)
        }

        server.start()
        defer { server.stop() }

        guard waitUntil(timeout: 2.0, condition: { server.isRunning }) else {
            XCTFail("AgentHTTPServer did not start listening")
            return
        }

        let body = #"{"agent":"codex","session":"manual","status":"info","message":"hello"}"#
        let request = makeRequest(headers: ["Content-Length: \(body.utf8.count)"], body: body)

        let response = try sendLoopbackRequest(port: port, request: request)

        XCTAssertTrue(String(decoding: response, as: UTF8.self).hasPrefix("HTTP/1.1 204 No Content\r\n"))
        XCTAssertTrue(waitUntil(timeout: 1.0) {
            eventStore.value != nil
        })
        let event = eventStore.value
        XCTAssertEqual(event?.agent, "codex")
        XCTAssertEqual(event?.session, "manual")
        XCTAssertEqual(event?.status, .info)
    }

    func testRequestBufferWaitsForSplitBodyBytes() {
        let body = #"{"agent":"codex","status":"info"}"#
        let header = "POST /agent-events HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n"
        var buffer = AgentHTTPRequestBuffer()

        XCTAssertEqual(buffer.append(Data((header + "{").utf8)), .needsMoreData)

        let result = buffer.append(Data(body.dropFirst().utf8))

        XCTAssertEqual(result, .ready(Data((header + body).utf8)))
    }

    func testRequestBufferRejectsMalformedContentLength() {
        let request = Data("POST /agent-events HTTP/1.1\r\nContent-Length: nope\r\n\r\n{}".utf8)
        var buffer = AgentHTTPRequestBuffer()

        XCTAssertEqual(buffer.append(request), .badRequest)
    }

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
        let httpResponse = AgentHTTPResponse(statusCode: 418)

        XCTAssertEqual(httpResponse.statusCode, 500)
        let response = String(decoding: httpResponse.data, as: UTF8.self)

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

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return condition()
    }

    private func sendLoopbackRequest(port: UInt16, request: Data) throws -> Data {
        let fileDescriptor = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        XCTAssertGreaterThanOrEqual(fileDescriptor, 0)
        defer { close(fileDescriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                connect(fileDescriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(connected, 0)

        request.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var bytesSent = 0
            while bytesSent < rawBuffer.count {
                let result = send(fileDescriptor, baseAddress.advanced(by: bytesSent), rawBuffer.count - bytesSent, 0)
                XCTAssertGreaterThan(result, 0)
                bytesSent += result
            }
        }

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = recv(fileDescriptor, &buffer, buffer.count, 0)
            if count <= 0 { break }
            response.append(buffer, count: count)
        }
        return response
    }
}

private final class CapturedAgentEvent: @unchecked Sendable {
    private let lock = NSLock()
    private var event: AgentEvent?

    var value: AgentEvent? {
        lock.lock()
        defer { lock.unlock() }
        return event
    }

    func set(_ event: AgentEvent) {
        lock.lock()
        self.event = event
        lock.unlock()
    }
}
