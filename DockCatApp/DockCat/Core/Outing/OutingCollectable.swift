import Foundation

struct OutingCollectable: Codable, Equatable, Identifiable {
    var id: String
    var chineseName: String
    var englishName: String
    var rarity: Int
    var author: String
    var imagePath: String
    var isRetired: Bool
    var isSpecialDisplayRarity: Bool

    var rarityLabel: String {
        isSpecialDisplayRarity ? "☀️" : "\(rarity)"
    }

    var raritySortRank: Int {
        isSpecialDisplayRarity ? 6 : rarity
    }

    var isStandardRarity: Bool {
        (1 ... 5).contains(rarity)
    }

    var isRewardEligible: Bool {
        isStandardRarity && !isRetired
    }

    enum CodingKeys: String, CodingKey {
        case id
        case chineseName = "chinese_name"
        case englishName = "english_name"
        case rarity
        case author
        case imagePath = "image_path"
        case isRetired = "retired"
    }

    init(
        id: String,
        chineseName: String,
        englishName: String,
        rarity: Int,
        author: String,
        imagePath: String,
        isRetired: Bool = false,
        isSpecialDisplayRarity: Bool = false
    ) {
        self.id = id
        self.chineseName = chineseName
        self.englishName = englishName
        self.rarity = rarity
        self.author = author
        self.imagePath = imagePath
        self.isRetired = isRetired
        self.isSpecialDisplayRarity = isSpecialDisplayRarity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        chineseName = try container.decode(String.self, forKey: .chineseName)
        englishName = try container.decode(String.self, forKey: .englishName)
        if let decodedRarity = try? container.decode(Int.self, forKey: .rarity) {
            rarity = decodedRarity
            isSpecialDisplayRarity = false
        } else {
            let decodedRarity = try container.decode(String.self, forKey: .rarity)
            guard decodedRarity.uppercased() == "X" else {
                throw DecodingError.dataCorruptedError(
                    forKey: .rarity,
                    in: container,
                    debugDescription: "Collectable rarity must be 1...5 or X."
                )
            }
            rarity = 0
            isSpecialDisplayRarity = true
        }
        author = try container.decode(String.self, forKey: .author)
        imagePath = try container.decode(String.self, forKey: .imagePath)
        isRetired = try container.decodeIfPresent(Bool.self, forKey: .isRetired) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(chineseName, forKey: .chineseName)
        try container.encode(englishName, forKey: .englishName)
        if isSpecialDisplayRarity {
            try container.encode("X", forKey: .rarity)
        } else {
            try container.encode(rarity, forKey: .rarity)
        }
        try container.encode(author, forKey: .author)
        try container.encode(imagePath, forKey: .imagePath)
        if isRetired {
            try container.encode(isRetired, forKey: .isRetired)
        }
    }
}
