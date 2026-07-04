import XCTest
@testable import DockCat

final class AgentEventQueueTests: XCTestCase {
    func testCoalescesLowPriorityEventsForSameAgentAndSession() {
        var queue = AgentEventQueue(maxCount: 5)

        queue.enqueue(presentation(agent: "codex", session: "task", status: .working, message: "one"))
        queue.enqueue(presentation(agent: "codex", session: "task", status: .info, message: "two"))

        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertEqual(queue.popNext()?.message, "codex has an update: two")
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

    func testPeekNextMatchesPriorityWithoutRemoving() {
        var queue = AgentEventQueue(maxCount: 5)

        queue.enqueue(presentation(agent: "codex", session: "task", status: .working, message: "low"))
        queue.enqueue(presentation(agent: "claude", session: "task", status: .failure, message: "high"))

        XCTAssertEqual(queue.peekNext()?.event.status, .failure)
        XCTAssertEqual(queue.pendingCount, 2)
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

    func testCoalescingRefreshesRecencyBeforeTrimming() {
        var queue = AgentEventQueue(maxCount: 2)

        queue.enqueue(presentation(agent: "a", session: "1", status: .working, message: "one"))
        queue.enqueue(presentation(agent: "b", session: "1", status: .working, message: "two"))
        queue.enqueue(presentation(agent: "a", session: "1", status: .info, message: "updated"))
        queue.enqueue(presentation(agent: "c", session: "1", status: .failure, message: "three"))

        XCTAssertEqual(queue.pendingCount, 2)
        XCTAssertEqual(queue.popNext()?.event.agent, "c")
        XCTAssertEqual(queue.popNext()?.event.agent, "a")
    }

    func testSameKeyHighPriorityEventsDoNotCoalesce() {
        var queue = AgentEventQueue(maxCount: 5)

        queue.enqueue(presentation(agent: "codex", session: "task", status: .waiting, message: "one"))
        queue.enqueue(presentation(agent: "codex", session: "task", status: .failure, message: "two"))

        XCTAssertEqual(queue.pendingCount, 2)
        XCTAssertEqual(queue.popNext()?.event.status, .waiting)
        XCTAssertEqual(queue.popNext()?.event.status, .failure)
    }

    func testAllHighOverflowDropsOldestHighPriorityEvent() {
        var queue = AgentEventQueue(maxCount: 2)

        queue.enqueue(presentation(agent: "a", session: "1", status: .waiting, message: "one"))
        queue.enqueue(presentation(agent: "b", session: "1", status: .failure, message: "two"))
        queue.enqueue(presentation(agent: "c", session: "1", status: .failure, message: "three"))

        XCTAssertEqual(queue.pendingCount, 2)
        XCTAssertEqual(queue.popNext()?.event.agent, "b")
        XCTAssertEqual(queue.popNext()?.event.agent, "c")
    }

    func testMaxCountClampsToOne() {
        var queue = AgentEventQueue(maxCount: 0)

        queue.enqueue(presentation(agent: "a", session: "1", status: .waiting, message: "one"))
        queue.enqueue(presentation(agent: "b", session: "1", status: .failure, message: "two"))

        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertEqual(queue.popNext()?.event.agent, "b")
    }

    private func presentation(agent: String, session: String, status: AgentStatus, message: String) -> AgentPresentation {
        let event = AgentEvent(agent: agent, session: session, status: status, message: message, hint: nil)
        return AgentEventPresenter.presentation(for: event, strings: AppStrings(language: .english))
    }
}
