import CryptoKit
import Foundation

struct GiftCodeEntry: Equatable {
    var hashParts: [String]
    var collectableIDParts: [String]

    var hash: String {
        hashParts.joined()
    }

    var collectableID: String {
        collectableIDParts.joined()
    }
}

struct GiftCodeRedeemer {
    private static let pepperParts = ["Dock", "Cat", ":gift-code:", "v1", ":standard-collectables"]
    private static let requiredCodeLength = 6

    private let entriesByHash: [String: String]
    private let hiddenEntriesByCode: [String: String]

    init(
        entries: [GiftCodeEntry] = GiftCodeRedeemer.standardEntries,
        hiddenEntriesByCode: [String: String] = GiftCodeRedeemer.hiddenEntriesByCode
    ) {
        entriesByHash = Dictionary(
            entries.map { ($0.hash, $0.collectableID) },
            uniquingKeysWith: { first, _ in first }
        )
        self.hiddenEntriesByCode = hiddenEntriesByCode
    }

    func collectableID(for rawCode: String, in catalog: OutingCatalog) -> String? {
        guard let normalizedAnyLengthCode = Self.normalizedAnyLengthCode(rawCode) else { return nil }
        if let collectableID = hiddenEntriesByCode[normalizedAnyLengthCode],
           catalog.collectables.contains(where: { $0.id == collectableID }) {
            return collectableID
        }

        guard let normalizedCode = Self.normalizedCode(normalizedAnyLengthCode) else { return nil }
        let hash = Self.hash(normalizedCode: normalizedCode)
        guard let collectableID = entriesByHash[hash],
              catalog.collectables.contains(where: { $0.id == collectableID && $0.isStandardRarity })
        else {
            return nil
        }
        return collectableID
    }

    static func normalizedCode(_ rawCode: String) -> String? {
        guard let normalized = normalizedAnyLengthCode(rawCode) else { return nil }
        return normalized.count == requiredCodeLength ? normalized : nil
    }

    static func normalizedAnyLengthCode(_ rawCode: String) -> String? {
        let normalized = rawCode
            .uppercased()
            .filter { !$0.isWhitespace }
        return normalized.isEmpty ? nil : normalized
    }

