import XCTest
@testable import DockCat

final class AgentBridgeConfigPatcherTests: XCTestCase {
    private let helperPath = "/Users/test/Library/Application Support/DockCat/AgentBridge/dockcat-agent-event"

    func testCodexPatchPreservesCommentsAndRestoresPreviousNotify() {
        let original = """
        # existing comment
        notify = ["old", "arg"]
        model = "gpt-5"
        """

        let patch = AgentBridgeConfigPatcher.patchCodexTOML(original, helperPath: helperPath, port: 8765)
        let restored = AgentBridgeConfigPatcher.restoreCodexTOML(patch.text, previousNotifyLine: patch.previousNotifyLine)

        XCTAssertTrue(patch.text.contains("# existing comment"))
        XCTAssertTrue(patch.text.contains("dockcat-agent-event"))
        XCTAssertTrue(patch.text.contains("--chain"))
        XCTAssertTrue(restored.contains("notify = [\"old\", \"arg\"]"))
    }

    func testClaudePatchPreservesExistingSettingsAndRemovesOnlyDockCatHooks() throws {
        let json = """
        {
          "env": { "A": "B" },
          "theme": "dark",
          "hooks": {
            "Stop": [
              { "type": "command", "command": "old-stop" }
            ]
          }
        }
        """.data(using: .utf8)!

        let patched = try AgentBridgeConfigPatcher.patchClaudeSettingsJSON(json, helperPath: helperPath, port: 8765)
        let patchedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: patched) as? [String: Any])
        XCTAssertEqual(patchedObject["theme"] as? String, "dark")
        XCTAssertNotNil(patchedObject["env"])

        let hooks = try XCTUnwrap(patchedObject["hooks"] as? [String: Any])
        let stopHooks = try XCTUnwrap(hooks["Stop"] as? [[String: String]])
        XCTAssertTrue(stopHooks.contains { $0["command"] == "old-stop" })
        XCTAssertTrue(stopHooks.contains { $0["command"]?.contains(AgentBridgeHelper.managedMarker) == true })

        let removed = try AgentBridgeConfigPatcher.removeClaudeSettingsJSON(patched, helperPath: helperPath)
        let removedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: removed) as? [String: Any])
        let removedHooks = try XCTUnwrap(removedObject["hooks"] as? [String: Any])
        let removedStopHooks = try XCTUnwrap(removedHooks["Stop"] as? [[String: String]])
        XCTAssertEqual(removedStopHooks.map { $0["command"] }, ["old-stop"])
    }

    func testHermesPatchAddsHooksAndExactAllowlistWithoutRemovingExistingEntries() {
        let original = """
        hooks:
          Stop:
            - "old-command"
        hooks_auto_accept: false
        """

        let patched = AgentBridgeConfigPatcher.patchHermesYAML(original, helperPath: "/tmp/dockcat-agent-event", port: 8765)

        XCTAssertTrue(patched.contains("hooks:"))
        XCTAssertTrue(patched.contains("old-command"))
        XCTAssertTrue(patched.contains("DockCatAgentEvent"))
        XCTAssertTrue(patched.contains("hooks_allowlist:"))
        XCTAssertTrue(patched.contains("  - \"/tmp/dockcat-agent-event --dockcat-managed --agent hermes --session hermes --status info --port 8765\""))
    }

    func testOpenClawMigrationStatusRequiresReportWithoutLiveConfig() {
        XCTAssertEqual(
            AgentBridgeConfigPatcher.openClawStatus(openClawConfigExists: true, migrationReportExists: true),
            .detected
        )
        XCTAssertEqual(
            AgentBridgeConfigPatcher.openClawStatus(openClawConfigExists: false, migrationReportExists: true),
            .migrated
        )
        XCTAssertEqual(
            AgentBridgeConfigPatcher.openClawStatus(openClawConfigExists: false, migrationReportExists: false),
            .notInstalled
        )
    }
}
