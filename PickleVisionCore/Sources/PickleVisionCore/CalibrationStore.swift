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

/// A persisted court calibration. Stores the tapped image corners and the
/// layout, not the homography — the homography is recomputed on load, which
/// keeps the format tiny and re-derives from source of truth.
public struct StoredCalibration: Codable, Equatable {
    public var venueName: String
    public var layout: CourtLayout
    public var imageCorners: [CodablePoint]   // [nearLeft, nearRight, farRight, farLeft]
    public var customDimensions: CustomDimensions?
    public var savedAt: Date

    public init(venueName: String, layout: CourtLayout, imageCorners: [CodablePoint],
                customDimensions: CustomDimensions?, savedAt: Date) {
        self.venueName = venueName
        self.layout = layout
        self.imageCorners = imageCorners
        self.customDimensions = customDimensions
        self.savedAt = savedAt
    }
}

/// Saves and restores `StoredCalibration`s as JSON files in a directory, and
/// rebuilds a `CourtModel` from one.
public final class CalibrationStore {
    private let directory: URL
    private let fileManager = FileManager.default

    public init(directory: URL) {
        self.directory = directory
    }

    /// Maps a venue name to a safe filename, neutralizing path separators,
    /// `..` traversal, and other filesystem-special characters by keeping only
    /// letters, numbers, spaces, dashes, and underscores.
    private func url(forVenue venue: String) -> URL {
        var safe = String(venue.map { ch in
            (ch.isLetter || ch.isNumber || ch == " " || ch == "-" || ch == "_") ? ch : "_"
        })
        if safe.isEmpty { safe = "venue" }
        return directory.appendingPathComponent("\(safe).json")
    }

    public func save(_ calibration: StoredCalibration) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(calibration)
        try data.write(to: url(forVenue: calibration.venueName), options: .atomic)
    }

    public func load(venueName: String) throws -> StoredCalibration? {
        let u = url(forVenue: venueName)
        guard fileManager.fileExists(atPath: u.path) else { return nil }
        let data = try Data(contentsOf: u)
        return try JSONDecoder().decode(StoredCalibration.self, from: data)
    }

    /// All saved calibrations, newest first by `savedAt`. Skips unreadable or
    /// non-JSON entries so one corrupt file can't hide the rest. Returns `[]`
    /// if the directory doesn't exist yet.
    public func loadAll() -> [StoredCalibration] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let decoder = JSONDecoder()
        let calibrations = entries
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> StoredCalibration? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(StoredCalibration.self, from: data)
            }
        return calibrations.sorted { $0.savedAt > $1.savedAt }
    }

    /// Removes the persisted calibration for the given venue name. No-ops if the
    /// file does not exist (idempotent). Throws only on genuine filesystem errors.
    public func delete(venueName: String) throws {
        let u = url(forVenue: venueName)
        guard fileManager.fileExists(atPath: u.path) else { return }
        try fileManager.removeItem(at: u)
    }

    /// Recomputes a live `CourtModel` from a stored calibration, or `nil` if
    /// the corners are degenerate.
    public func courtModel(from calibration: StoredCalibration) -> CourtModel? {
        let profile = CourtProfile.make(layout: calibration.layout,
                                        custom: calibration.customDimensions)
        let image = calibration.imageCorners.map { $0.cgPoint }
        guard let h = Homography(source: image, destination: profile.calibrationCorners) else {
            return nil
        }
        return CourtModel(profile: profile, homography: h)
    }
}
