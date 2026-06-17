import XCTest
@testable import KalshiKit

final class TriggerLogicTests: XCTestCase {

    // MARK: - .above

    func testAboveCrossingFires() {
        XCTAssertTrue(triggerShouldFire(previousCents: 48, currentCents: 52, thresholdCents: 50, direction: .above))
    }

    func testAboveAlreadyAboveDoesNotFire() {
        // 52 -> 55: both ticks are already past the threshold; no crossing.
        XCTAssertFalse(triggerShouldFire(previousCents: 52, currentCents: 55, thresholdCents: 50, direction: .above))
    }

    func testAboveBaselineDoesNotFire() {
        XCTAssertFalse(triggerShouldFire(previousCents: nil, currentCents: 60, thresholdCents: 50, direction: .above))
        XCTAssertEqual(
            evaluateTrigger(previousCents: nil, currentCents: 60, thresholdCents: 50, direction: .above),
            .armedBaseline
        )
    }

    func testAboveExactTouchFires() {
        // 49 -> 50: reaching the threshold exactly counts as crossing (>=).
        XCTAssertTrue(triggerShouldFire(previousCents: 49, currentCents: 50, thresholdCents: 50, direction: .above))
    }

    // MARK: - .below

    func testBelowCrossingFires() {
        XCTAssertTrue(triggerShouldFire(previousCents: 52, currentCents: 48, thresholdCents: 50, direction: .below))
    }

    func testBelowAlreadyBelowDoesNotFire() {
        // 48 -> 45: both ticks already past the threshold; no crossing.
        XCTAssertFalse(triggerShouldFire(previousCents: 48, currentCents: 45, thresholdCents: 50, direction: .below))
    }

    func testBelowBaselineDoesNotFire() {
        XCTAssertFalse(triggerShouldFire(previousCents: nil, currentCents: 40, thresholdCents: 50, direction: .below))
        XCTAssertEqual(
            evaluateTrigger(previousCents: nil, currentCents: 40, thresholdCents: 50, direction: .below),
            .armedBaseline
        )
    }

    func testBelowExactTouchFires() {
        // 51 -> 50: reaching the threshold exactly counts as crossing (<=).
        XCTAssertTrue(triggerShouldFire(previousCents: 51, currentCents: 50, thresholdCents: 50, direction: .below))
    }

    // MARK: - Re-cross

    func testAboveCanFireAgainAfterRecross() {
        // 48 -> 52: fires.
        XCTAssertTrue(triggerShouldFire(previousCents: 48, currentCents: 52, thresholdCents: 50, direction: .above))
        // 52 -> 48: moves back below; no fire.
        XCTAssertFalse(triggerShouldFire(previousCents: 52, currentCents: 48, thresholdCents: 50, direction: .above))
        // 48 -> 53: re-crosses upward; fires again.
        XCTAssertTrue(triggerShouldFire(previousCents: 48, currentCents: 53, thresholdCents: 50, direction: .above))
    }

    // MARK: - Baseline already past

    func testAboveBaselineAlreadyPastDoesNotFire() {
        // previous=60, current=61, threshold=50: never crossed live; no fire.
        XCTAssertFalse(triggerShouldFire(previousCents: 60, currentCents: 61, thresholdCents: 50, direction: .above))
        XCTAssertEqual(
            evaluateTrigger(previousCents: 60, currentCents: 61, thresholdCents: 50, direction: .above),
            .holding
        )
    }

    // MARK: - Evaluation cases

    func testEvaluationFireCase() {
        XCTAssertEqual(
            evaluateTrigger(previousCents: 48, currentCents: 52, thresholdCents: 50, direction: .above),
            .fire
        )
    }
}
