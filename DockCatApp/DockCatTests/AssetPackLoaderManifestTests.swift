import Foundation
import XCTest
@testable import DockCat

final class AssetPackLoaderManifestTests: XCTestCase {
    func testRepairingDefaultManifestGeneratesValidWalkFramePaths() throws {
        let fileManager = FileManager.default
        let applicationSupportURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: applicationSupportURL) }

        let loader = AssetPackLoader(
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        )
        XCTAssertTrue(loader.prepareCustomPacksDirectory(refreshDefaultPackBackup: true))

        let manifestURL = applicationSupportURL
            .appendingPathComponent("DockCat/CatPacks/default-xiaohou/manifest.json")
        var manifestObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )
        manifestObject.removeValue(forKey: "app_icons")
        try JSONSerialization.data(withJSONObject: manifestObject).write(to: manifestURL, options: .atomic)

        XCTAssertTrue(loader.prepareCustomPacksDirectory())

        let manifest = try JSONDecoder().decode(AssetManifest.self, from: Data(contentsOf: manifestURL))
        let expectedFrames = (1 ... 24).map {
            String(format: "animations/walk-xiaohou/walk_%02d.png", $0)
        }
        XCTAssertEqual(manifest.animations.walk.frames, expectedFrames)
    }
}
