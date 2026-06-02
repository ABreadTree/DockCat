import Foundation

struct UserDataBackupSnapshot: Codable, Equatable {
    var schemaVersion: Int
    var generatedAt: Date
    var appVersion: String
    var bundleIdentifier: String
    var settings: UserDataBackupSettings
    var usageStatistics: UsageStatistics
    var collectableInventory: UserDataBackupCollectableInventory

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case generatedAt
        case appVersion
        case bundleIdentifier
        case settings
        case usageStatistics
        case collectableInventory
    }
}

struct UserDataBackupSettings: Codable, Equatable {
    var language: AppLanguage
    var catName: String
    var catIdentifier: String
    var userSalutation: String
    var selectedAssetPackID: String
    var remindersEnabled: Bool
    var waterReminderInterval: TimeInterval
    var waterReminderMessageSuffix: String
    var movementReminderInterval: TimeInterval
    var movementReminderMessageSuffix: String
    var customReminderEnabled: Bool
    var customReminderInterval: TimeInterval
    var customReminderMessageSuffix: String
    var outingDepartureMessageSuffix: String
    var defaultOutingDuration: TimeInterval
    var restDurationMinimum: TimeInterval
    var restDurationMaximum: TimeInterval
    var walkDurationMinimum: TimeInterval
    var walkDurationMaximum: TimeInterval
    var walkBaseSpeed: Double
    var catScalePercent: Double
    var startPositionPercent: Double
    var catActivityScope: CatActivityScope
    var activityDisplayID: UInt32?

    enum CodingKeys: String, CodingKey {
        case language
        case catName
        case catIdentifier
        case userSalutation
        case selectedAssetPackID
        case remindersEnabled
        case waterReminderInterval
        case waterReminderMessageSuffix
        case movementReminderInterval
        case movementReminderMessageSuffix
        case customReminderEnabled
        case customReminderInterval
        case customReminderMessageSuffix
        case outingDepartureMessageSuffix
        case defaultOutingDuration
        case restDurationMinimum
        case restDurationMaximum
        case walkDurationMinimum
        case walkDurationMaximum
        case walkBaseSpeed
        case catScalePercent
        case startPositionPercent
        case catActivityScope
        case activityDisplayID
    }

    enum LegacyCodingKeys: String, CodingKey {
        case outingDepartureMessageTemplate
    }

