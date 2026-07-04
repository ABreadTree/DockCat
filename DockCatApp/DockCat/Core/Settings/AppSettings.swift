import Foundation

enum CatActivityScope: String, Codable, Equatable, Hashable, CaseIterable {
    case dockEdge
    case desktop
}

struct AppSettings: Codable, Equatable {
    private static let defaultAssetPackID = "default-xiaohou"
    private static let legacyDefaultAssetPackID = "default-lizz"

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
    var activeOutingEndDate: Date?
    var activeOutingDuration: TimeInterval?

    func reminderMessageSuffix(for type: ReminderType) -> String {
        switch type {
        case .water:
            return waterReminderMessageSuffix
        case .movement:
            return movementReminderMessageSuffix
        case .custom:
            return customReminderMessageSuffix
        }
    }

    mutating func applyLanguageChangePreservingCustomText(to newLanguage: AppLanguage) {
        let oldLanguage = language
        guard oldLanguage != newLanguage else { return }
        let oldDefaults = AppSettings.defaults(for: oldLanguage)
        let newDefaults = AppSettings.defaults(for: newLanguage)
        if waterReminderMessageSuffix == oldDefaults.waterReminderMessageSuffix {
            waterReminderMessageSuffix = newDefaults.waterReminderMessageSuffix
        }
        if movementReminderMessageSuffix == oldDefaults.movementReminderMessageSuffix {
            movementReminderMessageSuffix = newDefaults.movementReminderMessageSuffix
        }
        if customReminderMessageSuffix == oldDefaults.customReminderMessageSuffix {
            customReminderMessageSuffix = newDefaults.customReminderMessageSuffix
        }
        if outingDepartureMessageSuffix == oldDefaults.outingDepartureMessageSuffix {
            outingDepartureMessageSuffix = newDefaults.outingDepartureMessageSuffix
        }
        language = newLanguage
    }

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
        case activeOutingEndDate
        case activeOutingDuration
    }

    enum LegacyCodingKeys: String, CodingKey {
        case standReminderInterval
        case outingDepartureMessageTemplate
    }

    static let defaults = AppSettings(
        language: .chinese,
        catName: "小猴",
        catIdentifier: "Xiaohou",
        userSalutation: "妈妈",
        selectedAssetPackID: defaultAssetPackID,
        remindersEnabled: true,
        waterReminderInterval: 30 * 60,
        waterReminderMessageSuffix: "该喝水啦",
        movementReminderInterval: 60 * 60,
        movementReminderMessageSuffix: "该起来走走啦",
        customReminderEnabled: false,
        customReminderInterval: 30 * 60,
        customReminderMessageSuffix: "休息一下吧",
        outingDepartureMessageSuffix: "工作要加油呀！",
        defaultOutingDuration: 25 * 60,
        restDurationMinimum: 2 * 60,
        restDurationMaximum: 5 * 60,
        walkDurationMinimum: 2 * 60,
        walkDurationMaximum: 5 * 60,
        walkBaseSpeed: 36,
        catScalePercent: 15,
        startPositionPercent: 75,
        catActivityScope: .dockEdge,
        activityDisplayID: nil,
        activeOutingEndDate: nil,
        activeOutingDuration: nil
    )

    static func defaults(for language: AppLanguage) -> AppSettings {
        switch language {
        case .chinese:
            return .defaults
        case .english:
            return AppSettings(
                language: .english,
                catName: "Xiaohou",
                catIdentifier: "Xiaohou",
                userSalutation: "Mom",
                selectedAssetPackID: defaultAssetPackID,
                remindersEnabled: true,
                waterReminderInterval: 30 * 60,
                waterReminderMessageSuffix: "time to drink some water.",
                movementReminderInterval: 60 * 60,
                movementReminderMessageSuffix: "time to stand up a bit.",
                customReminderEnabled: false,
                customReminderInterval: 30 * 60,
                customReminderMessageSuffix: "take a short break.",
                outingDepartureMessageSuffix: "Good luck with your work!",
                defaultOutingDuration: 25 * 60,
                restDurationMinimum: 2 * 60,
                restDurationMaximum: 5 * 60,
                walkDurationMinimum: 2 * 60,
                walkDurationMaximum: 5 * 60,
                walkBaseSpeed: 36,
                catScalePercent: 15,
                startPositionPercent: 75,
                catActivityScope: .dockEdge,
                activityDisplayID: nil,
                activeOutingEndDate: nil,
                activeOutingDuration: nil
            )
        }
    }

    init(
        language: AppLanguage,
        catName: String,
        catIdentifier: String,
        userSalutation: String,
        selectedAssetPackID: String,
        remindersEnabled: Bool,
        waterReminderInterval: TimeInterval,
        waterReminderMessageSuffix: String,
        movementReminderInterval: TimeInterval,
        movementReminderMessageSuffix: String,
        customReminderEnabled: Bool,
        customReminderInterval: TimeInterval,
        customReminderMessageSuffix: String,
        outingDepartureMessageSuffix: String,
        defaultOutingDuration: TimeInterval,
        restDurationMinimum: TimeInterval,
        restDurationMaximum: TimeInterval,
        walkDurationMinimum: TimeInterval,
        walkDurationMaximum: TimeInterval,
        walkBaseSpeed: Double,
        catScalePercent: Double,
        startPositionPercent: Double,
        catActivityScope: CatActivityScope,
        activityDisplayID: UInt32?,
        activeOutingEndDate: Date?,
        activeOutingDuration: TimeInterval?
    ) {
        self.language = language
        self.catName = catName
        self.catIdentifier = catIdentifier
        self.userSalutation = userSalutation
        self.selectedAssetPackID = selectedAssetPackID
        self.remindersEnabled = remindersEnabled
        self.waterReminderInterval = waterReminderInterval
        self.waterReminderMessageSuffix = waterReminderMessageSuffix
        self.movementReminderInterval = movementReminderInterval
        self.movementReminderMessageSuffix = movementReminderMessageSuffix
        self.customReminderEnabled = customReminderEnabled
        self.customReminderInterval = customReminderInterval
        self.customReminderMessageSuffix = customReminderMessageSuffix
        self.outingDepartureMessageSuffix = outingDepartureMessageSuffix
        self.defaultOutingDuration = defaultOutingDuration
        self.restDurationMinimum = restDurationMinimum
        self.restDurationMaximum = restDurationMaximum
        self.walkDurationMinimum = walkDurationMinimum
        self.walkDurationMaximum = walkDurationMaximum
        self.walkBaseSpeed = walkBaseSpeed
        self.catScalePercent = catScalePercent
        self.startPositionPercent = startPositionPercent
        self.catActivityScope = catActivityScope
        self.activityDisplayID = activityDisplayID
        self.activeOutingEndDate = activeOutingEndDate
        self.activeOutingDuration = activeOutingDuration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? AppSettings.defaults.language
        let defaults = AppSettings.defaults(for: language)
        catName = try container.decodeIfPresent(String.self, forKey: .catName) ?? defaults.catName
        catIdentifier = try container.decodeIfPresent(String.self, forKey: .catIdentifier) ?? defaults.catIdentifier
        userSalutation = try container.decodeIfPresent(String.self, forKey: .userSalutation) ?? defaults.userSalutation
        let decodedAssetPackID = try container.decodeIfPresent(String.self, forKey: .selectedAssetPackID)
        selectedAssetPackID = Self.normalizedAssetPackID(decodedAssetPackID ?? defaults.selectedAssetPackID)
        if decodedAssetPackID == Self.legacyDefaultAssetPackID {
            if catName == Self.legacyDefaultCatName(for: language) {
                catName = defaults.catName
            }
            if catIdentifier == "Lizz" {
                catIdentifier = defaults.catIdentifier
            }
        }
        remindersEnabled = try container.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? defaults.remindersEnabled
        waterReminderInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .waterReminderInterval) ?? defaults.waterReminderInterval
        waterReminderMessageSuffix = try container.decodeIfPresent(String.self, forKey: .waterReminderMessageSuffix) ?? defaults.waterReminderMessageSuffix
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        movementReminderInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .movementReminderInterval)
            ?? legacyContainer.decodeIfPresent(TimeInterval.self, forKey: .standReminderInterval)
            ?? defaults.movementReminderInterval
        movementReminderMessageSuffix = try container.decodeIfPresent(String.self, forKey: .movementReminderMessageSuffix) ?? defaults.movementReminderMessageSuffix
        customReminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .customReminderEnabled) ?? defaults.customReminderEnabled
        customReminderInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .customReminderInterval) ?? defaults.customReminderInterval
        customReminderMessageSuffix = try container.decodeIfPresent(String.self, forKey: .customReminderMessageSuffix) ?? defaults.customReminderMessageSuffix
        let decodedOutingSuffix = try container.decodeIfPresent(String.self, forKey: .outingDepartureMessageSuffix)
            ?? legacyContainer.decodeIfPresent(String.self, forKey: .outingDepartureMessageTemplate)
        outingDepartureMessageSuffix = Self.normalizedOutingDepartureMessageSuffix(
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
        activityDisplayID = try container.decodeIfPresent(UInt32.self, forKey: .activityDisplayID)
        activeOutingEndDate = try container.decodeIfPresent(Date.self, forKey: .activeOutingEndDate)
        activeOutingDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .activeOutingDuration)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(language, forKey: .language)
        try container.encode(catName, forKey: .catName)
        try container.encode(catIdentifier, forKey: .catIdentifier)
        try container.encode(userSalutation, forKey: .userSalutation)
        try container.encode(selectedAssetPackID, forKey: .selectedAssetPackID)
        try container.encode(remindersEnabled, forKey: .remindersEnabled)
        try container.encode(waterReminderInterval, forKey: .waterReminderInterval)
        try container.encode(waterReminderMessageSuffix, forKey: .waterReminderMessageSuffix)
        try container.encode(movementReminderInterval, forKey: .movementReminderInterval)
        try container.encode(movementReminderMessageSuffix, forKey: .movementReminderMessageSuffix)
        try container.encode(customReminderEnabled, forKey: .customReminderEnabled)
        try container.encode(customReminderInterval, forKey: .customReminderInterval)
        try container.encode(customReminderMessageSuffix, forKey: .customReminderMessageSuffix)
        try container.encode(outingDepartureMessageSuffix, forKey: .outingDepartureMessageSuffix)
        try container.encode(defaultOutingDuration, forKey: .defaultOutingDuration)
        try container.encode(restDurationMinimum, forKey: .restDurationMinimum)
        try container.encode(restDurationMaximum, forKey: .restDurationMaximum)
        try container.encode(walkDurationMinimum, forKey: .walkDurationMinimum)
        try container.encode(walkDurationMaximum, forKey: .walkDurationMaximum)
        try container.encode(walkBaseSpeed, forKey: .walkBaseSpeed)
        try container.encode(catScalePercent, forKey: .catScalePercent)
        try container.encode(startPositionPercent, forKey: .startPositionPercent)
        try container.encode(catActivityScope, forKey: .catActivityScope)
        try container.encodeIfPresent(activityDisplayID, forKey: .activityDisplayID)
        try container.encodeIfPresent(activeOutingEndDate, forKey: .activeOutingEndDate)
        try container.encodeIfPresent(activeOutingDuration, forKey: .activeOutingDuration)
    }

    static func normalizedOutingDepartureMessageSuffix(
        _ rawValue: String?,
        language: AppLanguage,
        fallback: String
    ) -> String {
        guard var value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return fallback
        }

        let defaultTemplatePrefix: String
        switch language {
        case .chinese:
            defaultTemplatePrefix = "我出门啦，{salutation}"
        case .english:
            defaultTemplatePrefix = "I'm heading out, {salutation}. "
        }
        if value.hasPrefix(defaultTemplatePrefix) {
            value.removeFirst(defaultTemplatePrefix.count)
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : value
    }

    private static func normalizedAssetPackID(_ id: String) -> String {
        id == legacyDefaultAssetPackID ? defaultAssetPackID : id
    }

    private static func legacyDefaultCatName(for language: AppLanguage) -> String {
        switch language {
        case .chinese:
            return "栗子"
        case .english:
            return "Lizz"
        }
    }
}
