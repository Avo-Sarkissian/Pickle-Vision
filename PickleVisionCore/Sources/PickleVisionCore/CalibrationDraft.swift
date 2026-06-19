import CoreGraphics
import Foundation

/// An in-progress manual calibration: the four court corners (normalized image
/// coords, order [nearLeft, nearRight, farRight, farLeft]) and the chosen layout.
public struct CalibrationDraft {
    public var corners: [CGPoint]
    public var layout: CourtLayout
    public var customDimensions: CustomDimensions?

    public init(corners: [CGPoint] = [], layout: CourtLayout, customDimensions: CustomDimensions? = nil) {
        self.corners = corners
        self.layout = layout
        self.customDimensions = customDimensions
    }

    public var isComplete: Bool { corners.count == 4 }

    /// Builds the calibrated `CourtModel` (normalized-image → court homography),
    /// or `nil` if the four corners aren't set or are degenerate.
    public func courtModel() -> CourtModel? {
        guard isComplete else { return nil }
        let profile = CourtProfile.make(layout: layout, custom: customDimensions)
        guard let h = Homography(source: corners, destination: profile.calibrationCorners) else {
            return nil
        }
        return CourtModel(profile: profile, homography: h)
    }

    /// Index of the handle nearest to `p` within `radius` (view-space points), or nil.
    public func nearestCornerIndex(toView p: CGPoint, handles: [CGPoint], within radius: CGFloat) -> Int? {
        var bestIndex: Int?
        var bestDist = radius
        for (i, h) in handles.enumerated() {
            let d = hypot(h.x - p.x, h.y - p.y)
            if d <= bestDist { bestDist = d; bestIndex = i }
        }
        return bestIndex
    }

    /// A starting quad (normalized) the user nudges onto the real lines.
    public static func defaultCorners() -> [CGPoint] {
        [CGPoint(x: 0.20, y: 0.85), CGPoint(x: 0.80, y: 0.85),
         CGPoint(x: 0.65, y: 0.35), CGPoint(x: 0.35, y: 0.35)]
    }
}
