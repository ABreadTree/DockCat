import Foundation

final class SpriteAnimator {
    private var timer: Timer?
    private var sequenceIndex = 0

    func start(animation: SpriteAnimation, onFrame: @escaping (Int) -> Void, onFinish: (() -> Void)? = nil) {
        stop()
        sequenceIndex = 0
        guard !animation.frames.isEmpty else { return }
        let frameIndices = AnimationFrameSequence.playbackIndices(frameCount: animation.frames.count)
        onFrame(frameIndices[0])
        timer = Timer.scheduledTimer(withTimeInterval: animation.frameDuration, repeats: true) { [weak self] timer in
            guard let self else { return }
            sequenceIndex += 1
            if sequenceIndex >= frameIndices.count {
                if animation.loops {
                    sequenceIndex = 0
                } else {
                    timer.invalidate()
                    onFinish?()
                    return
                }
            }
            onFrame(frameIndices[sequenceIndex])
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        sequenceIndex = 0
    }
}
