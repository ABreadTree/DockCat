import XCTest
@testable import DockCat

final class AppSettingsAgentBridgeTests: XCTestCase {
    func testDecodingLegacySettingsUsesAgentBridgeDefaults() throws {
        let data = "{}".data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertTrue(settings.agentHTTPEnabled)
        XCTAssertEqual(settings.agentHTTPPort, 8765)
        XCTAssertFalse(settings.agentBridge.codex.enabled)
        XCTAssertFalse(settings.agentBridge.claudeCode.enabled)
        XCTAssertFalse(settings.agentBridge.hermes.enabled)
        XCTAssertFalse(settings.agentBridge.openClaw.enabled)
    }

    func testEncodesAndDecodesAgentBridgeSettings() throws {
        var settings = AppSettings.defaults
        settings.agentHTTPEnabled = false
        settings.agentHTTPPort = 9876
        settings.agentBridge.codex.enabled = true
        settings.agentBridge.hermes.enabled = true

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertFalse(decoded.agentHTTPEnabled)
        XCTAssertEqual(decoded.agentHTTPPort, 9876)
        XCTAssertTrue(decoded.agentBridge.codex.enabled)
        XCTAssertFalse(decoded.agentBridge.claudeCode.enabled)
        XCTAssertTrue(decoded.agentBridge.hermes.enabled)
        XCTAssertFalse(decoded.agentBridge.openClaw.enabled)
    }
}
