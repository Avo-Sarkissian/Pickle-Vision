import Foundation

public enum DriftState: Equatable {
    case stable
    case drifted
}

/// Decides whether the camera has moved enough to invalidate the calibration.
/// Thresholds are compared inclusively, so a measurement exactly at the
/// threshold counts as drift.
public struct DriftDetector {
    public let translationThreshold: Double   // pixels
    public let rotationThreshold: Double       // radians

    public init(translationThreshold: Double = 12, rotationThreshold: Double = 0.02) {
        self.translationThreshold = translationThreshold
        self.rotationThreshold = rotationThreshold
    }

    public func evaluate(translation: Double, rotationRadians: Double) -> DriftState {
        if translation >= translationThreshold || abs(rotationRadians) >= rotationThreshold {
            return .drifted
        }
        return .stable
    }
}
