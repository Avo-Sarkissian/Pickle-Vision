import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class CalibrationStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pvcore-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
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

    func test_unsafe_venue_name_is_sanitized() throws {
        let store = CalibrationStore(directory: dir)
        var cal = sample()
        cal.venueName = "../../etc/passwd"
        try store.save(cal)
        // The file lands inside `dir`, with no path separators in its name.
        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(contents.count, 1)
        XCTAssertFalse(contents[0].contains("/"))
        // It still round-trips by the original venue name (re-sanitized identically).
        let loaded = try XCTUnwrap(store.load(venueName: "../../etc/passwd"))
        XCTAssertEqual(loaded, cal)
    }

    func test_rebuilds_court_model_from_stored_calibration() throws {
        let store = CalibrationStore(directory: dir)
        let model = try XCTUnwrap(store.courtModel(from: sample()))
        let origin = model.courtPoint(forImage: CGPoint(x: 45, y: 172))
        XCTAssertEqual(origin.x, 0, accuracy: 1e-6)
        XCTAssertEqual(origin.y, 0, accuracy: 1e-6)
        XCTAssertEqual(model.profile.layout, .regulationPickleball)
    }

    func test_load_by_id_round_trips() throws {
        let store = CalibrationStore(directory: dir)
        let cal = sample()
        try store.save(cal)
        let loaded = try XCTUnwrap(store.load(id: cal.id))
        XCTAssertEqual(loaded, cal)
    }

    // M5/I4: invalid records are rejected on the way in, before any file is written.
    func test_save_rejects_wrong_corner_count() {
        let store = CalibrationStore(directory: dir)
        var cal = sample()
        cal.imageCorners = Array(cal.imageCorners.prefix(3))
        XCTAssertThrowsError(try store.save(cal)) {
            XCTAssertEqual($0 as? CalibrationStore.StoreError, .invalidCornerCount)
        }
    }

    func test_save_rejects_custom_without_dimensions() {
        let store = CalibrationStore(directory: dir)
        var cal = sample()
        cal.layout = .custom
        cal.customDimensions = nil
        XCTAssertThrowsError(try store.save(cal)) {
            XCTAssertEqual($0 as? CalibrationStore.StoreError, .missingCustomDimensions)
        }
    }

    func test_save_rejects_invalid_custom_dimensions() {
        let store = CalibrationStore(directory: dir)
        var cal = sample()
        cal.layout = .custom
        cal.customDimensions = CustomDimensions(widthFeet: 18, lengthFeet: 40, nonVolleyZoneFeet: 25)
        XCTAssertThrowsError(try store.save(cal)) {
            XCTAssertEqual($0 as? CalibrationStore.StoreError, .invalidCustomDimensions)
        }
    }
}
