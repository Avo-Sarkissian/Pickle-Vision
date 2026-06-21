import CoreGraphics
import Foundation

// MARK: - Public types

/// A single ball detection from a vision pass.
/// Image point is normalized [0,1] to the frame dimensions.
/// Codable so trajectory fixtures (Phase B5) can be stored/loaded as JSON.
public struct BallObservation: Equatable, Codable {
    public var imagePoint: CGPoint
    public var time: TimeInterval
    public var confidence: Double

    public init(imagePoint: CGPoint, time: TimeInterval, confidence: Double) {
        self.imagePoint = imagePoint
        self.time = time
        self.confidence = confidence
    }

    public static func == (lhs: BallObservation, rhs: BallObservation) -> Bool {
        lhs.imagePoint == rhs.imagePoint &&
        lhs.time == rhs.time &&
        lhs.confidence == rhs.confidence
    }
}

/// One sample in a smoothed, velocity-annotated ball track.
/// Velocity is in image units per second (central finite difference).
public struct TrackSample: Equatable {
    public var imagePoint: CGPoint
    public var time: TimeInterval
    public var velocity: CGVector   // image units per second

    public init(imagePoint: CGPoint, time: TimeInterval, velocity: CGVector) {
        self.imagePoint = imagePoint
        self.time = time
        self.velocity = velocity
    }

    public static func == (lhs: TrackSample, rhs: TrackSample) -> Bool {
        lhs.imagePoint == rhs.imagePoint &&
        lhs.time == rhs.time &&
        lhs.velocity.dx == rhs.velocity.dx &&
        lhs.velocity.dy == rhs.velocity.dy
    }
}

/// An ordered sequence of track samples derived from raw observations.
public struct BallTrack: Equatable {
    public var samples: [TrackSample]

    public init(samples: [TrackSample]) {
        self.samples = samples
    }
}

// MARK: - Tracker

/// Converts raw BallObservations into a cleaned, velocity-annotated BallTrack.
///
/// Pipeline (all steps deterministic, no ML):
///  1. Drop observations below minConfidence.
///  2. Sort by time ascending.
///  3. Reject single-point spatial outliers: a point whose Euclidean jump from
///     both its immediate neighbours exceeds outlierFactor * local median step.
///  4. Fill gaps up to maxGap by linear interpolation (preserves cadence).
///  5. Compute velocity by central finite difference; endpoints use one-sided
///     difference. Units are image units per second.
///
/// Physics note: image points are normalized [0,1]. An airborne ball does NOT
/// map correctly to court space through the ground homography (parallax error).
/// Only the bounce point (ball touching the ground) maps validly. Bounce
/// detection happens in image space; court mapping happens only at the detected
/// bounce.
public struct Tracker {
    /// Observations with confidence below this value are discarded.
    public var minConfidence: Double = 0.3
    /// Gaps larger than this (in seconds) are not interpolated.
    public var maxGap: TimeInterval = 0.1
    /// An observation is an outlier when its jump from both neighbours exceeds
    /// this multiple of the median inter-observation step. Internal tuning constant,
    /// not a public knob: the spec exposes only minConfidence and maxGap.
    private let outlierFactor: Double = 3.0

    public init(
        minConfidence: Double = 0.3,
        maxGap: TimeInterval = 0.1
    ) {
        self.minConfidence = minConfidence
        self.maxGap = maxGap
    }

    /// Produces a BallTrack from unordered, possibly noisy observations.
    public func track(_ observations: [BallObservation]) -> BallTrack {
        // Step 1: drop low-confidence detections
        var pts = observations.filter { $0.confidence >= minConfidence }

        // Step 2: sort by time
        pts.sort { $0.time < $1.time }

        // Step 3: reject single-point spatial outliers
        pts = rejectOutliers(pts)

        // Step 4: gap fill by linear interpolation
        pts = fillGaps(pts)

        // Step 5: compute velocity by central finite difference
        let samples = computeVelocities(pts)

        return BallTrack(samples: samples)
    }

    // MARK: - Private helpers

