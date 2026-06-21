import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class TrajectoryFixtureTests: XCTestCase {

    private let corners = [
        CGPoint(x: 0.18, y: 0.82), CGPoint(x: 0.82, y: 0.82),
        CGPoint(x: 0.64, y: 0.30), CGPoint(x: 0.36, y: 0.30)
    ]

    // A vertical down-then-up parabola in image-y whose vertex (ball on the ground) sits
    // at (peakX, peakY) at time `tv`. Sampled finely (0.02 s) over a tight window around
    // the vertex, with the vertex strictly between two samples, so (a) the velocity sign
    // flip is geometric (not float noise) and (b) the detected bounce lands ~0.004 image-y
    // from the true vertex -- close enough that it maps back essentially onto the labeled
    // court point. (A coarse 0.1 s step leaves the detected point ~0.1 image-y low, which
    // maps several feet off and is why a verdict-only test never caught it.)
    private func bounceDrop(peakX: Double, peakY: Double, atTime tv: TimeInterval) -> [BallObservation] {
        var obs: [BallObservation] = []
        for i in 0...20 {
            let t = (tv - 0.21) + Double(i) * 0.02   // vertex tv is midway between i=10 and i=11
            let y = peakY - 40.0 * (t - tv) * (t - tv)
            obs.append(BallObservation(imagePoint: CGPoint(x: peakX, y: y), time: t, confidence: 1.0))
        }
        return obs
    }

    func test_fixture_courtModel_builds() {
        let fixture = TrajectoryFixture(
            name: "empty", imageCorners: corners, layout: .regulationPickleball,
            customDimensions: nil, observations: [], reference: []
        )
        XCTAssertNotNil(fixture.courtModel())
    }

    func test_fixture_codable_round_trips() throws {
        let fixture = TrajectoryFixture(
            name: "rt", imageCorners: corners, layout: .regulationPickleball,
            customDimensions: nil,
            observations: [BallObservation(imagePoint: CGPoint(x: 0.5, y: 0.5), time: 0.1, confidence: 0.8)],
            reference: [ReferenceBounce(courtPoint: CGPoint(x: 10, y: 22), expectedVerdict: .in, time: 0.45)]
        )
        let data = try JSONEncoder().encode(fixture)
        let decoded = try JSONDecoder().decode(TrajectoryFixture.self, from: data)
        XCTAssertEqual(decoded, fixture)
    }

    func test_fixture_decodes_from_handwritten_json() throws {
        // Proves a fixture can be authored by hand in readable JSON (string-coded verdicts).
        let json = """
        {
          "name": "hand-written",
          "imageCorners": [[0.18,0.82],[0.82,0.82],[0.64,0.30],[0.36,0.30]],
          "layout": "regulationPickleball",
          "observations": [
            {"imagePoint":[0.5,0.5],"time":0.0,"confidence":0.9}
          ],
          "reference": [
            {"courtPoint":[10,22],"expectedVerdict":"in","time":0.45}
          ]
        }
        """
        let fixture = try JSONDecoder().decode(TrajectoryFixture.self, from: Data(json.utf8))
        XCTAssertEqual(fixture.name, "hand-written")
        XCTAssertEqual(fixture.layout, .regulationPickleball)
        XCTAssertEqual(fixture.observations.count, 1)
        XCTAssertEqual(fixture.reference.first?.expectedVerdict, .in)
    }

    // End-to-end: a two-bounce in/out fixture replayed through RefereeCore then scored by
    // EvalRunner yields a clean report (both bounces matched + called correctly).
    func test_two_bounce_fixture_replays_to_a_clean_report() throws {
        let gen = CalibrationDraft(corners: corners, layout: .regulationPickleball).courtModel()!
        let insidePt  = CGPoint(x: 10, y: 22)
        let outsidePt = CGPoint(x: -3, y: 22)
        let insideImg  = try XCTUnwrap(gen.imagePoint(forCourt: insidePt))
        let outsideImg = try XCTUnwrap(gen.imagePoint(forCourt: outsidePt))

        let observations =
            bounceDrop(peakX: insideImg.x,  peakY: insideImg.y,  atTime: 0.45) +
            bounceDrop(peakX: outsideImg.x, peakY: outsideImg.y, atTime: 1.95)

        let fixture = TrajectoryFixture(
            name: "two-bounce in/out",
            imageCorners: corners, layout: .regulationPickleball, customDimensions: nil,
            observations: observations,
            reference: [
                ReferenceBounce(courtPoint: insidePt,  expectedVerdict: .in,  time: 0.45),
                ReferenceBounce(courtPoint: outsidePt, expectedVerdict: .out, time: 1.95)
            ]
        )

        let model = try XCTUnwrap(fixture.courtModel())
        let predicted = RefereeCore().evaluate(fixture.observations, court: model)
        let report = EvalRunner().evaluate(predicted: predicted, reference: fixture.reference)

        XCTAssertEqual(report.matchedCount, 2)
        XCTAssertEqual(report.falsePositives, 0)
        XCTAssertEqual(report.falseNegatives, 0)
        XCTAssertEqual(report.clearCallCorrect, 2)
        XCTAssertEqual(report.clearCallWrong, 0)
        XCTAssertEqual(report.clearCallAccuracy, 1.0, accuracy: 1e-9)
        XCTAssertLessThan(report.maxCourtErrorFeet, 1.0)   // fine sampling -> small mapping error
    }
}
