import CoreGraphics

// MARK: - LineVerdict

/// The outcome of a line call for a single bounce.
public enum LineVerdict: Equatable {
    /// The ball landed clearly in bounds.
    case `in`
    /// The ball landed clearly out of bounds.
    case out
    /// The bounce landed within the uncertainty band -- the call is indeterminate
    /// with single-camera geometry and should be treated as inconclusive.
    case tooCloseToCall
}

// MARK: - LineCall

/// A structured line call produced by LineJudge.
public struct LineCall: Equatable {
    /// The verdict for this bounce.
    public var verdict: LineVerdict
    /// Minimum distance (feet) from the bounce court point to the nearest in-bounds
    /// boundary edge. Zero if the bounce is on or very near a line.
    public var distanceToLineFeet: Double
    /// The uncertainty band (feet) that was in effect when this call was made.
    public var uncertaintyBandFeet: Double

    public init(verdict: LineVerdict, distanceToLineFeet: Double, uncertaintyBandFeet: Double) {
        self.verdict = verdict
        self.distanceToLineFeet = distanceToLineFeet
        self.uncertaintyBandFeet = uncertaintyBandFeet
    }
}

// MARK: - LineJudge

/// Determines whether a detected bounce is in, out, or too close to call.
///
/// Physics context: `courtPoint(forImage:)` applies the ground-plane homography. This
/// mapping is only valid at the instant the ball contacts the ground. Airborne ball
/// positions suffer parallax error and must NOT be passed through the homography.
/// BounceDetector handles this contract -- it provides exactly the ground-contact point.
///
/// Uncertainty band: the default 0.33 ft (~4 inches) is a placeholder that acknowledges
/// single-camera limitations. A principled band would propagate per-pixel measurement
/// error through the homography Jacobian to obtain a position-dependent uncertainty
/// ellipse in court space. That refinement is left for a future phase.
public struct LineJudge {
    /// Half-width of the uncertainty band (feet). Bounces whose nearest boundary
    /// distance falls at or below this threshold are reported as `tooCloseToCall`.
    /// Default ~4 inches -- a conservative placeholder for single-camera physics.
    public var uncertaintyBandFeet: Double

    public init(uncertaintyBandFeet: Double = 0.33) {
        self.uncertaintyBandFeet = uncertaintyBandFeet
    }

    /// Produces a line call for the given bounce using the supplied court model.
    ///
    /// Returns `nil` if the bounce image point maps to a non-finite court coordinate
    /// (this can happen when the homography maps near the projective vanishing line).
    public func call(bounce: Bounce, court: CourtModel) -> LineCall? {
        let cp = court.courtPoint(forImage: bounce.imagePoint)
        guard cp.x.isFinite && cp.y.isFinite else { return nil }

        let d = court.distanceToInBoundsBoundaryFeet(courtPoint: cp)
        let inside = court.isInBounds(courtPoint: cp)

        let verdict: LineVerdict
        if d <= uncertaintyBandFeet {
            verdict = .tooCloseToCall
        } else {
            verdict = inside ? .in : .out
        }

        return LineCall(verdict: verdict, distanceToLineFeet: d, uncertaintyBandFeet: uncertaintyBandFeet)
    }
}
