import CoreGraphics
import Foundation

struct WalkMotionState: Equatable {
    var x: CGFloat
    var direction: CGFloat
    var pauseRemaining: TimeInterval
    var phase: Double
}

struct WalkMotionStep: Equatable {
    var state: WalkMotionState
    var visualYOffset: CGFloat
    var isPaused: Bool
}

struct WalkMotionModel {
    var boundaryPause: TimeInterval = 0.28

    func advance(
        state: WalkMotionState,
        baseSpeed: CGFloat,
        range: ClosedRange<CGFloat>,
        deltaTime: TimeInterval
    ) -> WalkMotionStep {
        var next = normalized(state)
        let interval = max(0, deltaTime)

        if next.pauseRemaining > 0 {
            next.pauseRemaining = max(0, next.pauseRemaining - interval)
            return WalkMotionStep(state: next, visualYOffset: 0, isPaused: true)
        }

        let phase = next.phase + interval * 2.0 * Double.pi * 1.7
        let speedMultiplier = 1.0 + 0.12 * sin(phase)
        let distance = baseSpeed * CGFloat(speedMultiplier) * CGFloat(interval)
        next.x += next.direction * distance
        next.phase = phase

        if next.x <= range.lowerBound {
            next.x = range.lowerBound
            next.direction = 1
            next.pauseRemaining = boundaryPause
            return WalkMotionStep(state: next, visualYOffset: 0, isPaused: true)
        }

        if next.x >= range.upperBound {
            next.x = range.upperBound
            next.direction = -1
            next.pauseRemaining = boundaryPause
            return WalkMotionStep(state: next, visualYOffset: 0, isPaused: true)
        }

        return WalkMotionStep(state: next, visualYOffset: 0, isPaused: false)
    }

    private func normalized(_ state: WalkMotionState) -> WalkMotionState {
        var state = state
        state.direction = state.direction < 0 ? -1 : 1
        state.pauseRemaining = max(0, state.pauseRemaining)
        return state
    }
}
