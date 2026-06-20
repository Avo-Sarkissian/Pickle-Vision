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
    /// homography is non-invertible or the point maps onto the vanishing line
    /// (which would yield a non-finite coordinate).
    public func imagePoint(forCourt p: CGPoint) -> CGPoint? {
        guard let q = homography.inverse?.project(p), q.x.isFinite, q.y.isFinite else { return nil }
        return q
    }

    /// Minimum distance (feet) from `courtPoint` to any edge of the in-bounds polygon.
    /// Always >= 0. A point on a boundary edge returns 0.
    /// Used by LineJudge to determine whether a call falls within the uncertainty band.
    public func distanceToInBoundsBoundaryFeet(courtPoint p: CGPoint) -> Double {
        let poly = profile.inBoundsPolygon
        guard poly.count >= 2 else { return .infinity }
        var minDist = Double.infinity
        let n = poly.count
        for i in 0..<n {
            let a = poly[i], b = poly[(i + 1) % n]
            let d = Self.distanceToSegment(p, a, b)
            if d < minDist { minDist = d }
        }
        return minDist
    }

    /// Whether a court-space point lies inside the in-bounds polygon.
    /// Line-inclusive: a point exactly on a boundary line counts as in-bounds,
    /// matching pickleball's rule that a ball touching the line is "in".
    public func isInBounds(courtPoint p: CGPoint) -> Bool {
        Self.pointInPolygon(p, profile.inBoundsPolygon)
            || Self.isOnBoundary(p, profile.inBoundsPolygon)
    }

    /// Ray-casting point-in-polygon test (interior only; boundary handled by
    /// `isOnBoundary`).
    private static func pointInPolygon(_ p: CGPoint, _ poly: [CGPoint]) -> Bool {
        guard poly.count >= 3 else { return false }
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let pi = poly[i], pj = poly[j]
            // The `(pi.y > p.y) != (pj.y > p.y)` test excludes horizontal edges,
            // so `(pj.y - pi.y)` is never zero when the divide runs.
            if ((pi.y > p.y) != (pj.y > p.y)) &&
               (p.x < (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y) + pi.x) {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// Whether `p` lies on (within a tiny tolerance of) any edge of the polygon.
    private static func isOnBoundary(_ p: CGPoint, _ poly: [CGPoint], epsilon: Double = 1e-9) -> Bool {
        let n = poly.count
        guard n >= 2 else { return false }
        for i in 0..<n {
            let a = poly[i], b = poly[(i + 1) % n]
            if distanceToSegment(p, a, b) <= epsilon { return true }
        }
        return false
    }

    /// Euclidean distance from `p` to the segment `a`–`b`.
    private static func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        let px = Double(p.x - a.x), py = Double(p.y - a.y)
        let len2 = dx * dx + dy * dy
        if len2 == 0 { return (px * px + py * py).squareRoot() }
        var t = (px * dx + py * dy) / len2
        t = max(0, min(1, t))
        let cx = Double(a.x) + t * dx, cy = Double(a.y) + t * dy
        let ex = Double(p.x) - cx, ey = Double(p.y) - cy
        return (ex * ex + ey * ey).squareRoot()
    }
}
