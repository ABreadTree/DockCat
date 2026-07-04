# Agent HTTP Pet Status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a default-on localhost HTTP endpoint that accepts multi-agent status events and turns them into DockCat pet motions and speech bubbles.

**Architecture:** Add three small core pieces: `AgentEvent` for validation, `AgentEventPresenter`/`AgentEventQueue` for status-to-pet behavior and coalescing, and `AgentHTTPServer` for the `127.0.0.1:8765` POST endpoint. `DockCatApplication` remains the only owner of pet UI state; the HTTP layer never touches AppKit views directly.

**Tech Stack:** Swift 6, AppKit, Foundation, Network.framework, XCTest, existing DockCat Xcode project.

---

## File Structure

- Create `DockCatApp/DockCat/Core/Agent/AgentEvent.swift`
  - Defines `AgentStatus`, `AgentEvent`, validation errors, and JSON decoding.
- Create `DockCatApp/DockCat/Core/Agent/AgentEventPresenter.swift`
  - Maps status events to action, priority, bubble text, and acknowledgement behavior.
- Create `DockCatApp/DockCat/Core/Agent/AgentEventQueue.swift`
  - Maintains a five-item pending queue with `agent + session` coalescing for low-priority events.
- Create `DockCatApp/DockCat/Core/Agent/AgentHTTPServer.swift`
  - Starts/stops the loopback listener and accepts events.
- Create `DockCatApp/DockCat/Core/Agent/AgentHTTPRequestParser.swift`
  - Parses the tiny HTTP subset for tests and the server.
- Modify `DockCatApp/DockCat/App/DockCatApplication.swift`
  - Owns `AgentHTTPServer`, starts it on launch, stops it on terminate, and applies presentations through existing pet UI helpers.
- Modify `DockCatApp/DockCat/Support/AppStrings.swift`
  - Adds localized fallback strings for agent bubbles.
- Create `DockCatApp/DockCatTests/AgentEventTests.swift`
- Create `DockCatApp/DockCatTests/AgentEventPresenterTests.swift`
- Create `DockCatApp/DockCatTests/AgentEventQueueTests.swift`
- Create `DockCatApp/DockCatTests/AgentHTTPRequestParserTests.swift`
- Modify `docs/superpowers/specs/2026-07-04-agent-http-pet-status-design.md`
  - Keep it aligned with `session` and queue behavior.

The project uses file-system synchronized groups, so new files under `DockCatApp/DockCat` and `DockCatApp/DockCatTests` are picked up by their targets without adding manual build-file IDs.

## Task 1: Agent Event Model

**Files:**
- Create: `DockCatApp/DockCat/Core/Agent/AgentEvent.swift`
- Create: `DockCatApp/DockCatTests/AgentEventTests.swift`

- [ ] **Step 1: Write failing tests for JSON decoding and validation**

Create `DockCatApp/DockCatTests/AgentEventTests.swift`:

```swift
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
        let data = """
        {"agent":" codex ","session":" task ","status":"info","message":"  \(longMessage)  ","hint":"  done  "}
        """.data(using: .utf8)!

        let event = try AgentEvent.decode(from: data)

        XCTAssertEqual(event.agent, "codex")
        XCTAssertEqual(event.session, "task")
        XCTAssertEqual(event.message?.count, AgentEvent.maxTextLength)
        XCTAssertEqual(event.hint, "done")
    }
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat -configuration Debug -destination 'platform=macOS' test
```

Expected: build fails because `AgentEvent` and `AgentStatus` do not exist.

- [ ] **Step 3: Add the minimal event model**

Create `DockCatApp/DockCat/Core/Agent/AgentEvent.swift`:

