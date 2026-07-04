import XCTest
@testable import DockCat

final class AgentBridgeStoreTests: XCTestCase {
    func testBackupCreatesOwnerOnlyCopyAndManifestUnderInjectedSupport() throws {
        let root = try temporaryRoot()
        let home = root.appendingPathComponent("home", isDirectory: true)
        let support = root.appendingPathComponent("support", isDirectory: true)
        let config = home.appendingPathComponent(".codex", isDirectory: true).appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("notify = [\"old\"]\n".utf8).write(to: config)

        let store = try AgentBridgeStore(homeURL: home, applicationSupportURL: support)
        let record = try store.backupFile(config, agent: .codex)
        let manifest = try store.loadManifest()

        XCTAssertTrue(record.backupPath.hasPrefix(support.path))
        XCTAssertEqual(manifest.records.map(\.originalPath), [config.path])
        XCTAssertEqual(manifest.records.map(\.agent), [.codex])

        let attributes = try FileManager.default.attributesOfItem(atPath: record.backupPath)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
    }

    func testInstallHelperCreatesExecutableOwnerOnlyScript() throws {
        let root = try temporaryRoot()
        let store = try AgentBridgeStore(
            homeURL: root.appendingPathComponent("home", isDirectory: true),
            applicationSupportURL: root.appendingPathComponent("support", isDirectory: true)
        )

        let helperURL = try store.installHelper(defaultPort: 8765)
        let script = try String(contentsOf: helperURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: helperURL.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)

        XCTAssertTrue(script.contains("127.0.0.1"))
        XCTAssertEqual(permissions.intValue & 0o777, 0o700)
    }

    func testSafeWriteFailsWhenFileChangesBetweenReadAndCommit() throws {
        let root = try temporaryRoot()
        let config = root.appendingPathComponent("config.toml")
        try Data("one".utf8).write(to: config)

        let store = try AgentBridgeStore(homeURL: root, applicationSupportURL: root.appendingPathComponent("support", isDirectory: true))
        let snapshot = try store.readFileSnapshot(config)
        try Data("changed".utf8).write(to: config)

        XCTAssertThrowsError(try store.safeWrite(config, data: Data("two".utf8), expected: snapshot)) { error in
            XCTAssertEqual(error as? AgentBridgeStoreError, .fileChanged)
        }
        XCTAssertEqual(try String(contentsOf: config), "changed")
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockCatAgentBridgeStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
