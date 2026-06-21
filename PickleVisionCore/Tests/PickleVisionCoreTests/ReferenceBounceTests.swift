import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class ReferenceBounceTests: XCTestCase {

    func test_reference_bounce_construction() {
        let r = ReferenceBounce(courtPoint: CGPoint(x: 10, y: 22), expectedVerdict: .in, time: 1.5)
        XCTAssertEqual(r.courtPoint, CGPoint(x: 10, y: 22))
        XCTAssertEqual(r.expectedVerdict, .in)
        XCTAssertEqual(r.time, 1.5, accuracy: 1e-9)
    }

    func test_reference_bounce_codable_round_trips() throws {
        let original = ReferenceBounce(courtPoint: CGPoint(x: -2.5, y: 21.0), expectedVerdict: .out, time: 3.25)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReferenceBounce.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_line_verdict_codable_round_trips() throws {
        for verdict in [LineVerdict.in, .out, .tooCloseToCall] {
            let data = try JSONEncoder().encode(verdict)
            let decoded = try JSONDecoder().decode(LineVerdict.self, from: data)
            XCTAssertEqual(decoded, verdict)
        }
    }
}
