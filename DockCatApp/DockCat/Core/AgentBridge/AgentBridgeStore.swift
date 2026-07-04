import Foundation

enum AgentBridgeStoreError: Error, Equatable {
    case fileChanged
    case missingApplicationSupportDirectory
}

struct AgentBridgeBackupRecord: Codable, Equatable {
    var agent: AgentBridgeAgentID
    var originalPath: String
    var backupPath: String
    var createdAt: Date
}

struct AgentBridgeBackupManifest: Codable, Equatable {
    var records: [AgentBridgeBackupRecord]

    static let empty = AgentBridgeBackupManifest(records: [])
}

struct AgentBridgeFileMetadata: Equatable {
    var size: UInt64
    var modificationDate: Date?
    var systemFileNumber: UInt64?
    var posixPermissions: Int?
}

struct AgentBridgeFileSnapshot: Equatable {
    var url: URL
    var data: Data
    var metadata: AgentBridgeFileMetadata
}

final class AgentBridgeStore {
    let homeURL: URL
    let applicationSupportURL: URL
    private let fileManager: FileManager

    init(
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationSupportURL: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
        fileManager: FileManager = .default
    ) throws {
        guard let applicationSupportURL else {
            throw AgentBridgeStoreError.missingApplicationSupportDirectory
        }
        self.homeURL = homeURL
        self.applicationSupportURL = applicationSupportURL
        self.fileManager = fileManager
    }

    var bridgeDirectoryURL: URL {
        applicationSupportURL
            .appendingPathComponent("DockCat", isDirectory: true)
            .appendingPathComponent("AgentBridge", isDirectory: true)
    }

    var helperURL: URL {
        bridgeDirectoryURL.appendingPathComponent(AgentBridgeHelper.executableName)
    }

    var backupsDirectoryURL: URL {
        bridgeDirectoryURL.appendingPathComponent("Backups", isDirectory: true)
    }

    var manifestURL: URL {
        bridgeDirectoryURL.appendingPathComponent("backup-manifest.json")
    }

    func installHelper(defaultPort: Int) throws -> URL {
        try fileManager.createDirectory(at: bridgeDirectoryURL, withIntermediateDirectories: true)
        let scriptData = Data(AgentBridgeHelper.script(defaultPort: defaultPort).utf8)
        try scriptData.write(to: helperURL)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)
        return helperURL
    }

    func backupFile(_ originalURL: URL, agent: AgentBridgeAgentID) throws -> AgentBridgeBackupRecord {
        try fileManager.createDirectory(at: backupsDirectoryURL, withIntermediateDirectories: true)
        let filename = "\(agent.rawValue)-\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString).bak"
        let backupURL = backupsDirectoryURL.appendingPathComponent(filename)
        try fileManager.copyItem(at: originalURL, to: backupURL)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)

        let record = AgentBridgeBackupRecord(
            agent: agent,
            originalPath: originalURL.path,
            backupPath: backupURL.path,
            createdAt: Date()
        )
        var manifest = try loadManifest()
        manifest.records.append(record)
        try saveManifest(manifest)
        return record
    }

    func loadManifest() throws -> AgentBridgeBackupManifest {
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return .empty
        }
        let data = try Data(contentsOf: manifestURL)
        return try JSONDecoder().decode(AgentBridgeBackupManifest.self, from: data)
    }

    func readFileSnapshot(_ url: URL) throws -> AgentBridgeFileSnapshot {
        AgentBridgeFileSnapshot(
            url: url,
            data: try Data(contentsOf: url),
            metadata: try metadata(for: url)
        )
    }

    func safeWrite(_ url: URL, data: Data, expected snapshot: AgentBridgeFileSnapshot) throws {
        guard url == snapshot.url,
              try metadata(for: url) == snapshot.metadata,
              try Data(contentsOf: url) == snapshot.data
        else {
            throw AgentBridgeStoreError.fileChanged
        }

        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent(".dockcat-\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporaryURL)
            if let permissions = snapshot.metadata.posixPermissions {
                try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: temporaryURL.path)
            }
            _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private func saveManifest(_ manifest: AgentBridgeBackupManifest) throws {
        try fileManager.createDirectory(at: bridgeDirectoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifestURL.path)
    }

    private func metadata(for url: URL) throws -> AgentBridgeFileMetadata {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return AgentBridgeFileMetadata(
            size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
            modificationDate: attributes[.modificationDate] as? Date,
            systemFileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
            posixPermissions: (attributes[.posixPermissions] as? NSNumber)?.intValue
        )
    }
}