    /// Returns Euclidean distance between two image points.
    private func dist(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Removes observations that are spatial outliers from both their neighbours.
    ///
    /// Algorithm: for each interior point i, compute:
    ///   - jumpPrev = dist(pts[i], pts[i-1])
    ///   - jumpNext = dist(pts[i], pts[i+1])
    ///   - localMedianStep = median of all inter-observation steps that do NOT
    ///     involve point i (steps i-1 and i are excluded). This gives a robust
    ///     baseline that is not inflated by the candidate's own large jumps.
    /// If jumpPrev > outlierFactor * localMedianStep AND
    ///    jumpNext > outlierFactor * localMedianStep, reject pts[i].
    /// Endpoints are never rejected (they have only one neighbour).
    /// When fewer than 2 non-candidate steps exist the global median is used.
    private func rejectOutliers(_ pts: [BallObservation]) -> [BallObservation] {
        guard pts.count >= 3 else { return pts }

        // Pre-compute all consecutive step distances
        var allSteps: [Double] = []
        for i in 0 ..< pts.count - 1 {
            allSteps.append(dist(pts[i].imagePoint, pts[i + 1].imagePoint))
        }

        var result: [BallObservation] = []
        for i in pts.indices {
            if i == 0 || i == pts.count - 1 {
                // Endpoints are never rejected
                result.append(pts[i])
                continue
            }

            // Steps adjacent to point i are indices i-1 and i (in allSteps).
            // Exclude them to get an unbiased local baseline.
            var referenceSteps: [Double] = []
            for s in allSteps.indices {
                if s != i - 1 && s != i {
                    referenceSteps.append(allSteps[s])
                }
            }

            // Fall back to global median when no reference steps are available
            let baselineSteps = referenceSteps.isEmpty ? allSteps : referenceSteps
            let localMedianStep = median(baselineSteps)

            guard localMedianStep > 0 else {
                result.append(pts[i])
                continue
            }

            let threshold = outlierFactor * localMedianStep
            let jumpPrev = dist(pts[i].imagePoint, pts[i - 1].imagePoint)
            let jumpNext = dist(pts[i].imagePoint, pts[i + 1].imagePoint)
            if jumpPrev > threshold && jumpNext > threshold {
                // Both jumps are huge relative to the local median step - outlier
                continue
            }
            result.append(pts[i])
        }
        return result
    }

    /// Median of a non-empty array. Sorts a copy.
    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        } else {
            return sorted[mid]
        }
    }

    /// Linearly interpolates between consecutive observations whose gap is in
    /// (0, maxGap]. Gaps larger than maxGap are left as-is (track discontinuity).
    ///
    /// The interpolation cadence matches the local average step inferred from
    /// the adjacent observations. When there is no clear cadence (fewer than 2
    /// surrounding samples), gaps are bridged with a single midpoint.
    private func fillGaps(_ pts: [BallObservation]) -> [BallObservation] {
        guard pts.count >= 2 else { return pts }

        // Estimate a nominal time step from the median inter-sample interval
        var intervals: [TimeInterval] = []
        for i in 0 ..< pts.count - 1 {
            intervals.append(pts[i + 1].time - pts[i].time)
        }
        let nominalStep = median(intervals)
        guard nominalStep > 0 else { return pts }

        var result: [BallObservation] = [pts[0]]

        for i in 0 ..< pts.count - 1 {
            let a = pts[i]
            let b = pts[i + 1]
            let gap = b.time - a.time

            // Only bridge a gap that is clearly wider than the local cadence (>1.5x the
            // nominal step, so a slightly irregular interval is left untouched) and still
            // within maxGap (a larger gap is a genuine track discontinuity, not a dropout).
            if gap > nominalStep * 1.5 && gap <= maxGap {
                // Insert interpolated points to fill the gap
                let steps = max(1, Int(round(gap / nominalStep))) - 1
                for s in 1 ... steps {
                    let t = Double(s) / Double(steps + 1)
                    let interp = BallObservation(
                        imagePoint: CGPoint(
                            x: a.imagePoint.x + t * (b.imagePoint.x - a.imagePoint.x),
                            y: a.imagePoint.y + t * (b.imagePoint.y - a.imagePoint.y)
                        ),
                        time: a.time + t * gap,
                        // Interpolated points are inferred, not observed: take the more
                        // conservative (lower) confidence of the two flanking detections.
                        confidence: min(a.confidence, b.confidence)
                    )
                    result.append(interp)
                }
            }
            result.append(b)
        }

        return result
    }

    /// Computes velocity for each observation using central finite differences.
    /// Interior points: v = (next - prev) / (t_next - t_prev)
    /// Endpoints: one-sided difference with the adjacent neighbour.
    private func computeVelocities(_ pts: [BallObservation]) -> [TrackSample] {
        guard !pts.isEmpty else { return [] }

        if pts.count == 1 {
            return [TrackSample(
                imagePoint: pts[0].imagePoint,
                time: pts[0].time,
                velocity: CGVector(dx: 0, dy: 0)
            )]
        }

        var samples: [TrackSample] = []
        for i in pts.indices {
            let velocity: CGVector
            if i == 0 {
                // Forward difference
                let dt = pts[1].time - pts[0].time
                velocity = dt > 0
                    ? CGVector(
                        dx: (pts[1].imagePoint.x - pts[0].imagePoint.x) / dt,
                        dy: (pts[1].imagePoint.y - pts[0].imagePoint.y) / dt
                      )
                    : CGVector(dx: 0, dy: 0)
            } else if i == pts.count - 1 {
                // Backward difference
                let dt = pts[i].time - pts[i - 1].time
                velocity = dt > 0
                    ? CGVector(
                        dx: (pts[i].imagePoint.x - pts[i - 1].imagePoint.x) / dt,
                        dy: (pts[i].imagePoint.y - pts[i - 1].imagePoint.y) / dt
                      )
                    : CGVector(dx: 0, dy: 0)
            } else {
                // Central difference
                let dt = pts[i + 1].time - pts[i - 1].time
                velocity = dt > 0
                    ? CGVector(
                        dx: (pts[i + 1].imagePoint.x - pts[i - 1].imagePoint.x) / dt,
                        dy: (pts[i + 1].imagePoint.y - pts[i - 1].imagePoint.y) / dt
                      )
                    : CGVector(dx: 0, dy: 0)
            }
            samples.append(TrackSample(
                imagePoint: pts[i].imagePoint,
                time: pts[i].time,
                velocity: velocity
            ))
        }
        return samples
    }
}