    init(settings: AppSettings) {
        language = settings.language
        catName = settings.catName
        catIdentifier = settings.catIdentifier
        userSalutation = settings.userSalutation
        selectedAssetPackID = settings.selectedAssetPackID
        remindersEnabled = settings.remindersEnabled
        waterReminderInterval = settings.waterReminderInterval
        waterReminderMessageSuffix = settings.waterReminderMessageSuffix
        movementReminderInterval = settings.movementReminderInterval
        movementReminderMessageSuffix = settings.movementReminderMessageSuffix
        customReminderEnabled = settings.customReminderEnabled
        customReminderInterval = settings.customReminderInterval
        customReminderMessageSuffix = settings.customReminderMessageSuffix
        outingDepartureMessageSuffix = settings.outingDepartureMessageSuffix
        defaultOutingDuration = settings.defaultOutingDuration
        restDurationMinimum = settings.restDurationMinimum
        restDurationMaximum = settings.restDurationMaximum
        walkDurationMinimum = settings.walkDurationMinimum
        walkDurationMaximum = settings.walkDurationMaximum
        walkBaseSpeed = settings.walkBaseSpeed
        catScalePercent = settings.catScalePercent
        startPositionPercent = settings.startPositionPercent
        catActivityScope = settings.catActivityScope
        activityDisplayID = settings.activityDisplayID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? AppSettings.defaults.language
        let defaults = AppSettings.defaults(for: language)
        catName = try container.decodeIfPresent(String.self, forKey: .catName) ?? defaults.catName
        catIdentifier = try container.decodeIfPresent(String.self, forKey: .catIdentifier) ?? defaults.catIdentifier
        userSalutation = try container.decodeIfPresent(String.self, forKey: .userSalutation) ?? defaults.userSalutation
        selectedAssetPackID = try container.decodeIfPresent(String.self, forKey: .selectedAssetPackID) ?? defaults.selectedAssetPackID
        remindersEnabled = try container.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? defaults.remindersEnabled
        waterReminderInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .waterReminderInterval) ?? defaults.waterReminderInterval
        waterReminderMessageSuffix = try container.decodeIfPresent(String.self, forKey: .waterReminderMessageSuffix) ?? defaults.waterReminderMessageSuffix
        movementReminderInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .movementReminderInterval) ?? defaults.movementReminderInterval
        movementReminderMessageSuffix = try container.decodeIfPresent(String.self, forKey: .movementReminderMessageSuffix) ?? defaults.movementReminderMessageSuffix
        customReminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .customReminderEnabled) ?? defaults.customReminderEnabled
        customReminderInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .customReminderInterval) ?? defaults.customReminderInterval
        customReminderMessageSuffix = try container.decodeIfPresent(String.self, forKey: .customReminderMessageSuffix) ?? defaults.customReminderMessageSuffix
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        let decodedOutingSuffix = try container.decodeIfPresent(String.self, forKey: .outingDepartureMessageSuffix)
            ?? legacyContainer.decodeIfPresent(String.self, forKey: .outingDepartureMessageTemplate)
        outingDepartureMessageSuffix = AppSettings.normalizedOutingDepartureMessageSuffix(
            decodedOutingSuffix,
            language: language,
            fallback: defaults.outingDepartureMessageSuffix
        )
        defaultOutingDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .defaultOutingDuration) ?? defaults.defaultOutingDuration
        restDurationMinimum = try container.decodeIfPresent(TimeInterval.self, forKey: .restDurationMinimum) ?? defaults.restDurationMinimum
        restDurationMaximum = try container.decodeIfPresent(TimeInterval.self, forKey: .restDurationMaximum) ?? defaults.restDurationMaximum
        walkDurationMinimum = try container.decodeIfPresent(TimeInterval.self, forKey: .walkDurationMinimum) ?? defaults.walkDurationMinimum
        walkDurationMaximum = try container.decodeIfPresent(TimeInterval.self, forKey: .walkDurationMaximum) ?? defaults.walkDurationMaximum
        walkBaseSpeed = try container.decodeIfPresent(Double.self, forKey: .walkBaseSpeed) ?? defaults.walkBaseSpeed
        catScalePercent = try container.decodeIfPresent(Double.self, forKey: .catScalePercent) ?? defaults.catScalePercent
        startPositionPercent = try container.decodeIfPresent(Double.self, forKey: .startPositionPercent) ?? defaults.startPositionPercent
        catActivityScope = try container.decodeIfPresent(CatActivityScope.self, forKey: .catActivityScope) ?? defaults.catActivityScope
        activityDisplayID = try container.decodeIfPresent(UInt32.self, forKey: .activityDisplayID) ?? defaults.activityDisplayID
    }
}

struct UserDataBackupCollectableInventory: Codable, Equatable {
    var entries: [String: UserDataBackupCollectableInventoryEntry]
    var recentNewCollectableID: String?

    init(entries: [String: UserDataBackupCollectableInventoryEntry], recentNewCollectableID: String?) {
        self.entries = entries
        self.recentNewCollectableID = recentNewCollectableID
    }

    init(inventory: CollectableInventory) {
        entries = inventory.entries.mapValues { entry in
            UserDataBackupCollectableInventoryEntry(entry: entry)
        }
        recentNewCollectableID = inventory.recentNewCollectableID
    }
}

struct UserDataBackupCollectableInventoryEntry: Codable, Equatable {
    var collectableID: String
    var count: Int?
    var firstAcquiredAt: Date?
    var lastAcquiredAt: Date

    init(
        collectableID: String,
        count: Int? = nil,
        firstAcquiredAt: Date? = nil,
        lastAcquiredAt: Date
    ) {
        self.collectableID = collectableID
        self.count = count
        self.firstAcquiredAt = firstAcquiredAt
        self.lastAcquiredAt = lastAcquiredAt
    }

    init(entry: CollectableInventoryEntry) {
        collectableID = entry.collectableID
        count = entry.count
        firstAcquiredAt = entry.firstAcquiredAt
        lastAcquiredAt = entry.lastAcquiredAt
    }
}

struct UserDataRestoreResult: Equatable {
    var usageStatistics: UsageStatistics
    var collectableInventory: CollectableInventory
    var skippedCollectableNames: [String]
}

enum UserDataBackupRestoreError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case invalidUsageStatistics
    case invalidCollectableEntry(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let schema):
            return "Unsupported backup schema version: \(schema)."
        case .invalidUsageStatistics:
            return "Backup usage statistics are invalid."
        case .invalidCollectableEntry(let id):
            return "Backup collectable entry is invalid: \(id)."
        }
    }
}

