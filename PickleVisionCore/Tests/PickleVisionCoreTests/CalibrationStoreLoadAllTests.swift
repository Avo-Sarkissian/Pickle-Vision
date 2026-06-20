import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class CalibrationStoreLoadAllTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pvcore-loadall-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func cal(_ venue: String, at t: TimeInterval) -> StoredCalibration {
        StoredCalibration(
            venueName: venue,
            layout: .regulationPickleball,
            imageCorners: [
                CodablePoint(x: 45, y: 172), CodablePoint(x: 275, y: 172),
                CodablePoint(x: 200, y: 48), CodablePoint(x: 120, y: 48),
            ],
            customDimensions: nil,
            savedAt: Date(timeIntervalSince1970: t)
        )
    }

    func test_empty_directory_returns_empty() {
        let store = CalibrationStore(directory: dir)
        XCTAssertEqual(store.loadAll().count, 0)
    }

    func test_missing_directory_returns_empty_not_throw() {
        let gone = dir.appendingPathComponent("does-not-exist")
        let store = CalibrationStore(directory: gone)
        XCTAssertEqual(store.loadAll(), [])
    }

    func test_returns_all_saved_newest_first() throws {
        let store = CalibrationStore(directory: dir)
        try store.save(cal("Old", at: 1_000))
        try store.save(cal("New", at: 9_000))
        try store.save(cal("Mid", at: 5_000))
        let all = store.loadAll()
        XCTAssertEqual(all.map(\.venueName), ["New", "Mid", "Old"])
    }

    func test_skips_corrupt_files() throws {
        let store = CalibrationStore(directory: dir)
        try store.save(cal("Good", at: 1_000))
        try Data("not json".utf8).write(to: dir.appendingPathComponent("junk.json"))
        let all = store.loadAll()
        XCTAssertEqual(all.map(\.venueName), ["Good"])
    }

    // MARK: - delete(venueName:) tests

    func test_delete_removes_file() throws {
        let store = CalibrationStore(directory: dir)
        try store.save(cal("DeleteMe", at: 1_000))
        XCTAssertEqual(store.loadAll().count, 1)
        try store.delete(venueName: "DeleteMe")
        XCTAssertEqual(store.loadAll().count, 0)
    }

    func test_delete_nonexistent_does_not_throw() {
        let store = CalibrationStore(directory: dir)
        XCTAssertNoThrow(try store.delete(venueName: "Ghost"))
    }

    func test_delete_leaves_other_courts_intact() throws {
        let store = CalibrationStore(directory: dir)
        try store.save(cal("Keep", at: 2_000))
        try store.save(cal("Remove", at: 1_000))
        try store.delete(venueName: "Remove")
        let all = store.loadAll()
        XCTAssertEqual(all.map(\.venueName), ["Keep"])
    }
}