```swift
import Foundation

enum AgentStatus: String, Codable, Equatable {
    case working
    case success
    case failure
    case waiting
    case info
}

struct AgentEvent: Equatable {
    static let maxTextLength = 160

    enum ValidationError: Error, Equatable {
        case invalidJSON
        case missingAgent
        case missingStatus
        case unknownStatus(String)
    }

    let agent: String
    let session: String?
    let status: AgentStatus
    let message: String?
    let hint: String?

    private struct Payload: Decodable {
        let agent: String?
        let session: String?
        let status: String?
        let message: String?
        let hint: String?
    }

    static func decode(from data: Data) throws -> AgentEvent {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw ValidationError.invalidJSON
        }

        guard let agent = normalizedRequired(payload.agent) else {
            throw ValidationError.missingAgent
        }
        guard let statusValue = normalizedRequired(payload.status) else {
            throw ValidationError.missingStatus
        }
        guard let status = AgentStatus(rawValue: statusValue) else {
            throw ValidationError.unknownStatus(statusValue)
        }

        return AgentEvent(
            agent: agent,
            session: normalizedOptional(payload.session),
            status: status,
            message: normalizedOptional(payload.message),
            hint: normalizedOptional(payload.hint)
        )
    }

    private static func normalizedRequired(_ value: String?) -> String? {
        normalizedOptional(value)
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxTextLength))
    }
}
```

- [ ] **Step 4: Run tests and verify GREEN**

Run the same `xcodebuild ... test` command.

Expected: `AgentEventTests` pass.

- [ ] **Step 5: Commit**

```bash
git add DockCatApp/DockCat/Core/Agent/AgentEvent.swift DockCatApp/DockCatTests/AgentEventTests.swift
git commit -m "Add agent event model"
```

## Task 2: Status Presentation Mapping

**Files:**
- Create: `DockCatApp/DockCat/Core/Agent/AgentEventPresenter.swift`
- Create: `DockCatApp/DockCatTests/AgentEventPresenterTests.swift`
- Modify: `DockCatApp/DockCat/Support/AppStrings.swift`

- [ ] **Step 1: Write failing tests for status-to-action mapping**

Create `DockCatApp/DockCatTests/AgentEventPresenterTests.swift`:

```swift
import XCTest
@testable import DockCat

final class AgentEventPresenterTests: XCTestCase {
    func testMapsSelectedActions() {
        XCTAssertEqual(presentation(.working).action, .smallPatrol)
        XCTAssertEqual(presentation(.success).action, .comfortableFinish)
        XCTAssertEqual(presentation(.failure).action, .seriousAlert)
        XCTAssertEqual(presentation(.waiting).action, .waitForUser)
        XCTAssertEqual(presentation(.info).action, .turnToNotice)
    }

    func testPrioritiesMatchInterruptionRules() {
        XCTAssertEqual(presentation(.failure).priority, .high)
        XCTAssertEqual(presentation(.waiting).priority, .high)
        XCTAssertEqual(presentation(.working).priority, .low)
        XCTAssertEqual(presentation(.success).priority, .low)
        XCTAssertEqual(presentation(.info).priority, .low)
    }

    func testUsesHintBeforeFallbackMessage() {
        let event = AgentEvent(agent: "codex", session: "task", status: .info, message: "raw", hint: "pet text")

        let result = AgentEventPresenter.presentation(for: event, strings: AppStrings(language: .english))

        XCTAssertEqual(result.message, "pet text")
    }

    func testFallbackMessageUsesAgentAndMessage() {
        let event = AgentEvent(agent: "codex", session: "task", status: .failure, message: "Tests failed", hint: nil)

        let result = AgentEventPresenter.presentation(for: event, strings: AppStrings(language: .english))

        XCTAssertEqual(result.message, "codex needs attention: Tests failed")
    }

    private func presentation(_ status: AgentStatus) -> AgentPresentation {
        let event = AgentEvent(agent: "codex", session: "task", status: status, message: "message", hint: nil)
        return AgentEventPresenter.presentation(for: event, strings: AppStrings(language: .english))
    }
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat -configuration Debug -destination 'platform=macOS' test
```

Expected: build fails because `AgentEventPresenter`, `AgentPresentation`, `AgentPetAction`, and `AgentEventPriority` do not exist.

- [ ] **Step 3: Add presentation mapping and localized fallbacks**

Create `DockCatApp/DockCat/Core/Agent/AgentEventPresenter.swift`:

