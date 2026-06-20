//
//  PickleVisionTests.swift
//  PickleVisionTests
//
//  App-layer unit tests (Swift Testing). The pure logic lives in
//  PickleVisionCore (run via `swift test`); these cover the app-only
//  view-model / persistence glue that the core suite can't reach.
//

import Testing
import Foundation
import CoreGraphics
@testable import PickleVision
import PickleVisionCore

@MainActor
struct CalibrationModelTests {
    private func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory
            .appendingPathComponent("pv-app-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @Test func save_persists_a_calibration() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let m = CalibrationModel(camera: CameraService(),
                                 flow: CalibrationFlow(step: .verify),
                                 venueName: "Court A",
                                 storeDirectory: dir)
        #expect(m.save())
        let all = CalibrationStore(directory: dir).loadAll()
        #expect(all.count == 1)
        #expect(all.first?.venueName == "Court A")
    }

    // I8: re-calibrating and renaming overwrites the same record (by id) instead
    // of leaving an orphaned duplicate under the old name.
    @Test func recal_rename_overwrites_same_record() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = CalibrationStore(directory: dir)

        let original = CalibrationModel(camera: CameraService(),
                                        flow: CalibrationFlow(step: .verify),
                                        venueName: "Old Name",
                                        storeDirectory: dir)
        #expect(original.save())
        let saved = try #require(store.loadAll().first)

        let recal = CalibrationModel(
            camera: CameraService(),
            flow: .forExpressReCal(corners: CalibrationDraft.defaultCorners(),
                                   layout: .regulationPickleball,
                                   customDimensions: nil),
            venueName: "New Name",
            editingID: saved.id,
            storeDirectory: dir
        )
        #expect(recal.save())

        let all = store.loadAll()
        #expect(all.count == 1)                     // no orphaned duplicate
        #expect(all.first?.venueName == "New Name")
        #expect(all.first?.id == saved.id)
    }

    // I4: a custom layout without dimensions is rejected on save (not silently
    // persisted as a regulation court).
    @Test func save_custom_without_dimensions_fails() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        var flow = CalibrationFlow(step: .verify)
        flow.layout = .custom
        flow.customDimensions = nil
        let m = CalibrationModel(camera: CameraService(), flow: flow,
                                 venueName: "Custom", storeDirectory: dir)
        #expect(m.save() == false)
        #expect(m.saveError != nil)
        #expect(CalibrationStore(directory: dir).loadAll().isEmpty)
    }

    @Test func tap_test_result_reads_in_bounds_near_centre() throws {
        let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let m = CalibrationModel(camera: CameraService(),
                                 flow: CalibrationFlow(step: .verify),
                                 venueName: "C", storeDirectory: dir)
        m.flow.tapPoint = CGPoint(x: 0.5, y: 0.6)   // inside the default quad
        let result = try #require(m.tapTestResult())
        #expect(result.inBounds)
    }
}

struct CaptureProfileStoreTests {
    @Test func persists_and_restores_selected_profile() throws {
        let name = "pv-test-" + UUID().uuidString
        let suite = try #require(UserDefaults(suiteName: name))
        defer { suite.removePersistentDomain(forName: name) }

        let a = CaptureProfileStore(defaults: suite)
        #expect(a.profile == .auto)                 // default
        a.profile = .fhd240
        let b = CaptureProfileStore(defaults: suite)
        #expect(b.profile == .fhd240)               // restored from the same suite
    }
}
