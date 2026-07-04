import Foundation

final class AgentBridgeManager {
    typealias CommandLocator = (String) -> URL?

    private let store: AgentBridgeStore
    private let fileManager: FileManager
    private let commandLocator: CommandLocator

    init(
        store: AgentBridgeStore,
        fileManager: FileManager = .default,
        commandLocator: @escaping CommandLocator = AgentBridgeManager.defaultCommandLocator
    ) {
        self.store = store
        self.fileManager = fileManager
        self.commandLocator = commandLocator
    }

    static func live() throws -> AgentBridgeManager {
        try AgentBridgeManager(store: AgentBridgeStore())
    }

    func snapshot(settings: AppSettings, serverRunning: Bool) -> AgentBridgeSnapshot {
        AgentBridgeSnapshot(
            serverEnabled: settings.agentHTTPEnabled,
            serverPort: AppSettings.normalizedAgentHTTPPort(settings.agentHTTPPort),
            serverRunning: serverRunning,
            helperPath: store.helperURL.path,
            agents: AgentBridgeAgentID.allCases.map { agent in
                detect(agent: agent, settings: settings)
            }
        )
    }

    func enable(_ agent: AgentBridgeAgentID, port: Int) -> AgentBridgeActionResult {
        do {
            try enableThrowing(agent, port: port)
            return .success("\(agent.displayName) bridge enabled.")
        } catch {
            return .failure("\(agent.displayName) bridge failed: \(error.localizedDescription)")
        }
    }

    func disable(_ agent: AgentBridgeAgentID) -> AgentBridgeActionResult {
        do {
            try disableThrowing(agent)
            return .success("\(agent.displayName) bridge disabled.")
        } catch {
            return .failure("\(agent.displayName) disable failed: \(error.localizedDescription)")
        }
    }

    func enableAllDetected(port: Int, settings: AppSettings) -> [AgentBridgeActionResult] {
        snapshot(settings: settings, serverRunning: false).agents
            .filter { $0.status == .detected || $0.status == .enabled }
            .map { enable($0.agent, port: port) }
    }