```swift
import Foundation

enum AgentPetAction: Equatable {
    case smallPatrol
    case comfortableFinish
    case seriousAlert
    case waitForUser
    case turnToNotice
}

enum AgentEventPriority: Equatable {
    case low
    case high
}

struct AgentPresentation: Equatable {
    let event: AgentEvent
    let action: AgentPetAction
    let priority: AgentEventPriority
    let message: String
    let requiresAcknowledgement: Bool

    var coalescingKey: String {
        "\(event.agent)::\(event.session ?? "")"
    }
}

enum AgentEventPresenter {
    static func presentation(for event: AgentEvent, strings: AppStrings) -> AgentPresentation {
        AgentPresentation(
            event: event,
            action: action(for: event.status),
            priority: priority(for: event.status),
            message: event.hint ?? strings.agentEventFallback(agent: event.agent, status: event.status, message: event.message),
            requiresAcknowledgement: event.status == .waiting || event.status == .failure
        )
    }

    private static func action(for status: AgentStatus) -> AgentPetAction {
        switch status {
        case .working: return .smallPatrol
        case .success: return .comfortableFinish
        case .failure: return .seriousAlert
        case .waiting: return .waitForUser
        case .info: return .turnToNotice
        }
    }

    private static func priority(for status: AgentStatus) -> AgentEventPriority {
        switch status {
        case .failure, .waiting: return .high
        case .working, .success, .info: return .low
        }
    }
}
```

Add this method near the other message helpers in `DockCatApp/DockCat/Support/AppStrings.swift`:

```swift
    func agentEventFallback(agent: String, status: AgentStatus, message: String?) -> String {
        let suffix = message.map { ": \($0)" } ?? ""
        switch (language, status) {
        case (.chinese, .working): return "\(agent) 正在处理\(suffix)"
        case (.chinese, .success): return "\(agent) 完成了\(suffix)"
        case (.chinese, .failure): return "\(agent) 需要注意\(suffix)"
        case (.chinese, .waiting): return "\(agent) 正在等待\(suffix)"
        case (.chinese, .info): return "\(agent)\(suffix)"
        case (.english, .working): return "\(agent) is working\(suffix)"
        case (.english, .success): return "\(agent) finished\(suffix)"
        case (.english, .failure): return "\(agent) needs attention\(suffix)"
        case (.english, .waiting): return "\(agent) is waiting\(suffix)"
        case (.english, .info): return "\(agent)\(suffix)"
        }
    }
```

- [ ] **Step 4: Run tests and verify GREEN**

Run the same `xcodebuild ... test` command.

Expected: `AgentEventPresenterTests` and `AgentEventTests` pass.

- [ ] **Step 5: Commit**

```bash
git add DockCatApp/DockCat/Core/Agent/AgentEventPresenter.swift DockCatApp/DockCat/Support/AppStrings.swift DockCatApp/DockCatTests/AgentEventPresenterTests.swift
git commit -m "Map agent events to pet presentations"
```

## Task 3: Pending Queue And Multi-Agent Coalescing

**Files:**
- Create: `DockCatApp/DockCat/Core/Agent/AgentEventQueue.swift`
- Create: `DockCatApp/DockCatTests/AgentEventQueueTests.swift`

- [ ] **Step 1: Write failing tests for queue priority and coalescing**

Create `DockCatApp/DockCatTests/AgentEventQueueTests.swift`:

