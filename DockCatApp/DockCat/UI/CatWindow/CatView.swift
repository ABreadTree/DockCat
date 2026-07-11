import AppKit

final class CatView: NSView {
    private let imageLayer = CALayer()

    var image: NSImage? {
        didSet { updateImageContents() }
    }

    var isMirrored = false {
        didSet { updateImageTransform() }
    }

    var onMouseDown: ((NSEvent) -> Void)?
    var onMouseDragged: ((NSEvent) -> Void)?
    var onMouseUp: ((NSEvent) -> Void)?
    var onRightMouseDown: ((NSEvent) -> Void)?

    override var isFlipped: Bool { true }

    var hasImageLayerContents: Bool {
        imageLayer.contents != nil
    }

    var imageLayerFrame: CGRect {
        imageLayer.frame
    }

    var imageLayerTransform: CGAffineTransform {
        imageLayer.affineTransform()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureImageLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureImageLayer()
    }

    override func layout() {
        super.layout()
        updateImageLayerFrame()
    }

    private func configureImageLayer() {
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        imageLayer.contentsGravity = .resize
        imageLayer.magnificationFilter = .linear
        imageLayer.minificationFilter = .linear
        imageLayer.actions = [
            "contents": NSNull(),
            "frame": NSNull(),
            "transform": NSNull(),
        ]
        layer?.addSublayer(imageLayer)
        updateImageTransform()
    }

    private func updateImageContents() {
        guard let image else {
            imageLayer.contents = nil
            return
        }
        var proposedRect = NSRect(origin: .zero, size: image.size)
        imageLayer.contents = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        updateImageLayerFrame()
    }

    private func updateImageLayerFrame() {
        guard let image else {
            imageLayer.frame = .zero
            return
        }
        imageLayer.frame = bottomAlignedAspectFitRect(imageSize: image.size, in: bounds)
        imageLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private func updateImageTransform() {
        imageLayer.setAffineTransform(CGAffineTransform(scaleX: isMirrored ? -1 : 1, y: -1))
    }

    private func bottomAlignedAspectFitRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(event)
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?(event)
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp?(event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightMouseDown?(event)
    }
}
