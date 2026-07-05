import Foundation

enum AnimationFrameSequence {
    static func playbackIndices(frameCount: Int) -> [Int] {
        guard frameCount < 12 else {
            return Array(0..<frameCount)
        }
        return pingPongIndices(frameCount: frameCount)
    }

    static func pingPongIndices(frameCount: Int) -> [Int] {
        guard frameCount > 1 else {
            return frameCount == 1 ? [0] : []
        }
        guard frameCount > 2 else {
            return Array(0..<frameCount)
        }
        return Array(0..<frameCount) + Array((1..<(frameCount - 1)).reversed())
    }
}