```swift
import XCTest
@testable import DockCat

final class AgentEventQueueTests: XCTestCase {
    func testCoalescesLowPriorityEventsForSameAgentAndSession() {
        var queue = AgentEventQueue(maxCount: 5)

        queue.enqueue(presentation(agent: "codex", session: "task", status: .working, message: "one"))
        queue.enqueue(presentation(agent: "codex", session: "task", status: .info, message: "two"))

        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertEqual(queue.popNext()?.message, "codex: two")
    }

    func testKeepsDifferentAgentsAndSessionsSeparate() {
        var queue = AgentEventQueue(maxCount: 5)

        queue.enqueue(presentation(agent: "codex", session: "task", status: .working, message: "one"))
        queue.enqueue(presentation(agent: "claude", session: "task", status: .working, message: "two"))
        queue.enqueue(presentation(agent: "codex", session: "other", status: .working, message: "three"))

        XCTAssertEqual(queue.pendingCount, 3)
    }

    func testPopsHighPriorityBeforeLowPriority() {
        var queue = AgentEventQueue(maxCount: 5)

        queue.enqueue(presentation(agent: "codex", session: "task", status: .working, message: "low"))
        queue.enqueue(presentation(agent: "claude", session: "task", status: .failure, message: "high"))

        XCTAssertEqual(queue.popNext()?.event.status, .failure)
    }

    func testDropsOldestLowPriorityWhenFull() {
        var queue = AgentEventQueue(maxCount: 2)

        queue.enqueue(presentation(agent: "a", session: "1", status: .working, message: "one"))
        queue.enqueue(presentation(agent: "b", session: "1", status: .waiting, message: "two"))
        queue.enqueue(presentation(agent: "c", session: "1", status: .failure, message: "three"))

        XCTAssertEqual(queue.pendingCount, 2)
        XCTAssertEqual(queue.popNext()?.event.agent, "b")
        XCTAssertEqual(queue.popNext()?.event.agent, "c")
    }

    private func presentation(agent: String, session: String, status: AgentStatus, message: String) -> AgentPresentation {
        let event = AgentEvent(agent: agent, session: session, status: status, message: message, hint: nil)
        return AgentEventPresenter.presentation(for: event, strings: AppStrings(language: .english))
    }
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat -configuration Debug -destination 'platform=macOS' test
```

Expected: build fails because `AgentEventQueue` does not exist.

- [ ] **Step 3: Add the queue**

Create `DockCatApp/DockCat/Core/Agent/AgentEventQueue.swift`:

```swift
import Foundation

struct AgentEventQueue {
    private(set) var pending: [AgentPresentation] = []
    let maxCount: Int

    var pendingCount: Int {
        pending.count
    }

    init(maxCount: Int = 5) {
        self.maxCount = max(1, maxCount)
    }

    mutating func enqueue(_ presentation: AgentPresentation) {
        if presentation.priority == .low,
           let index = pending.firstIndex(where: { $0.priority == .low && $0.coalescingKey == presentation.coalescingKey }) {
            pending[index] = presentation
            return
        }

        pending.append(presentation)
        trimToMaxCount()
    }

    mutating func popNext() -> AgentPresentation? {
        if let highIndex = pending.firstIndex(where: { $0.priority == .high }) {
            return pending.remove(at: highIndex)
        }
        guard !pending.isEmpty else { return nil }
        return pending.removeFirst()
    }

    private mutating func trimToMaxCount() {
        while pending.count > maxCount {
            if let lowIndex = pending.firstIndex(where: { $0.priority == .low }) {
                pending.remove(at: lowIndex)
            } else {
                pending.removeFirst()
            }
        }
    }
}
```

- [ ] **Step 4: Run tests and verify GREEN**

Run the same `xcodebuild ... test` command.

Expected: all agent model, presenter, and queue tests pass.

- [ ] **Step 5: Commit**

```bash
git add DockCatApp/DockCat/Core/Agent/AgentEventQueue.swift DockCatApp/DockCatTests/AgentEventQueueTests.swift
git commit -m "Add agent event queue"
```

## Task 4: Minimal HTTP Parser

**Files:**
- Create: `DockCatApp/DockCat/Core/Agent/AgentHTTPRequestParser.swift`
- Create: `DockCatApp/DockCatTests/AgentHTTPRequestParserTests.swift`

- [ ] **Step 1: Write failing parser tests**

Create `DockCatApp/DockCatTests/AgentHTTPRequestParserTests.swift`:

