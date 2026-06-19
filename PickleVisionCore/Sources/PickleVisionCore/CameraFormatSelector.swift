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
    /// returns `true` when `a` is a better choice than `b`.
    public func select(from candidates: [CameraFormatCandidate]) -> CameraFormatCandidate? {
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
