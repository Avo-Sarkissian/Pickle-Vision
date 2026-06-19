import Foundation

/// A capture format abstracted from `AVCaptureDevice.Format` so the selection
/// logic can be unit-tested without a camera.
public struct CameraFormatCandidate: Equatable {
    public let width: Int
    public let height: Int
    public let maxFrameRate: Double
    public let isBinned: Bool
    public let supportsMultiCam: Bool

    public init(width: Int, height: Int, maxFrameRate: Double,
                isBinned: Bool = false, supportsMultiCam: Bool = false) {
        self.width = width
        self.height = height
        self.maxFrameRate = maxFrameRate
        self.isBinned = isBinned
        self.supportsMultiCam = supportsMultiCam
    }
}

/// Picks the best capture format for ball tracking: closest to a target
/// resolution height, then the lowest native frame rate that still reaches the
/// cap (least thermal waste), preferring non-binned, higher-resolution formats.
public struct CameraFormatSelector {
    public let targetHeight: Int
    public let maxFrameRate: Double

    public init(targetHeight: Int = 1080, maxFrameRate: Double = 120) {
        self.targetHeight = targetHeight
        self.maxFrameRate = maxFrameRate
    }

    /// Returns the best candidate, or `nil` if none are usable. The comparator
    /// returns `true` when `a` should be ordered before `b` (i.e. `a` is the
    /// better choice).
    public func select(from candidates: [CameraFormatCandidate]) -> CameraFormatCandidate? {
        // AVFoundation reports some non-video / still formats with a 0 max frame
        // rate; ignore anything that cannot sustain at least 1 fps.
        let usable = candidates.filter { $0.maxFrameRate >= 1 }
        guard !usable.isEmpty else { return nil }
        return usable.min { a, b in
            let da = abs(a.height - targetHeight)
            let db = abs(b.height - targetHeight)
            if da != db { return da < db }                       // closest to target height

            let aMeets = a.maxFrameRate >= maxFrameRate
            let bMeets = b.maxFrameRate >= maxFrameRate
            if aMeets != bMeets { return aMeets }                 // meeting the cap wins
            if aMeets {                                           // both meet: least excess headroom
                if a.maxFrameRate != b.maxFrameRate { return a.maxFrameRate < b.maxFrameRate }
            } else {                                              // neither meets: highest available
                if a.maxFrameRate != b.maxFrameRate { return a.maxFrameRate > b.maxFrameRate }
            }
            if a.isBinned != b.isBinned { return !a.isBinned }    // prefer non-binned
            return a.width > b.width                              // prefer higher resolution
        }
    }
}
