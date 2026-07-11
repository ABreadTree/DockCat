import AppKit
import XCTest
@testable import DockCat

@MainActor
final class CatViewRenderingTests: XCTestCase {
    func testImageUsesBottomAlignedLayerContents() {
        let view = CatView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let image = NSImage(size: NSSize(width: 200, height: 100), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            return true
        }

        view.image = image
        view.layoutSubtreeIfNeeded()

        XCTAssertTrue(view.wantsLayer)
        XCTAssertTrue(view.hasImageLayerContents)
        XCTAssertEqual(view.imageLayerFrame, NSRect(x: 0, y: 50, width: 100, height: 50))
        XCTAssertEqual(view.imageLayerTransform.d, -1, accuracy: 0.001)
    }

    func testMirroringUsesImageLayerTransform() {
        let view = CatView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.image = NSImage(size: NSSize(width: 100, height: 100), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            return true
        }

        view.isMirrored = true

        XCTAssertEqual(view.imageLayerTransform.a, -1, accuracy: 0.001)
        XCTAssertEqual(view.imageLayerTransform.d, -1, accuracy: 0.001)
    }
}
