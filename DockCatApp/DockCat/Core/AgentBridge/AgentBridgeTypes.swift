import Foundation

enum AgentBridgeAgentID: String, Codable, CaseIterable, Identifiable {
    case codex
    case claudeCode = "claude-code"
    case hermes
    case openClaw = "openclaw"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        case .hermes: "Hermes"
        case .openClaw: "OpenClaw"
        }
    }

    var settingsKeyPath: WritableKeyPath<AgentBridgeSettings, AgentBridgeAgentSetting> {
        switch self {
        case .codex: \.codex
        case .claudeCode: \.claudeCode
        case .hermes: \.hermes
        case .openClaw: \.openClaw
        }
    }
}

enum AgentBridgeStatus: String, Equatable {
    case notInstalled
    case detected
    case enabled
    case migrated
    case failed
}

struct AgentBridgeAgentSnapshot: Identifiable, Equatable {
    var agent: AgentBridgeAgentID
    var status: AgentBridgeStatus
    var detail: String
    var configPath: String?

    var id: AgentBridgeAgentID { agent }
    var isAvailable: Bool { status != .notInstalled && status != .migrated }
    var isEnabled: Bool { status == .enabled }
}

struct AgentBridgeSnapshot: Equatable {
    var serverEnabled: Bool
    var serverPort: Int
    var serverRunning: Bool
    var helperPath: String
    var agents: [AgentBridgeAgentSnapshot]

    static let empty = AgentBridgeSnapshot(
        serverEnabled: true,
        serverPort: 8765,
        serverRunning: false,
        helperPath: "",
        agents: []
    )
}

struct AgentBridgeActionResult: Equatable {
    var succeeded: Bool
    var message: String

    static func success(_ message: String) -> AgentBridgeActionResult {
        AgentBridgeActionResult(succeeded: true, message: message)
    }

    static func failure(_ message: String) -> AgentBridgeActionResult {
        AgentBridgeActionResult(succeeded: false, message: message)
    }
}