    static func hash(normalizedCode: String) -> String {
        let source = "\(pepperParts.joined()):\(normalizedCode)"
        let digest = SHA256.hash(data: Data(source.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static let standardEntries: [GiftCodeEntry] = [
        GiftCodeEntry(hashParts: ["ff3cc5ecb1249807", "03b47dc2223f0661", "47a6c22196eee0a1", "31e7410e2cb02a73"], collectableIDParts: ["le", "af"]),
        GiftCodeEntry(hashParts: ["9d4f6a1ada0b0382", "0770cdc11be34ae6", "5d98e8bfad92447f", "12955243648d6c07"], collectableIDParts: ["pe", "bble"]),
        GiftCodeEntry(hashParts: ["28ccd9ba4d6011ed", "89b2c7de55aae700", "cd9fe14ca077f62a", "97184c96712fcea4"], collectableIDParts: ["small_", "feather"]),
        GiftCodeEntry(hashParts: ["49fba80fa6d17ffd", "2e2e1b72f2bb1489", "fee98b4d7af125b3", "c76e677746b7edaa"], collectableIDParts: ["pretty_", "button"]),
        GiftCodeEntry(hashParts: ["18649238ce2e20db", "1017877494c0b63b", "e869fdfa032c4c93", "252c3ed4eeb44f73"], collectableIDParts: ["small_", "pinecone"]),
        GiftCodeEntry(hashParts: ["578292210e1ad5b1", "572edda6036a26c3", "fc263c964bc59b05", "32032cf6de8fab43"], collectableIDParts: ["tw", "ig"]),
        GiftCodeEntry(hashParts: ["b3da4f11cc6d6bff", "fd9210ce45490410", "c0e7b2c96b5718f9", "46ecd97f5ee77312"], collectableIDParts: ["fly", "er"]),
        GiftCodeEntry(hashParts: ["40471ba6b003ae0f", "5d6c2b99eff648e2", "7037777ad9913b4d", "946b4d319008d32c"], collectableIDParts: ["colorful_", "bottle_cap"]),
        GiftCodeEntry(hashParts: ["a9d2a521e2b828be", "0013da92ac4eb5b5", "089f176c0d30f649", "07deef83257cf875"], collectableIDParts: ["shell_", "chip"]),
        GiftCodeEntry(hashParts: ["8160b487a6ff6a51", "379062394af0b755", "f69816f73750b2e9", "b745972157d8eef8"], collectableIDParts: ["mar", "ble"]),
        GiftCodeEntry(hashParts: ["6b72191d09f16911", "295d87d94df8051e", "5587eee61719ec8a", "02de13f5f6efd93a"], collectableIDParts: ["patterned_", "ribbon"]),
        GiftCodeEntry(hashParts: ["86c74544851623af", "588ddcfb321de703", "013544287697afa7", "90ceb3fd64284236"], collectableIDParts: ["wooden_", "whistle"]),
        GiftCodeEntry(hashParts: ["10c819f36ab56e15", "effeb07c30433d4c", "91d98a8a859dde15", "87b6725c980a6918"], collectableIDParts: ["dried_", "flower"]),
        GiftCodeEntry(hashParts: ["39335d96f2386ea8", "3f59bf458adbe447", "6d133ec2f8fb6955", "816442e684b8b92f"], collectableIDParts: ["toy_", "fish"]),
        GiftCodeEntry(hashParts: ["e1007e49bf135a05", "d06462a735058b5b", "4475c56c36e81477", "9043103eb9db3014"], collectableIDParts: ["engraved_", "bell"]),
        GiftCodeEntry(hashParts: ["3e73eb8ea57f54ad", "dc95d16fea3ee550", "e81be6981983dfd1", "98c7d7fb27236aa7"], collectableIDParts: ["pin", "wheel"]),
        GiftCodeEntry(hashParts: ["0dd437e5b879464f", "9fb1833ae4642084", "e84cda6be074a423", "5c6d48adec81a2be"], collectableIDParts: ["paw_", "badge"]),
        GiftCodeEntry(hashParts: ["0ecb5eeda82e2d5f", "67f6661925991a9f", "a0fdcd2f9b69247a", "dcf0ab7afe6cf577"], collectableIDParts: ["tiny_", "bottle"]),
        GiftCodeEntry(hashParts: ["6cc139a38f582f3e", "d5f51729de60e4e8", "8f4cb0908a3300ba", "1b2fecf522b6164a"], collectableIDParts: ["crescent_", "pendant"]),
        GiftCodeEntry(hashParts: ["eee5d727e37aef15", "d6b98eb80670c7dc", "73b113e5af3609f8", "22e0d912509b04bd"], collectableIDParts: ["alpaca_", "plush"]),
        GiftCodeEntry(hashParts: ["d2f25ccf8c3cccd0", "5eb80a01e21bb324", "21c60ffbf676c53f", "490dd63b8c2ac9c0"], collectableIDParts: ["pearl_", "hairpin"]),
        GiftCodeEntry(hashParts: ["1d406253503e44fd", "4d2a18c0c57ea8cc", "f61fd2fc0da9824c", "e95dd53e4cad866e"], collectableIDParts: ["com", "pass"]),
        GiftCodeEntry(hashParts: ["37dcc83ebe733216", "159fd033b14df702", "2a45783acd768c2f", "78f44442396384f5"], collectableIDParts: ["tiny_", "porcelain_cat"]),
        GiftCodeEntry(hashParts: ["02184a237b6c167b", "084eda15755b2711", "6b8dbc2c045ac717", "3a3e8b8d3422e566"], collectableIDParts: ["chipmunk_", "plush"]),
        GiftCodeEntry(hashParts: ["1a85ae5c00b6f045", "75767d81ed4fd1e3", "57408dad5413221d", "22719d13863fcd29"], collectableIDParts: ["wa", "nd"]),
        GiftCodeEntry(hashParts: ["6db577a43decaf8b", "0fad52f81a0246b9", "0b20a07e2280679c", "993757dbd7957bda"], collectableIDParts: ["firefly_", "amber"])
    ]

    private static let hiddenEntriesByCode: [String: String] = [
        "CRYSTAL": "crystal_petal",
        "TWILIGHT": "twilight_petal",
        "STARRY": "starry_petal"
    ]
}
