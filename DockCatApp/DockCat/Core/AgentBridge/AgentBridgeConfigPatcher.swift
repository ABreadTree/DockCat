import Foundation

enum AgentBridgeConfigPatchError: Error, Equatable {
    case invalidJSON
}

struct AgentBridgeCodexPatch: Equatable {
    var text: String
    var previousNotifyLine: String?
}

enum AgentBridgeConfigPatcher {
    static func patchCodexTOML(_ text: String, helperPath: String, port: Int) -> AgentBridgeCodexPatch {
        var lines = splitLines(text)
        let newline = text.hasSuffix("\n")
        let notifyIndex = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("notify = [") }
        let previousLine = notifyIndex.map { lines[$0] }
        let previousArguments = previousLine.flatMap(parseTomlStringArray) ?? []
        let chainArguments = previousArguments.contains(AgentBridgeHelper.managedMarker) ? [] : previousArguments
        let arguments = AgentBridgeHelper.commandArguments(
            helperPath: helperPath,
            agent: .codex,
            port: port,
            session: "codex",
            chainedCommand: chainArguments
        )
        let replacement = "\(notifyIndex.map { leadingWhitespace(lines[$0]) } ?? "")notify = \(tomlStringArray(arguments))"

        if let notifyIndex {
            lines[notifyIndex] = replacement
        } else {
            lines.insert(replacement, at: 0)
        }

