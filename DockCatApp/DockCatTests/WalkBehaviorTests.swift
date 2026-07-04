import CoreGraphics
import XCTest
@testable import DockCat

final class WalkBehaviorTests: XCTestCase {
    func testPingPongFrameSequenceAvoidsHardLoopJump() {
        XCTAssertEqual(AnimationFrameSequence.pingPongIndices(frameCount: 4), [0, 1, 2, 3, 2, 1])
        XCTAssertEqual(AnimationFrameSequence.pingPongIndices(frameCount: 2), [0, 1])
        XCTAssertEqual(AnimationFrameSequence.pingPongIndices(frameCount: 1), [0])
        XCTAssertEqual(AnimationFrameSequence.pingPongIndices(frameCount: 0), [])
    }

    func testWalkMotionTurnsWithShortPauseAtBoundary() {
        let model = WalkMotionModel(boundaryPause: 0.35, bobAmplitude: 1.2)
        let state = WalkMotionState(x: 98, direction: 1, pauseRemaining: 0, phase: 0)

        let step = model.advance(state: state, baseSpeed: 60, range: 0 ... 100, deltaTime: 1)

        XCTAssertEqual(step.state.x, 100, accuracy: 0.0001)
        XCTAssertEqual(step.state.direction, -1, accuracy: 0.0001)
        XCTAssertEqual(step.state.pauseRemaining, 0.35, accuracy: 0.0001)
        XCTAssertTrue(step.isPaused)
    }

    func testWalkMotionCountsDownPauseBeforeMoving() {
        let model = WalkMotionModel(boundaryPause: 0.35, bobAmplitude: 1.2)
        let state = WalkMotionState(x: 50, direction: -1, pauseRemaining: 0.2, phase: 0)

        let step = model.advance(state: state, baseSpeed: 60, range: 0 ... 100, deltaTime: 0.1)

        XCTAssertEqual(step.state.x, 50, accuracy: 0.0001)
        XCTAssertEqual(step.state.direction, -1, accuracy: 0.0001)
        XCTAssertEqual(step.state.pauseRemaining, 0.1, accuracy: 0.0001)
        XCTAssertEqual(step.visualYOffset, 0, accuracy: 0.0001)
        XCTAssertTrue(step.isPaused)
    }

    func testWalkMotionVariesSpeedAndKeepsBobSubtle() {
        let model = WalkMotionModel(boundaryPause: 0.35, bobAmplitude: 1.2)
        let state = WalkMotionState(x: 50, direction: 1, pauseRemaining: 0, phase: Double.pi / 2)

        let step = model.advance(state: state, baseSpeed: 60, range: 0 ... 100, deltaTime: 1.0 / 30.0)

        XCTAssertGreaterThan(step.state.x, 50)
        XCTAssertLessThanOrEqual(step.state.x, 50 + 60 / 30 * 1.13)
        XCTAssertLessThanOrEqual(abs(step.visualYOffset), 1.2)
        XCTAssertFalse(step.isPaused)
    }
}