```swift
import XCTest
@testable import DockCat

final class AgentHTTPRequestParserTests: XCTestCase {
    func testParsesValidPostEventRequest() throws {
        let body = #"{"agent":"codex","status":"info","message":"hello"}"#
        let request = """
        POST /agent-events HTTP/1.1\r
        Host: 127.0.0.1:8765\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        \r
        \(body)
        """.data(using: .utf8)!

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
        let request = """
        POST /agent-events HTTP/1.1\r
        Content-Length: \(body.utf8.count)\r
        \r
        \(body)
        """.data(using: .utf8)!

        XCTAssertEqual(AgentHTTPRequestParser.response(for: request).statusCode, 400)
    }
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat -configuration Debug -destination 'platform=macOS' test
```

Expected: build fails because `AgentHTTPRequestParser` does not exist.

- [ ] **Step 3: Add parser and HTTP response type**

Create `DockCatApp/DockCat/Core/Agent/AgentHTTPRequestParser.swift`:

```swift
import Foundation

struct AgentHTTPRequest {
    let agentEvent: AgentEvent
}

struct AgentHTTPResponse: Equatable {
    let statusCode: Int

    var data: Data {
        let reason: String
        switch statusCode {
        case 204: reason = "No Content"
        case 400: reason = "Bad Request"
        case 404: reason = "Not Found"
        case 405: reason = "Method Not Allowed"
        default: reason = "Internal Server Error"
        }
        return "HTTP/1.1 \(statusCode) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".data(using: .utf8)!
    }
}

enum AgentHTTPRequestParser {
    static let maxBodyBytes = 8 * 1024

    enum ParseError: Error {
        case badRequest
        case notFound
        case methodNotAllowed
    }

    static func parse(_ data: Data) throws -> AgentHTTPRequest {
        let request = String(decoding: data, as: UTF8.self)
        guard let headerRange = request.range(of: "\r\n\r\n") else {
            throw ParseError.badRequest
        }

        let header = String(request[..<headerRange.lowerBound])
        let lines = header.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { throw ParseError.badRequest }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { throw ParseError.badRequest }
        guard parts[0] == "POST" else { throw ParseError.methodNotAllowed }
        guard parts[1] == "/agent-events" else { throw ParseError.notFound }

        let contentLength = lines.dropFirst().compactMap { line -> Int? in
            let pieces = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard pieces.count == 2, pieces[0].lowercased() == "content-length" else { return nil }
            return Int(pieces[1].trimmingCharacters(in: .whitespacesAndNewlines))
        }.first ?? 0

        guard contentLength <= maxBodyBytes else { throw ParseError.badRequest }

        let bodyStart = headerRange.upperBound
        let body = String(request[bodyStart...])
        guard body.utf8.count >= contentLength else { throw ParseError.badRequest }
        let bodyData = Data(body.utf8.prefix(contentLength))
        return AgentHTTPRequest(agentEvent: try AgentEvent.decode(from: bodyData))
    }

    static func response(for data: Data) -> AgentHTTPResponse {
        do {
            _ = try parse(data)
            return AgentHTTPResponse(statusCode: 204)
        } catch ParseError.notFound {
            return AgentHTTPResponse(statusCode: 404)
        } catch ParseError.methodNotAllowed {
            return AgentHTTPResponse(statusCode: 405)
        } catch {
            return AgentHTTPResponse(statusCode: 400)
        }
    }
}
```

- [ ] **Step 4: Run tests and verify GREEN**

Run the same `xcodebuild ... test` command.

Expected: parser tests pass along with previous tests.

- [ ] **Step 5: Commit**

```bash
git add DockCatApp/DockCat/Core/Agent/AgentHTTPRequestParser.swift DockCatApp/DockCatTests/AgentHTTPRequestParserTests.swift
git commit -m "Parse agent HTTP events"
```

## Task 5: Loopback HTTP Server

**Files:**
- Create: `DockCatApp/DockCat/Core/Agent/AgentHTTPServer.swift`
- Modify: `DockCatApp/DockCat/App/DockCatApplication.swift`

- [ ] **Step 1: Add a compile check for server start/stop API**

Extend `DockCatApp/DockCatTests/AgentHTTPRequestParserTests.swift` with this small API test:

