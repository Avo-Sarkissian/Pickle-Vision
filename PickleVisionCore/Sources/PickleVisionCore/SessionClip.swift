import Foundation
import CoreGraphics

/// A recorded session clip, bound to the court it was shot on. The video file
/// lives beside this record; later phases process the file plus the court's
/// CourtModel. Frame size is stored as scalars so the record is portable.
public struct SessionClip: Codable, Equatable, Identifiable {
    public var id: UUID
    public var courtID: UUID
    public var fileName: String
    public var fps: Double
    public var frameWidth: Double
    public var frameHeight: Double
    public var recordedAt: Date

    public init(id: UUID = UUID(), courtID: UUID, fileName: String, fps: Double,
                frameWidth: Double, frameHeight: Double, recordedAt: Date) {
        self.id = id; self.courtID = courtID; self.fileName = fileName
        self.fps = fps; self.frameWidth = frameWidth; self.frameHeight = frameHeight
        self.recordedAt = recordedAt
    }

    public var frameSize: CGSize { CGSize(width: frameWidth, height: frameHeight) }
}
