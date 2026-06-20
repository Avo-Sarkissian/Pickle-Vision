import Foundation

/// Persists SessionClip sidecar records (one <id>.json per clip) in a directory.
/// The video file is stored alongside at `fileName`. Mirrors CalibrationStore.
public final class ClipStore {
    private let directory: URL
    private let fm = FileManager.default

    public init(directory: URL) { self.directory = directory }

    private func recordURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    public func fileURL(for clip: SessionClip) -> URL {
        directory.appendingPathComponent(clip.fileName)
    }

    public func save(_ clip: SessionClip) throws {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(clip)
        try data.write(to: recordURL(for: clip.id), options: .atomic)
    }

    public func loadAll() -> [SessionClip] {
        guard let entries = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        let decoder = JSONDecoder()
        return entries
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(SessionClip.self, from: Data(contentsOf: $0)) }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    public func clips(forCourt courtID: UUID) -> [SessionClip] {
        loadAll().filter { $0.courtID == courtID }
    }

    public func delete(id: UUID) throws {
        let rec = recordURL(for: id)
        if let clip = try? JSONDecoder().decode(SessionClip.self, from: Data(contentsOf: rec)) {
            try? fm.removeItem(at: fileURL(for: clip))   // remove the video too
        }
        if fm.fileExists(atPath: rec.path) { try fm.removeItem(at: rec) }
    }
}
