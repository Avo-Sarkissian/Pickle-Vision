import Foundation
import CoreGraphics

/// A recorded session clip. `courtID` is optional: a clip may be bound to the
/// court it was shot on, or be a quick capture with no court map yet (record-first
/// flow) - a court can be associated later, and the in/out pipeline only runs once
/// one is. The video file lives beside this record; later phases process the file
/// plus the court's CourtModel. Frame size is stored as scalars so the record is portable.
public struct SessionClip: Codable, Equatable, Identifiable {
    public var id: UUID
    /// The court this clip was shot on, or nil for a quick capture with no court map yet.
    public var courtID: UUID?
    public var fileName: String
    public var fps: Double
    public var frameWidth: Double
    public var frameHeight: Double
    public var recordedAt: Date

    public init(id: UUID = UUID(), courtID: UUID? = nil, fileName: String, fps: Double,
                frameWidth: Double, frameHeight: Double, recordedAt: Date) {
        self.id = id; self.courtID = courtID; self.fileName = fileName
        self.fps = fps; self.frameWidth = frameWidth; self.frameHeight = frameHeight
        self.recordedAt = recordedAt
    }

    public var frameSize: CGSize { CGSize(width: frameWidth, height: frameHeight) }
}
