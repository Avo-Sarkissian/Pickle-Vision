import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class ClipStoreTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("pv-clips-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func clip(court: UUID, at t: TimeInterval) -> SessionClip {
        SessionClip(id: UUID(), courtID: court, fileName: "\(UUID().uuidString).mov",
                    fps: 120, frameWidth: 1920, frameHeight: 1080,
                    recordedAt: Date(timeIntervalSince1970: t))
    }

    func test_save_load_round_trips_newest_first() throws {
        let store = ClipStore(directory: dir)
        let court = UUID()
        try store.save(clip(court: court, at: 1_000))
        try store.save(clip(court: court, at: 9_000))
        let all = store.loadAll()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first?.recordedAt, Date(timeIntervalSince1970: 9_000))
    }

    func test_clips_for_court_filters_by_id() throws {
        let store = ClipStore(directory: dir)
        let a = UUID(); let b = UUID()
        try store.save(clip(court: a, at: 1))
        try store.save(clip(court: b, at: 2))
        XCTAssertEqual(store.clips(forCourt: a).count, 1)
    }

    func test_courtless_clip_round_trips_and_is_excluded_from_court_filter() throws {
        let store = ClipStore(directory: dir)
        let court = UUID()
        // A quick-capture clip with no court bound yet (record-first flow).
        let courtless = SessionClip(id: UUID(), courtID: nil, fileName: "\(UUID().uuidString).mov",
                                    fps: 60, frameWidth: 1920, frameHeight: 1080,
                                    recordedAt: Date(timeIntervalSince1970: 5_000))
        try store.save(courtless)
        try store.save(clip(court: court, at: 6_000))

        XCTAssertEqual(store.loadAll().count, 2)                 // both persist
        XCTAssertEqual(store.clips(forCourt: court).count, 1)    // court filter excludes the nil-court clip
        XCTAssertNotNil(store.loadAll().first { $0.courtID == nil })  // nil round-trips
    }

    func test_delete_removes_record() throws {
        let store = ClipStore(directory: dir)
        let c = clip(court: UUID(), at: 1)
        try store.save(c)
        try store.delete(id: c.id)
        XCTAssertTrue(store.loadAll().isEmpty)
    }
}
