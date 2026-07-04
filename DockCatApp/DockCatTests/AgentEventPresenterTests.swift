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

    func testAcknowledgementMatchesInterruptionRules() {
        XCTAssertTrue(presentation(.failure).requiresAcknowledgement)
        XCTAssertTrue(presentation(.waiting).requiresAcknowledgement)
        XCTAssertFalse(presentation(.working).requiresAcknowledgement)
        XCTAssertFalse(presentation(.success).requiresAcknowledgement)
        XCTAssertFalse(presentation(.info).requiresAcknowledgement)
    }

    func testCoalescingKeyUsesAgentAndSession() {
        let eventWithSession = AgentEvent(agent: "codex", session: "task", status: .info, message: nil, hint: nil)
        let eventWithoutSession = AgentEvent(agent: "codex", session: nil, status: .info, message: nil, hint: nil)

        let resultWithSession = AgentEventPresenter.presentation(for: eventWithSession, strings: AppStrings(language: .english))
        let resultWithoutSession = AgentEventPresenter.presentation(for: eventWithoutSession, strings: AppStrings(language: .english))

        XCTAssertEqual(resultWithSession.coalescingKey, "codex::task")
        XCTAssertEqual(resultWithoutSession.coalescingKey, "codex::")
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

    func testInfoFallbackWithoutMessageIncludesStatusPhrase() {
        let event = AgentEvent(agent: "codex", session: "task", status: .info, message: nil, hint: nil)

        let result = AgentEventPresenter.presentation(for: event, strings: AppStrings(language: .english))

        XCTAssertEqual(result.message, "codex has an update")
    }

    private func presentation(_ status: AgentStatus) -> AgentPresentation {
        let event = AgentEvent(agent: "codex", session: "task", status: status, message: "message", hint: nil)
        return AgentEventPresenter.presentation(for: event, strings: AppStrings(language: .english))
    }
}