```swift
    func testServerCanBeConstructedWithoutStarting() {
        let server = AgentHTTPServer(port: 8765) { _ in }
        XCTAssertFalse(server.isRunning)
    }
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat -configuration Debug -destination 'platform=macOS' test
```

Expected: build fails because `AgentHTTPServer` does not exist.

- [ ] **Step 3: Add the server wrapper**

Create `DockCatApp/DockCat/Core/Agent/AgentHTTPServer.swift`:

```swift
import Foundation
import Network

final class AgentHTTPServer {
    private let port: UInt16
    private let onEvent: (AgentEvent) -> Void
    private let queue = DispatchQueue(label: "DockCat.AgentHTTPServer")
    private var listener: NWListener?

    private(set) var isRunning = false

    init(port: UInt16 = 8765, onEvent: @escaping (AgentEvent) -> Void) {
        self.port = port
        self.onEvent = onEvent
    }

    func start() {
        guard listener == nil else { return }
        guard let nwPort = NWEndpoint.Port(rawValue: port),
              let loopback = IPv4Address("127.0.0.1")
        else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(loopback), port: nwPort)
            let listener = try NWListener(using: parameters, on: nwPort)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .ready = state {
                    self?.isRunning = true
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            DockCatLog.app.error("Failed to start agent HTTP server: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: AgentHTTPRequestParser.maxBodyBytes + 2048) { [weak self] data, _, _, _ in
            guard let self, let data else {
                connection.cancel()
                return
            }
            let response = AgentHTTPRequestParser.response(for: data)
            if response.statusCode == 204, let request = try? AgentHTTPRequestParser.parse(data) {
                self.onEvent(request.agentEvent)
            }
            connection.send(content: response.data, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}
```

- [ ] **Step 4: Run tests and verify GREEN**

Run the same `xcodebuild ... test` command.

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add DockCatApp/DockCat/Core/Agent/AgentHTTPServer.swift DockCatApp/DockCatTests/AgentHTTPRequestParserTests.swift
git commit -m "Add loopback agent HTTP server"
```

## Task 6: DockCat Application Integration

**Files:**
- Modify: `DockCatApp/DockCat/App/DockCatApplication.swift`

- [ ] **Step 1: Add integration state**

In `DockCatApplication`, add properties near the other private state:

```swift
    private var agentHTTPServer: AgentHTTPServer?
    private var agentEventQueue = AgentEventQueue()
    private var activeAgentPresentation: AgentPresentation?
    private var agentPresentationTimer: Timer?
    private var agentPatrolTimer: Timer?
```

- [ ] **Step 2: Start and stop the server**

In `applicationDidFinishLaunching`, after menus/dock observer setup, add:

```swift
        configureAgentHTTPServer()
```

In `applicationWillTerminate`, add:

```swift
        agentHTTPServer?.stop()
        agentPresentationTimer?.invalidate()
        agentPatrolTimer?.invalidate()
```

Add:

```swift
    private func configureAgentHTTPServer() {
        let server = AgentHTTPServer { [weak self] event in
            Task { @MainActor in
                self?.receiveAgentEvent(event)
            }
        }
        agentHTTPServer = server
        server.start()
    }
```

- [ ] **Step 3: Add receiving and queueing**

Add:

```swift
    private func receiveAgentEvent(_ event: AgentEvent) {
        let presentation = AgentEventPresenter.presentation(for: event, strings: strings)
        if canShowAgentPresentation(presentation) {
            showAgentPresentation(presentation)
        } else {
            agentEventQueue.enqueue(presentation)
        }
    }

    private func canShowAgentPresentation(_ presentation: AgentPresentation) -> Bool {
        if isProtectedAgentInteraction {
            return false
        }
        if activeAgentPresentation == nil {
            return stateMachine.state.isLongDuration
        }
        return presentation.priority == .high
    }

    private var isProtectedAgentInteraction: Bool {
        if stateMachine.state.isOuting {
            return true
        }
        if case .dialogue = stateMachine.state, activeAgentPresentation == nil {
            return true
        }
        return false
    }
