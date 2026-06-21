import CoreGraphics

// MARK: - JudgedBounce

/// A detected bounce paired with its court-space location and line call.
///
/// Physics note: `courtPoint` is derived by applying the ground-plane homography
/// to the bounce's image point. This mapping is only valid at the instant the ball
/// contacts the ground. Airborne ball positions suffer parallax error and must not
/// be mapped through the homography -- BounceDetector guarantees that only
/// ground-contact instants are surfaced as Bounce values.
public struct JudgedBounce: Equatable {
    /// The raw bounce event in image space.
    public var bounce: Bounce
    /// The court-space coordinate of the bounce (in feet, origin at court corner).
    /// Derived by projecting `bounce.imagePoint` through the court homography.
    public var courtPoint: CGPoint
    /// The line call for this bounce.
    public var call: LineCall

    public init(bounce: Bounce, courtPoint: CGPoint, call: LineCall) {
        self.bounce = bounce
        self.courtPoint = courtPoint
        self.call = call
    }
}

// MARK: - RefereeCore

/// The top-level facade that chains the CV pipeline into line calls.
///
/// Pipeline: BallObservation[] -> Tracker -> BallTrack -> BounceDetector -> [Bounce]
///   -> for each Bounce: LineJudge.call (maps through CourtModel once) -> JudgedBounce
///
/// Skips bounces for which LineJudge returns nil -- i.e. the bounce image point
/// projects to a non-finite court coordinate, which can happen near the homography's
/// projective vanishing line.
///
/// Phase B3 feeds detector output into evaluate(); Phase B5 measures calls against
/// tap-test ground truth.
public struct RefereeCore {
    public var tracker  = Tracker()
    public var detector = BounceDetector()
    public var judge    = LineJudge()

    public init(
        tracker:  Tracker        = Tracker(),
        detector: BounceDetector = BounceDetector(),
        judge:    LineJudge      = LineJudge()
    ) {
        self.tracker  = tracker
        self.detector = detector
        self.judge    = judge
    }

    /// Converts raw ball observations into a time-ordered list of judged bounces.
    ///
    /// - Parameters:
    ///   - observations: Raw BallObservation values from the vision pass (any order, any confidence).
    ///   - court: Calibrated court model used to map bounce image points to court coordinates.
    /// - Returns: Judged bounces in ascending time order. Bounces that fail to map to a
    ///   finite court coordinate, or for which LineJudge returns nil, are silently dropped.
    public func evaluate(_ observations: [BallObservation], court: CourtModel) -> [JudgedBounce] {
        let track   = tracker.track(observations)
        let bounces = detector.bounces(in: track)

        var result: [JudgedBounce] = []

        for bounce in bounces {
            // LineJudge maps the bounce once and hands back both the court point and the
            // call, so the stored courtPoint is exactly what the verdict was computed from.
            // A nil result means the bounce projected to a non-finite court coordinate
            // (near the homography's vanishing line) and is dropped.
            guard let judged = judge.call(bounce: bounce, court: court) else { continue }
            result.append(JudgedBounce(bounce: bounce, courtPoint: judged.courtPoint, call: judged.call))
        }

        // BounceDetector already yields events in time order (it walks samples
        // sequentially), but sort defensively to guarantee the contract.
        result.sort { $0.bounce.time < $1.bounce.time }

        return result
    }
}
