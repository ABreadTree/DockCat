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
            pending.remove(at: index)
            pending.append(presentation)
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

    func peekNext() -> AgentPresentation? {
        if let highPriority = pending.first(where: { $0.priority == .high }) {
            return highPriority
        }
        return pending.first
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