```

- [ ] **Step 4: Add presentation helpers**

Add these helpers in `DockCatApplication`:

```swift
    private func showAgentPresentation(_ presentation: AgentPresentation) {
        activeAgentPresentation = presentation
        agentPresentationTimer?.invalidate()
        agentPatrolTimer?.invalidate()
        stopWalk()

        switch presentation.action {
        case .smallPatrol:
            showAgentPatrol(presentation)
        case .comfortableFinish:
            showAgentDialogue(presentation, autoDismissAfter: 3.0, resumeWhenIdle: false) { [weak self] in
                self?.showAgentRestingFinish()
            }
        case .seriousAlert:
            showAgentDialogue(presentation, autoDismissAfter: 8.0)
        case .waitForUser:
            showAgentDialogue(presentation, autoDismissAfter: nil)
        case .turnToNotice:
            showAgentDialogue(presentation, autoDismissAfter: 3.0)
        }
    }

    private func showAgentPatrol(_ presentation: AgentPresentation) {
        let animation = renderer.animationFrames(\.walk)
        let sourceSize = stableWalkSourceSize()
        walkDirection = Bool.random() ? 1 : -1
        catWindow.setImage(animation.frames.first ?? renderer.firstImage(for: .dialogue), mirrored: walkDirection < 0, sourceSize: sourceSize)
        let start = clampedCatPoint(stateMachine.position)
        catWindow.show(at: start)
        walkAnimator.start(animation: animation) { [weak self, animation] frameIndex in
            Task { @MainActor in
                guard let self else { return }
                self.catWindow.setImage(animation.frames[frameIndex], mirrored: self.walkDirection < 0, sourceSize: sourceSize)
            }
        }
        agentPatrolTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.showAgentDialogue(presentation, autoDismissAfter: 3.0)
            }
        }
    }

    private func showAgentDialogue(
        _ presentation: AgentPresentation,
        autoDismissAfter interval: TimeInterval?,
        resumeWhenIdle: Bool = true,
        onDismiss: (() -> Void)? = nil
    ) {
        stopWalk()
        let pose = renderer.randomPose(for: .dialogue)
        catWindow.setImage(pose.image, mirrored: pose.mirrored)
        catWindow.show(at: clampedCatPoint(stateMachine.position))
        catWindow.showBubble(
            message: presentation.message,
            primaryTitle: strings.ok,
            onPrimary: { [weak self] in
                self?.finishAgentPresentation(onDismiss: onDismiss, resumeWhenIdle: resumeWhenIdle)
            }
        )
        if let interval {
            agentPresentationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.finishAgentPresentation(onDismiss: onDismiss, resumeWhenIdle: resumeWhenIdle)
                }
            }
        }
    }

    private func showAgentRestingFinish() {
        let pose = renderer.randomPose(for: .resting, fallback: .dialogue)
        catWindow.setImage(pose.image, mirrored: pose.mirrored)
        catWindow.show(at: clampedCatPoint(stateMachine.position))
    }

    private func finishAgentPresentation(onDismiss: (() -> Void)? = nil, resumeWhenIdle: Bool = true) {
        agentPresentationTimer?.invalidate()
        agentPatrolTimer?.invalidate()
        agentPresentationTimer = nil
        agentPatrolTimer = nil
        catWindow.hideBubble()
        onDismiss?()
        activeAgentPresentation = nil
        showNextQueuedAgentPresentationIfPossible(resumeWhenIdle: resumeWhenIdle)
    }

    private func showNextQueuedAgentPresentationIfPossible(resumeWhenIdle: Bool = true) {
        guard !isProtectedAgentInteraction, activeAgentPresentation == nil else { return }
        guard let next = agentEventQueue.popNext() else {
            if resumeWhenIdle {
                applyState(stateMachine.state)
            }
            return
        }
        showAgentPresentation(next)
    }
```

- [ ] **Step 5: Resume queued events after protected flows**

At the end of `finishOutingReturn`, after `saveUserDataBackup()`, add:

```swift
        showNextQueuedAgentPresentationIfPossible()
