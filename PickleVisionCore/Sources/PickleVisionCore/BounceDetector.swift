import CoreGraphics
import Foundation

// MARK: - Bounce

/// A detected bounce event in image space.
///
/// Physics caveat: this is the ground-contact instant. An airborne ball does NOT
/// map correctly to court space through the ground homography (parallax error).
/// Only the bounce point (ball touching the ground) maps validly. Court mapping
/// must therefore be applied at the detected bounce point, not to airborne samples.
public struct Bounce: Equatable {
    /// Normalized [0,1] image point of the bounce, interpolated to the zero-crossing.
    public var imagePoint: CGPoint
    /// Interpolated time of the zero-crossing (seconds).
    public var time: TimeInterval
    /// Local image-y travel around the event (image units). Used to reject jitter.
    public var prominence: Double

    public init(imagePoint: CGPoint, time: TimeInterval, prominence: Double) {
        self.imagePoint = imagePoint
        self.time = time
        self.prominence = prominence
    }
}

// MARK: - BounceDetector

/// Detects bounce events in a BallTrack by finding sign flips in vertical
/// image velocity (dy) from positive to negative.
///
/// In image space, increasing y means the ball is moving DOWN the screen (falling).
/// A bounce occurs when dy transitions from positive (falling) to negative (rising).
/// The exact zero-crossing time and image point are recovered by linear interpolation
/// between the two bracketing samples. A prominence threshold rejects sub-pixel jitter.
///
/// Algorithm:
///  1. Walk consecutive pairs of TrackSamples.
///  2. Identify pairs where dy flips from > 0 to < 0 (+ to -).
///  3. Linearly interpolate the zero-crossing time: t* = t_a - dy_a * (t_b - t_a) / (dy_b - dy_a).
///  4. Interpolate the image point at t*.
///  5. Compute prominence as: max image-y in a local window minus the min image-y
///     on either side of the event (local peak height above surrounding values).
///  6. Discard bounces with prominence < minProminence.
public struct BounceDetector {
    /// Minimum local image-y travel (image units) required to report a bounce.
    /// Bounces below this threshold are considered jitter and discarded.
    public var minProminence: Double = 0.01

    public init(minProminence: Double = 0.01) {
        self.minProminence = minProminence
    }

    /// Detects bounces in the given track.
    /// Returns an array of Bounce values, ordered by time.
    public func bounces(in track: BallTrack) -> [Bounce] {
        let samples = track.samples
        guard samples.count >= 2 else { return [] }

        var result: [Bounce] = []

        for i in 0 ..< samples.count - 1 {
            let a = samples[i]
            let b = samples[i + 1]

            let dyA = a.velocity.dy
            let dyB = b.velocity.dy

            // A bounce requires dy to go from positive (falling) to negative (rising).
            guard dyA > 0 && dyB < 0 else { continue }

            // Linear interpolation of the zero-crossing time.
            let ddy = dyB - dyA
            guard ddy != 0 else { continue }
            let alpha = -dyA / ddy                    // in [0, 1]
            let dt = b.time - a.time
            let tStar = a.time + alpha * dt

            // Interpolate image point at t*.
            let xStar = a.imagePoint.x + alpha * (b.imagePoint.x - a.imagePoint.x)
            let yStar = a.imagePoint.y + alpha * (b.imagePoint.y - a.imagePoint.y)
            let pointStar = CGPoint(x: xStar, y: yStar)

            // Prominence: the height of the local peak above the surrounding valley floor.
            // Look up to 3 samples back and 3 samples forward to find min image-y on
            // each side; prominence = peak image-y minus the higher of the two minima.
            let peakY = yStar
            let lookback = max(0, i - 2)
            let lookahead = min(samples.count - 1, i + 3)

            let leftMin = samples[lookback ... i].map { $0.imagePoint.y }.min() ?? peakY
            let rightMin = samples[(i + 1) ... lookahead].map { $0.imagePoint.y }.min() ?? peakY

            // Prominence is the peak's height above the higher valley floor on either side.
            let prominence = peakY - max(leftMin, rightMin)

            guard prominence >= minProminence else { continue }

            result.append(Bounce(imagePoint: pointStar, time: tStar, prominence: prominence))
        }

        return result
    }
}
