import XCTest
@testable import PickleVisionCore

final class SmokeTests: XCTestCase {
    func test_version_isPresent() {
        XCTAssertEqual(PickleVisionCore.version, "0.1.0")
    }
}
