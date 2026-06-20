import Foundation
import CoreGraphics

/// A `Codable` 2D point (CGPoint persistence kept explicit and portable).
public struct CodablePoint: Codable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public init(_ p: CGPoint) { self.x = Double(p.x); self.y = Double(p.y) }
    public var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

/// A persisted court calibration. Identity is a stable `id` (the on-disk
/// filename), decoupled from the user-editable `venueName` — so two courts can
/// share a display name without clobbering each other, and renaming on re-cal
/// overwrites the same record instead of orphaning the old file. Stores the
/// tapped image corners and layout, not the homography (recomputed on load).
public struct StoredCalibration: Codable, Equatable, Identifiable {
    public var id: UUID
    public var venueName: String
    public var layout: CourtLayout
    public var imageCorners: [CodablePoint]   // [nearLeft, nearRight, farRight, farLeft]
    public var customDimensions: CustomDimensions?
    public var savedAt: Date

    public init(id: UUID = UUID(), venueName: String, layout: CourtLayout,
                imageCorners: [CodablePoint], customDimensions: CustomDimensions?, savedAt: Date) {
        self.id = id
        self.venueName = venueName
        self.layout = layout
        self.imageCorners = imageCorners
        self.customDimensions = customDimensions
        self.savedAt = savedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, venueName, layout, imageCorners, customDimensions, savedAt
    }

    /// Decodes a stored calibration, generating an `id` for legacy records that
    /// predate the id field (they migrate to an id-named file on first `loadAll`).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.venueName = try c.decode(String.self, forKey: .venueName)
        self.layout = try c.decode(CourtLayout.self, forKey: .layout)
        self.imageCorners = try c.decode([CodablePoint].self, forKey: .imageCorners)
        self.customDimensions = try c.decodeIfPresent(CustomDimensions.self, forKey: .customDimensions)
        self.savedAt = try c.decode(Date.self, forKey: .savedAt)
    }
}

/// Saves and restores `StoredCalibration`s as JSON files (one per `id`) in a
/// directory, and rebuilds a `CourtModel` from one.
public final class CalibrationStore {
    /// Reasons a save can be rejected before anything is written to disk.
    public enum StoreError: LocalizedError, Equatable {
        case invalidCornerCount
        case missingCustomDimensions
        case invalidCustomDimensions

        public var errorDescription: String? {
            switch self {
            case .invalidCornerCount:
                return "This calibration doesn't have all four court corners yet."
            case .missingCustomDimensions:
                return "A custom court needs its width, length, and kitchen set."
            case .invalidCustomDimensions:
                return "Those custom dimensions aren't valid (the kitchen must be less than half the length)."
            }
        }
    }

    private let directory: URL
    private let fileManager = FileManager.default

    public init(directory: URL) {
        self.directory = directory
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    /// Validates and persists a calibration under its `id`. Throws `StoreError`
    /// (before writing) for an incomplete corner set or an invalid custom court.
    public func save(_ calibration: StoredCalibration) throws {
        guard calibration.imageCorners.count == 4 else { throw StoreError.invalidCornerCount }
        if calibration.layout == .custom {
            guard let dims = calibration.customDimensions else { throw StoreError.missingCustomDimensions }
            guard dims.isValid else { throw StoreError.invalidCustomDimensions }
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(calibration)
        try data.write(to: url(for: calibration.id), options: .atomic)
    }

    /// The calibration with this id, or `nil` if absent/unreadable.
    public func load(id: UUID) -> StoredCalibration? {
        guard let data = try? Data(contentsOf: url(for: id)) else { return nil }
        return try? JSONDecoder().decode(StoredCalibration.self, from: data)
    }

    /// First saved calibration with this venue name (display lookup / back-compat).
    public func load(venueName: String) throws -> StoredCalibration? {
        loadAll().first { $0.venueName == venueName }
    }

    /// All saved calibrations, newest first by `savedAt`. Skips unreadable or
    /// non-JSON entries so one corrupt file can't hide the rest, and migrates
    /// legacy (venue-named / id-less) files to the stable `<id>.json` name.
    /// Returns `[]` if the directory doesn't exist yet.
    public func loadAll() -> [StoredCalibration] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        var result: [StoredCalibration] = []
        for u in entries where u.pathExtension == "json" {
            guard let data = try? Data(contentsOf: u),
                  let cal = try? decoder.decode(StoredCalibration.self, from: data) else { continue }
            let canonical = url(for: cal.id)
            if u.lastPathComponent != canonical.lastPathComponent {
                // Migrate legacy file to its id-named home, then drop the old one.
                if let migrated = try? encoder.encode(cal),
                   (try? migrated.write(to: canonical, options: .atomic)) != nil {
                    try? fileManager.removeItem(at: u)
                }
            }
            result.append(cal)
        }
        return result.sorted { $0.savedAt > $1.savedAt }
    }

    /// Removes the calibration with this id (idempotent).
    public func delete(id: UUID) throws {
        let u = url(for: id)
        guard fileManager.fileExists(atPath: u.path) else { return }
        try fileManager.removeItem(at: u)
    }

    /// Removes every saved calibration with this venue name (back-compat helper).
    public func delete(venueName: String) throws {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        let decoder = JSONDecoder()
        for u in entries where u.pathExtension == "json" {
            guard let data = try? Data(contentsOf: u),
                  let cal = try? decoder.decode(StoredCalibration.self, from: data) else { continue }
            if cal.venueName == venueName { try fileManager.removeItem(at: u) }
        }
    }

    /// Recomputes a live `CourtModel` from a stored calibration, or `nil` if the
    /// corners are missing/degenerate. Uses no instance state — exposed statically
    /// so views can build it once without standing up a store.
    public static func courtModel(from calibration: StoredCalibration) -> CourtModel? {
        guard calibration.imageCorners.count == 4 else { return nil }
        let profile = CourtProfile.make(layout: calibration.layout,
                                        custom: calibration.customDimensions)
        let image = calibration.imageCorners.map { $0.cgPoint }
        guard let h = Homography(source: image, destination: profile.calibrationCorners) else {
            return nil
        }
        return CourtModel(profile: profile, homography: h)
    }

    public func courtModel(from calibration: StoredCalibration) -> CourtModel? {
        Self.courtModel(from: calibration)
    }
}
