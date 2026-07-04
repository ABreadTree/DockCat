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