```

In the `askOutingDuration` cancel closure after `stateMachine.enterRandomLongDurationState()`, add:

```swift
                self.showNextQueuedAgentPresentationIfPossible()
```

In `startConfirmedOuting`, do not show queued events because the cat is leaving. They will remain queued until the outing return finishes.

- [ ] **Step 6: Build**

Run:

```bash
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat -configuration Debug -derivedDataPath DockCatApp/DerivedDataDebug build
```

Expected: build succeeds.

- [ ] **Step 7: Run tests**

Run:

```bash
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat -configuration Debug -destination 'platform=macOS' test
```

Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add DockCatApp/DockCat/App/DockCatApplication.swift
git commit -m "Show agent events in DockCat"
```

## Task 7: Manual Localhost Verification

**Files:**
- No source file changes expected.

- [ ] **Step 1: Launch the debug app**

Run:

```bash
open DockCatApp/DerivedDataDebug/Build/Products/Debug/DockCat.app
```

Expected: DockCat launches normally. If another DockCat instance is running, quit it first.

- [ ] **Step 2: Send a working event**

Run:

```bash
curl -i -X POST http://127.0.0.1:8765/agent-events \
  -H 'Content-Type: application/json' \
  -d '{"agent":"codex","session":"task-1","status":"working","message":"Updating tests"}'
```

Expected: HTTP `204 No Content`; DockCat briefly patrols, then shows a working dialogue bubble.

- [ ] **Step 3: Send a success event**

Run:

```bash
curl -i -X POST http://127.0.0.1:8765/agent-events \
  -H 'Content-Type: application/json' \
  -d '{"agent":"codex","session":"task-1","status":"success","message":"Tests passed"}'
```

Expected: HTTP `204 No Content`; DockCat shows success, then settles into a resting pose.

- [ ] **Step 4: Send a waiting event**

Run:

```bash
curl -i -X POST http://127.0.0.1:8765/agent-events \
  -H 'Content-Type: application/json' \
  -d '{"agent":"claude","session":"review-7","status":"waiting","message":"Needs approval"}'
```

Expected: HTTP `204 No Content`; DockCat faces the user and keeps the bubble until OK is clicked.

- [ ] **Step 5: Verify rejection paths**

Run:

```bash
curl -i -X POST http://127.0.0.1:8765/agent-events \
  -H 'Content-Type: application/json' \
  -d '{"agent":"codex","status":"unknown"}'
```

Expected: HTTP `400 Bad Request`; DockCat does not show a bubble.

- [ ] **Step 6: Commit verification notes only if docs changed**

If no docs changed, do not commit. If a README example was added during verification, commit it:

```bash
git add README.md README.en.md
git commit -m "Document agent event curl examples"
```

## Task 8: Final Verification

**Files:**
- No source file changes expected.

- [ ] **Step 1: Run full test suite**

Run:

```bash
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat -configuration Debug -destination 'platform=macOS' test
```

Expected: test action exits with code 0.

- [ ] **Step 2: Run full debug build**

Run:

```bash
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat -configuration Debug -derivedDataPath DockCatApp/DerivedDataDebug build
```

Expected: build exits with code 0.

- [ ] **Step 3: Inspect git status**

Run:

```bash
git status --short
```

Expected: only intended source, test, spec, and plan files are modified or committed. Existing unrelated asset changes under `DockCatApp/DockCat/Resources/` and `xiaohou/` must not be reverted or included unless the user explicitly asks.

## Implementation Notes

- Keep the HTTP layer one-way. The agent receives only HTTP status codes.
- Keep the listener default-on, loopback-only, and dependency-free.
- Do not add settings UI in this implementation.
- Do not persist agent history.
- Do not let `AgentHTTPServer` import AppKit or call `CatWindowController`.
- If the one-shot `NWConnection.receive` proves flaky with split TCP packets during manual testing, add a tiny per-connection buffer inside `AgentHTTPServer` and keep `AgentHTTPRequestParser` unchanged.
