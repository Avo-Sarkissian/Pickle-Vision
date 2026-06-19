import XCTest
@testable import PickleVisionCore

final class ThermalPolicyTests: XCTestCase {
    private let policy = ThermalPolicy(baseFrameRate: 120)

    func test_nominal_and_fair_are_unrestricted() {
        for level in [ThermalLevel.nominal, .fair] {
            let r = policy.recommendation(for: level)
            XCTAssertFalse(r.shouldWarn)
            XCTAssertNil(r.frameRateCap)
        }
    }

    func test_serious_warns_and_caps_to_60() {
        let r = policy.recommendation(for: .serious)
        XCTAssertTrue(r.shouldWarn)
        XCTAssertEqual(r.frameRateCap, 60)
        XCTAssertNotNil(r.message)
    }

    func test_critical_caps_to_30() {
        XCTAssertEqual(policy.recommendation(for: .critical).frameRateCap, 30)
    }

    func test_shutdown_pauses_capture() {
        let r = policy.recommendation(for: .shutdown)
        XCTAssertEqual(r.frameRateCap, 0)
        XCTAssertTrue(r.shouldWarn)
    }

    func test_level_is_ordered() {
        XCTAssertTrue(ThermalLevel.nominal < ThermalLevel.critical)
    }
}
