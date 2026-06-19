import CoreGraphics

/// The calibrated court — the single interface every later Pickle Vision phase
/// consumes. Wraps an image→court homography plus the court's real-world geometry.
public struct CourtModel {
    public let profile: CourtProfile
    /// Maps image (pixel) coordinates to court (feet) coordinates.
    public let homography: Homography

    public init(profile: CourtProfile, homography: Homography) {
        self.profile = profile
        self.homography = homography
    }

    /// Court (feet) coordinate for a point in the image.
    public func courtPoint(forImage p: CGPoint) -> CGPoint {
        homography.project(p)
    }

    /// Image (pixel) coordinate for a point on the court, or `nil` if the
    /// homography is non-invertible.
    public func imagePoint(forCourt p: CGPoint) -> CGPoint? {
        homography.inverse?.project(p)
    }

    /// Whether a court-space point lies inside the in-bounds polygon.
    public func isInBounds(courtPoint p: CGPoint) -> Bool {
        Self.pointInPolygon(p, profile.inBoundsPolygon)
    }

    /// Ray-casting point-in-polygon test.
    private static func pointInPolygon(_ p: CGPoint, _ poly: [CGPoint]) -> Bool {
        guard poly.count >= 3 else { return false }
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let pi = poly[i], pj = poly[j]
            if ((pi.y > p.y) != (pj.y > p.y)) &&
               (p.x < (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y) + pi.x) {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}
