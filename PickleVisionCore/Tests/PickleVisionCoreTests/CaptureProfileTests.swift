import XCTest
@testable import PickleVisionCore

final class CaptureProfileTests: XCTestCase {
    func test_all_five_cases_exist_in_order_and_no_uhd240() {
        XCTAssertEqual(CaptureProfile.allCases,
                       [.auto, .uhd120, .fhd240, .fhd120, .batterySaver])
        // There is no 4K·240 on iPhone 16 Pro; assert no case advertises it.
        for p in CaptureProfile.allCases {
            XCTAssertFalse(p.targetHeight == 2160 && p.maxFrameRate == 240,
                           "No profile may be 4K·240")
        }
    }

    func test_selector_params_per_case() {
        XCTAssertEqual(CaptureProfile.auto.targetHeight, 1080)
        XCTAssertEqual(CaptureProfile.auto.maxFrameRate, 120)
        XCTAssertEqual(CaptureProfile.uhd120.targetHeight, 2160)
        XCTAssertEqual(CaptureProfile.uhd120.maxFrameRate, 120)
        XCTAssertEqual(CaptureProfile.fhd240.targetHeight, 1080)
        XCTAssertEqual(CaptureProfile.fhd240.maxFrameRate, 240)
        XCTAssertEqual(CaptureProfile.fhd120.targetHeight, 1080)
        XCTAssertEqual(CaptureProfile.fhd120.maxFrameRate, 120)
        XCTAssertEqual(CaptureProfile.batterySaver.targetHeight, 1080)
        XCTAssertEqual(CaptureProfile.batterySaver.maxFrameRate, 60)
    }

    func test_recommended_is_uhd120_only() {
        XCTAssertTrue(CaptureProfile.uhd120.isRecommended)
        XCTAssertEqual(CaptureProfile.uhd120.badge, .recommended)
        for p in CaptureProfile.allCases where p != .uhd120 {
            XCTAssertFalse(p.isRecommended)
        }
    }

    func test_default_is_fhd120_only() {
        XCTAssertTrue(CaptureProfile.fhd120.isDefault)
        XCTAssertEqual(CaptureProfile.fhd120.badge, .default)
        for p in CaptureProfile.allCases where p != .fhd120 {
            XCTAssertFalse(p.isDefault)
        }
    }

    func test_titles_and_subtitles_match_handoff_copy() {
        XCTAssertEqual(CaptureProfile.auto.displayTitle, "Auto")
        XCTAssertEqual(CaptureProfile.auto.subtitle, "Adapts to light, steps down on heat")
        XCTAssertEqual(CaptureProfile.uhd120.displayTitle, "4K · 120 fps")
        XCTAssertEqual(CaptureProfile.fhd240.displayTitle, "1080p · 240 fps")
        XCTAssertEqual(CaptureProfile.fhd240.subtitle, "fast, flat shots")
        XCTAssertEqual(CaptureProfile.fhd120.displayTitle, "1080p · 120 fps")
        XCTAssertEqual(CaptureProfile.batterySaver.displayTitle, "Battery saver")
        XCTAssertNil(CaptureProfile.uhd120.subtitle)
        XCTAssertNil(CaptureProfile.batterySaver.subtitle)
    }

    func test_formatSelector_reflects_target_and_rate() {
        let s = CaptureProfile.uhd120.formatSelector
        XCTAssertEqual(s.targetHeight, 2160)
        XCTAssertEqual(s.maxFrameRate, 120)
    }
}
