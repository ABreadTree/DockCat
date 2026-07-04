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
