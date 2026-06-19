import XCTest
@testable import PickleVisionCore

final class CameraFormatSelectorTests: XCTestCase {
    private let selector = CameraFormatSelector(targetHeight: 1080, maxFrameRate: 120)

    func test_prefers_1080p_at_the_cap_over_4k_and_720p() {
        let candidates = [
            CameraFormatCandidate(width: 3840, height: 2160, maxFrameRate: 60),
            CameraFormatCandidate(width: 1920, height: 1080, maxFrameRate: 120),
            CameraFormatCandidate(width: 1920, height: 1080, maxFrameRate: 240),
            CameraFormatCandidate(width: 1280, height: 720,  maxFrameRate: 240),
        ]
        // 1080p that meets the 120 cap with the least excess headroom.
        XCTAssertEqual(selector.select(from: candidates),
                       CameraFormatCandidate(width: 1920, height: 1080, maxFrameRate: 120))
    }

    func test_when_nothing_meets_the_cap_it_takes_the_highest_rate_at_target_height() {
        let candidates = [
            CameraFormatCandidate(width: 1920, height: 1080, maxFrameRate: 30),
            CameraFormatCandidate(width: 1920, height: 1080, maxFrameRate: 60),
        ]
        XCTAssertEqual(selector.select(from: candidates)?.maxFrameRate, 60)
    }

    func test_falls_back_to_closest_height_when_no_1080p() {
        let candidates = [
            CameraFormatCandidate(width: 3840, height: 2160, maxFrameRate: 120),
            CameraFormatCandidate(width: 1280, height: 720,  maxFrameRate: 120),
        ]
        // 720 is closer to 1080 than 2160 is.
        XCTAssertEqual(selector.select(from: candidates)?.height, 720)
    }

    func test_empty_returns_nil() {
        XCTAssertNil(selector.select(from: []))
    }
}
