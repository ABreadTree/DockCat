import XCTest
@testable import DockCat

final class AgentBridgeManagerTests: XCTestCase {
    func testDetectsSupportedAgentsAndOpenClawMigrationReport() throws {
        let fixture = try makeFixture()
        try write("notify = [\"old\"]\n", to: fixture.home.appendingPathComponent(".codex/config.toml"))
        try write("{}", to: fixture.home.appendingPathComponent(".claude/settings.json"))
        try write("hooks_auto_accept: false\n", to: fixture.home.appendingPathComponent(".hermes/config.yaml"))
        try write("{}", to: fixture.home.appendingPathComponent(".openclaw-migration-report.json"))

        let snapshot = fixture.manager.snapshot(settings: .defaults, serverRunning: true)
        let statuses = Dictionary(uniqueKeysWithValues: snapshot.agents.map { ($0.agent, $0.status) })

        XCTAssertEqual(statuses[.codex], .detected)
        XCTAssertEqual(statuses[.claudeCode], .detected)
        XCTAssertEqual(statuses[.hermes], .detected)
        XCTAssertEqual(statuses[.openClaw], .migrated)
    }

    func testEnableAllDetectedSkipsUnavailableOpenClaw() throws {
        let fixture = try makeFixture()
        try write("notify = [\"old\"]\n", to: fixture.home.appendingPathComponent(".codex/config.toml"))
        try write("{}", to: fixture.home.appendingPathComponent(".claude/settings.json"))
        try write("hooks_auto_accept: false\n", to: fixture.home.appendingPathComponent(".hermes/config.yaml"))
        try write("{}", to: fixture.home.appendingPathComponent(".openclaw-migration-report.json"))

        let results = fixture.manager.enableAllDetected(port: 8765, settings: .defaults)

        XCTAssertEqual(results.count, 3)
        XCTAssertTrue(results.allSatisfy(\.succeeded))
        XCTAssertTrue(try String(contentsOf: fixture.home.appendingPathComponent(".codex/config.toml")).contains(AgentBridgeHelper.managedMarker))
        XCTAssertTrue(try String(contentsOf: fixture.home.appendingPathComponent(".claude/settings.json")).contains(AgentBridgeHelper.managedMarker))
        XCTAssertTrue(try String(contentsOf: fixture.home.appendingPathComponent(".hermes/config.yaml")).contains(AgentBridgeHelper.managedMarker))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.home.appendingPathComponent(".openclaw/config.json").path))
    }

    func testTestEventPayloadDecodesForExistingEndpointContract() throws {
        let fixture = try makeFixture()
        let data = try fixture.manager.testEventPayload(agent: .codex)
        let event = try AgentEvent.decode(from: data)

        XCTAssertEqual(event.agent, "codex")
        XCTAssertEqual(event.session, "dockcat-settings")
        XCTAssertEqual(event.status, .info)
        XCTAssertEqual(event.message, "Codex bridge test")
    }

    private func makeFixture() throws -> (home: URL, manager: AgentBridgeManager) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockCatAgentBridgeManagerTests-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let support = root.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let store = try AgentBridgeStore(homeURL: home, applicationSupportURL: support)
        let manager = AgentBridgeManager(store: store) { command in
            ["codex", "claude", "hermes"].contains(command)
                ? URL(fileURLWithPath: "/usr/bin/\(command)")
                : nil
        }
        return (home, manager)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
}