        return AgentBridgeCodexPatch(
            text: joinLines(lines, trailingNewline: newline),
            previousNotifyLine: previousArguments.contains(AgentBridgeHelper.managedMarker) ? nil : previousLine
        )
    }

    static func restoreCodexTOML(_ text: String, previousNotifyLine: String?) -> String {
        var lines = splitLines(text)
        let newline = text.hasSuffix("\n")
        guard let notifyIndex = lines.firstIndex(where: { line in
            line.trimmingCharacters(in: .whitespaces).hasPrefix("notify = [") &&
                line.contains(AgentBridgeHelper.managedMarker)
        }) else {
            return text
        }

        if let previousNotifyLine {
            lines[notifyIndex] = previousNotifyLine
        } else if let chainArguments = codexChainArguments(from: lines[notifyIndex]), !chainArguments.isEmpty {
            lines[notifyIndex] = "\(leadingWhitespace(lines[notifyIndex]))notify = \(tomlStringArray(chainArguments))"
        } else {
            lines.remove(at: notifyIndex)
        }
        return joinLines(lines, trailingNewline: newline)
    }

    static func patchClaudeSettingsJSON(_ data: Data, helperPath: String, port: Int) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentBridgeConfigPatchError.invalidJSON
        }

        let command = managedCommandString(helperPath: helperPath, agent: .claudeCode, port: port)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var stopHooks = hooks["Stop"] as? [Any] ?? []
        if !stopHooks.contains(where: { containsManagedCommand($0, helperPath: helperPath) }) {
            stopHooks.append([
                "type": "command",
                "command": command
            ])
        }
        hooks["Stop"] = stopHooks
        root["hooks"] = hooks

        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    static func removeClaudeSettingsJSON(_ data: Data, helperPath: String) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentBridgeConfigPatchError.invalidJSON
        }
        guard var hooks = root["hooks"] as? [String: Any] else {
            return data
        }

        for (event, value) in hooks {
            guard let entries = value as? [Any] else { continue }
            hooks[event] = entries.filter { !containsManagedCommand($0, helperPath: helperPath) }
        }
        root["hooks"] = hooks
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    static func patchHermesYAML(_ text: String, helperPath: String, port: Int) -> String {
        guard !text.contains(AgentBridgeHelper.managedMarker) else { return text }

        let command = managedCommandString(helperPath: helperPath, agent: .hermes, port: port)
        var lines = splitLines(text)
        let newline = text.hasSuffix("\n")
        let hookEntry = [
            "  DockCatAgentEvent:",
            "    - \"\(yamlEscaped(command))\""
        ]

        if let hooksIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "hooks:" }) {
            lines.insert(contentsOf: hookEntry, at: hooksIndex + 1)
        } else {
            lines.insert(contentsOf: ["hooks:"] + hookEntry + [""], at: 0)
        }

        let allowlistEntry = "  - \"\(yamlEscaped(command))\""
        if let allowlistIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "hooks_allowlist:" }) {
            lines.insert(allowlistEntry, at: allowlistIndex + 1)
        } else {
            if !lines.isEmpty, !lines.last!.isEmpty {
                lines.append("")
            }
            lines.append("hooks_allowlist:")
            lines.append(allowlistEntry)
        }

        return joinLines(lines, trailingNewline: newline)
    }

    static func removeHermesYAML(_ text: String) -> String {
        var lines = splitLines(text)
        let newline = text.hasSuffix("\n")
        var index = 0
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed == "DockCatAgentEvent:" {
                lines.remove(at: index)
                while index < lines.count, lines[index].hasPrefix("    ") {
                    lines.remove(at: index)
                }
                continue
            }
            if lines[index].contains(AgentBridgeHelper.managedMarker) {
                lines.remove(at: index)
                continue
            }
            index += 1
        }
        return joinLines(lines, trailingNewline: newline)
    }

    static func openClawStatus(openClawConfigExists: Bool, migrationReportExists: Bool) -> AgentBridgeStatus {
        if openClawConfigExists {
            return .detected
        }
        if migrationReportExists {
            return .migrated
        }
        return .notInstalled
    }

    static func managedCommandString(helperPath: String, agent: AgentBridgeAgentID, port: Int) -> String {
        AgentBridgeHelper.commandArguments(
            helperPath: helperPath,
            agent: agent,
            port: port,
            session: agent.rawValue
        )
        .map(shellQuoted)
        .joined(separator: " ")
    }

    private static func splitLines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private static func joinLines(_ lines: [String], trailingNewline: Bool) -> String {
        var text = lines.joined(separator: "\n")
        if trailingNewline, !text.hasSuffix("\n") {
            text.append("\n")
        }
        return text
    }

    private static func leadingWhitespace(_ line: String) -> String {
        String(line.prefix { $0 == " " || $0 == "\t" })
    }

    private static func parseTomlStringArray(_ line: String) -> [String] {
        guard let start = line.firstIndex(of: "["),
              let end = line.lastIndex(of: "]"),
              start < end
        else {
            return []
        }

        var values: [String] = []
        var current = ""
        var insideString = false
        var escaping = false
        for character in line[line.index(after: start)..<end] {
            if escaping {
                current.append(character)
                escaping = false
                continue
            }
            if character == "\\" {
                escaping = true
                continue
            }
            if character == "\"" {
                if insideString {
                    values.append(current)
                    current = ""
                }
                insideString.toggle()
                continue
            }
            if insideString {
                current.append(character)
            }
        }
        return values
    }

    private static func codexChainArguments(from line: String) -> [String]? {
        let arguments = parseTomlStringArray(line)
        guard let chainIndex = arguments.firstIndex(of: "--chain") else {
            return nil
        }
        let firstChainedIndex = arguments.indices.contains(chainIndex + 1) && arguments[chainIndex + 1] == "--"
            ? chainIndex + 2
            : chainIndex + 1
        guard arguments.indices.contains(firstChainedIndex) else {
            return []
        }
        return Array(arguments[firstChainedIndex...])
    }

    private static func tomlStringArray(_ values: [String]) -> String {
        "[\(values.map(tomlQuoted).joined(separator: ", "))]"
    }

    private static func tomlQuoted(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private static func shellQuoted(_ value: String) -> String {
        let safe = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_/:.,=+-")
        if value.rangeOfCharacter(from: safe.inverted) == nil {
            return value
        }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func yamlEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func containsManagedCommand(_ value: Any, helperPath: String) -> Bool {
        if let command = value as? String {
            return command.contains(AgentBridgeHelper.managedMarker) || command.contains(helperPath)
        }
        if let dictionary = value as? [String: Any],
           let command = dictionary["command"] as? String {
            return command.contains(AgentBridgeHelper.managedMarker) || command.contains(helperPath)
        }
        return false
    }
}