    func testEventPayload(agent: AgentBridgeAgentID) throws -> Data {
        let payload = [
            "agent": agent.rawValue,
            "session": "dockcat-settings",
            "status": AgentStatus.info.rawValue,
            "message": "\(agent.displayName) bridge test",
            "hint": "DockCat received a local agent event."
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    private func detect(agent: AgentBridgeAgentID, settings: AppSettings) -> AgentBridgeAgentSnapshot {
        if agent == .openClaw {
            let status = AgentBridgeConfigPatcher.openClawStatus(
                openClawConfigExists: fileExists(configURL(for: .openClaw)),
                migrationReportExists: fileExists(openClawMigrationReportURL)
            )
            return AgentBridgeAgentSnapshot(
                agent: agent,
                status: bridgeSetting(for: agent, in: settings).enabled && status == .detected ? .enabled : status,
                detail: detail(for: status),
                configPath: configURL(for: agent).path
            )
        }

        let configURL = configURL(for: agent)
        let hasConfig = fileExists(configURL)
        let commandAvailable = commandLocator(commandName(for: agent)) != nil
        let configManaged = hasConfig && ((try? String(contentsOf: configURL).contains(AgentBridgeHelper.managedMarker)) ?? false)
        let settingEnabled = bridgeSetting(for: agent, in: settings).enabled
        let status: AgentBridgeStatus
        if configManaged || settingEnabled {
            status = .enabled
        } else if hasConfig || commandAvailable {
            status = .detected
        } else {
            status = .notInstalled
        }
        return AgentBridgeAgentSnapshot(
            agent: agent,
            status: status,
            detail: detail(for: status),
            configPath: configURL.path
        )
    }

    private func enableThrowing(_ agent: AgentBridgeAgentID, port: Int) throws {
        _ = try store.installHelper(defaultPort: port)
        let url = configURL(for: agent)

        switch agent {
        case .codex:
            let text = try readTextIfExists(url) ?? ""
            let patched = AgentBridgeConfigPatcher.patchCodexTOML(text, helperPath: store.helperURL.path, port: port).text
            try writeConfig(url, data: Data(patched.utf8), agent: agent)
        case .claudeCode:
            let data = try readDataIfExists(url) ?? Data("{}".utf8)
            let patched = try AgentBridgeConfigPatcher.patchClaudeSettingsJSON(data, helperPath: store.helperURL.path, port: port)
            try writeConfig(url, data: patched, agent: agent)
        case .hermes:
            let text = try readTextIfExists(url) ?? "hooks_auto_accept: false\n"
            let patched = AgentBridgeConfigPatcher.patchHermesYAML(text, helperPath: store.helperURL.path, port: port)
            try writeConfig(url, data: Data(patched.utf8), agent: agent)
        case .openClaw:
            guard fileExists(url) else {
                throw CocoaError(.fileNoSuchFile)
            }
            let data = try readDataIfExists(url) ?? Data("{}".utf8)
            let patched = try patchJSONHooks(data, agent: .openClaw, port: port)
            try writeConfig(url, data: patched, agent: agent)
        }
    }

    private func disableThrowing(_ agent: AgentBridgeAgentID) throws {
        let url = configURL(for: agent)
        guard fileExists(url) else { return }

        switch agent {
        case .codex:
            let text = try String(contentsOf: url)
            try writeConfig(url, data: Data(AgentBridgeConfigPatcher.restoreCodexTOML(text, previousNotifyLine: nil).utf8), agent: agent)
        case .claudeCode:
            let data = try Data(contentsOf: url)
            try writeConfig(url, data: try AgentBridgeConfigPatcher.removeClaudeSettingsJSON(data, helperPath: store.helperURL.path), agent: agent)
        case .hermes:
            let text = try String(contentsOf: url)
            try writeConfig(url, data: Data(AgentBridgeConfigPatcher.removeHermesYAML(text).utf8), agent: agent)
        case .openClaw:
            let data = try Data(contentsOf: url)
            try writeConfig(url, data: try removeJSONHooks(data), agent: agent)
        }
    }

    private func writeConfig(_ url: URL, data: Data, agent: AgentBridgeAgentID) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileExists(url) {
            let snapshot = try store.readFileSnapshot(url)
            _ = try store.backupFile(url, agent: agent)
            try store.safeWrite(url, data: data, expected: snapshot)
        } else {
            try data.write(to: url)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    private func patchJSONHooks(_ data: Data, agent: AgentBridgeAgentID, port: Int) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentBridgeConfigPatchError.invalidJSON
        }
        let command = AgentBridgeConfigPatcher.managedCommandString(helperPath: store.helperURL.path, agent: agent, port: port)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var stopHooks = hooks["Stop"] as? [Any] ?? []
        if !stopHooks.contains(where: { containsManagedCommand($0) }) {
            stopHooks.append(["type": "command", "command": command])
        }
        hooks["Stop"] = stopHooks
        root["hooks"] = hooks
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    private func removeJSONHooks(_ data: Data) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentBridgeConfigPatchError.invalidJSON
        }
        guard var hooks = root["hooks"] as? [String: Any] else {
            return data
        }
        for (key, value) in hooks {
            guard let entries = value as? [Any] else { continue }
            hooks[key] = entries.filter { !containsManagedCommand($0) }
        }
        root["hooks"] = hooks
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    private func containsManagedCommand(_ value: Any) -> Bool {
        if let command = value as? String {
            return command.contains(AgentBridgeHelper.managedMarker)
        }
        if let dictionary = value as? [String: Any],
           let command = dictionary["command"] as? String {
            return command.contains(AgentBridgeHelper.managedMarker)
        }
        return false
    }

    private func bridgeSetting(for agent: AgentBridgeAgentID, in settings: AppSettings) -> AgentBridgeAgentSetting {
        settings.agentBridge[keyPath: agent.settingsKeyPath]
    }

    private func configURL(for agent: AgentBridgeAgentID) -> URL {
        switch agent {
        case .codex:
            store.homeURL.appendingPathComponent(".codex", isDirectory: true).appendingPathComponent("config.toml")
        case .claudeCode:
            store.homeURL.appendingPathComponent(".claude", isDirectory: true).appendingPathComponent("settings.json")
        case .hermes:
            store.homeURL.appendingPathComponent(".hermes", isDirectory: true).appendingPathComponent("config.yaml")
        case .openClaw:
            store.homeURL.appendingPathComponent(".openclaw", isDirectory: true).appendingPathComponent("config.json")
        }
    }

    private var openClawMigrationReportURL: URL {
        store.homeURL.appendingPathComponent(".openclaw-migration-report.json")
    }

    private func commandName(for agent: AgentBridgeAgentID) -> String {
        switch agent {
        case .codex: "codex"
        case .claudeCode: "claude"
        case .hermes: "hermes"
        case .openClaw: "openclaw"
        }
    }

    private func detail(for status: AgentBridgeStatus) -> String {
        switch status {
        case .notInstalled: "Not installed"
        case .detected: "Detected"
        case .enabled: "Enabled"
        case .migrated: "Migration report found"
        case .failed: "Failed"
        }
    }

    private func fileExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    private func readTextIfExists(_ url: URL) throws -> String? {
        fileExists(url) ? try String(contentsOf: url) : nil
    }

    private func readDataIfExists(_ url: URL) throws -> Data? {
        fileExists(url) ? try Data(contentsOf: url) : nil
    }

    private static func defaultCommandLocator(_ command: String) -> URL? {
        let fixedPaths = [
            "/opt/homebrew/bin/\(command)",
            "/usr/local/bin/\(command)",
            "/usr/bin/\(command)"
        ]
        if let path = fixedPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: path)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return output.isEmpty ? nil : URL(fileURLWithPath: output)
        } catch {
            return nil
        }
    }
}
