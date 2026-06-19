import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class CalibrationStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pvcore-tests-" + UUID().uuidString)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func sample() -> StoredCalibration {
        StoredCalibration(
            venueName: "Home Court",
            layout: .regulationPickleball,
            imageCorners: [
                CodablePoint(x: 45, y: 172), CodablePoint(x: 275, y: 172),
                CodablePoint(x: 200, y: 48), CodablePoint(x: 120, y: 48),
            ],
            customDimensions: nil,
            savedAt: Date(timeIntervalSince1970: 1_000_000)
        )
    }

    func test_save_then_load_round_trips() throws {
        let store = CalibrationStore(directory: dir)
        let cal = sample()
        try store.save(cal)
        let loaded = try XCTUnwrap(store.load(venueName: "Home Court"))
        XCTAssertEqual(loaded, cal)
    }

    func test_load_missing_returns_nil() throws {
        let store = CalibrationStore(directory: dir)
        XCTAssertNil(try store.load(venueName: "Nowhere"))
    }

    func test_rebuilds_court_model_from_stored_calibration() throws {
        let store = CalibrationStore(directory: dir)
        let model = try XCTUnwrap(store.courtModel(from: sample()))
        let origin = model.courtPoint(forImage: CGPoint(x: 45, y: 172))
        XCTAssertEqual(origin.x, 0, accuracy: 1e-6)
        XCTAssertEqual(origin.y, 0, accuracy: 1e-6)
        XCTAssertEqual(model.profile.layout, .regulationPickleball)
    }
}