final class UserDataBackupStore {
    private let fileManager: FileManager
    private let applicationSupportURL: URL
    private let appVersionProvider: () -> String
    private let bundleIdentifierProvider: () -> String
    private let now: () -> Date

    init(
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil,
        bundle: Bundle = .main,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.applicationSupportURL = applicationSupportURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        appVersionProvider = {
            bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        }
        bundleIdentifierProvider = {
            bundle.bundleIdentifier ?? "com.tianmaizhang.DockCat"
        }
        self.now = now
    }

    var backupDirectoryURL: URL {
        applicationSupportURL
            .appendingPathComponent("DockCat", isDirectory: true)
            .appendingPathComponent("DataBackup", isDirectory: true)
    }

    var backupFileURL: URL {
        backupDirectoryURL.appendingPathComponent("user-data-backup.json")
    }

    func save(
        settings: AppSettings,
        usageStatistics: UsageStatistics,
        collectableInventory: CollectableInventory
    ) {
        let snapshot = UserDataBackupSnapshot(
            schemaVersion: 2,
            generatedAt: now(),
            appVersion: appVersionProvider(),
            bundleIdentifier: bundleIdentifierProvider(),
            settings: UserDataBackupSettings(settings: settings),
            usageStatistics: usageStatistics,
            collectableInventory: UserDataBackupCollectableInventory(inventory: collectableInventory)
        )

        do {
            try fileManager.createDirectory(at: backupDirectoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(snapshot)
            try data.write(to: backupFileURL, options: .atomic)
        } catch {
            DockCatLog.app.error("Failed to write user data backup: \(error.localizedDescription)")
        }
    }

    func restoreData(from url: URL, outingCatalog: OutingCatalog) throws -> UserDataRestoreResult {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(UserDataBackupSnapshot.self, from: data)
        return try restoreData(from: snapshot, outingCatalog: outingCatalog)
    }

    func restoreData(from snapshot: UserDataBackupSnapshot, outingCatalog: OutingCatalog) throws -> UserDataRestoreResult {
        guard (1 ... 2).contains(snapshot.schemaVersion) else {
            throw UserDataBackupRestoreError.unsupportedSchema(snapshot.schemaVersion)
        }
        guard isValid(snapshot.usageStatistics) else {
            throw UserDataBackupRestoreError.invalidUsageStatistics
        }

        let collectablesByID = Dictionary(outingCatalog.collectables.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var restoredEntries: [String: CollectableInventoryEntry] = [:]
        var skippedNames: [String] = []

        for (key, backupEntry) in snapshot.collectableInventory.entries {
            let collectableID = backupEntry.collectableID.isEmpty ? key : backupEntry.collectableID
            guard !collectableID.isEmpty else {
                throw UserDataBackupRestoreError.invalidCollectableEntry(key)
            }
            guard collectablesByID[collectableID] != nil else {
                skippedNames.append(collectableID)
                continue
            }

            let count = backupEntry.count ?? 1
            guard count > 0 else {
                throw UserDataBackupRestoreError.invalidCollectableEntry(collectableID)
            }
            let firstAcquiredAt = backupEntry.firstAcquiredAt ?? backupEntry.lastAcquiredAt
            restoredEntries[collectableID] = CollectableInventoryEntry(
                collectableID: collectableID,
                count: count,
                firstAcquiredAt: firstAcquiredAt,
                lastAcquiredAt: backupEntry.lastAcquiredAt
            )
        }

        let recentNewCollectableID = snapshot.collectableInventory.recentNewCollectableID.flatMap { id in
            restoredEntries[id] == nil ? nil : id
        }

        return UserDataRestoreResult(
            usageStatistics: snapshot.usageStatistics,
            collectableInventory: CollectableInventory(
                entries: restoredEntries,
                recentNewCollectableID: recentNewCollectableID
            ),
            skippedCollectableNames: skippedNames.sorted()
        )
    }

    private func isValid(_ statistics: UsageStatistics) -> Bool {
        statistics.totalLitScreenUsageSeconds >= 0
            && statistics.completedWaterReminderCount >= 0
            && statistics.completedMovementReminderCount >= 0
            && statistics.outingEventCount >= 0
            && statistics.outingCollectableCount >= 0
    }
}
