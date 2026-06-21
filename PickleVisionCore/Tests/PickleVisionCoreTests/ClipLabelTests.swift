import XCTest
import CoreGraphics
import Foundation
@testable import PickleVisionCore

final class ClipLabelTests: XCTestCase {

    func test_clip_label_codable_round_trips() throws {
        let label = ClipLabel(
            clipID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            reference: [
                ReferenceBounce(courtPoint: CGPoint(x: 10, y: 22), expectedVerdict: .in, time: 1.2),
                ReferenceBounce(courtPoint: CGPoint(x: 0.1, y: 22), expectedVerdict: .tooCloseToCall, time: 3.4)
            ]
        )
        let data = try JSONEncoder().encode(label)
        let decoded = try JSONDecoder().decode(ClipLabel.self, from: data)
        XCTAssertEqual(decoded, label)
    }

    func test_clip_label_decodes_from_handwritten_json() throws {
        // The sidecar a human would write next to a recorded clip after the tap-test.
        let json = """
        {
          "clipID": "11111111-2222-3333-4444-555555555555",
          "reference": [
            {"courtPoint":[10,22],"expectedVerdict":"in","time":1.2},
            {"courtPoint":[-2,22],"expectedVerdict":"out","time":2.5}
          ]
        }
        """
        let label = try JSONDecoder().decode(ClipLabel.self, from: Data(json.utf8))
        XCTAssertEqual(label.clipID.uuidString, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(label.reference.count, 2)
        XCTAssertEqual(label.reference[1].expectedVerdict, .out)
    }
}
