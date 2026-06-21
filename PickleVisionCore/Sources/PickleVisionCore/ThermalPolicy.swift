/// Mirrors `AVCaptureDevice.SystemPressureState.Level`, decoupled so the policy
/// is unit-testable without AVFoundation.
public enum ThermalLevel: Int, Comparable {
    case nominal = 0, fair, serious, critical, shutdown
    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct ThermalRecommendation: Equatable {
    public let shouldWarn: Bool
    public let frameRateCap: Double?   // nil = no cap; 0 = pause capture
    public let message: String?

    public init(shouldWarn: Bool, frameRateCap: Double?, message: String?) {
        self.shouldWarn = shouldWarn
        self.frameRateCap = frameRateCap
        self.message = message
    }
}

/// Maps system thermal pressure to a capture recommendation, stepping the frame
/// rate down before the OS forces a shutdown.
public struct ThermalPolicy {
    public let baseFrameRate: Double

    public init(baseFrameRate: Double = 120) {
        self.baseFrameRate = baseFrameRate
    }

    public func recommendation(for level: ThermalLevel) -> ThermalRecommendation {
        switch level {
        case .nominal, .fair:
            return ThermalRecommendation(shouldWarn: false, frameRateCap: nil, message: nil)
        case .serious:
            let cap = min(60, baseFrameRate)
            return ThermalRecommendation(shouldWarn: true, frameRateCap: cap,
                                         message: "Phone is warming up - reduced to \(Int(cap)) fps.")
        case .critical:
            let cap = min(30, baseFrameRate)
            return ThermalRecommendation(shouldWarn: true, frameRateCap: cap,
                                         message: "Phone is hot - reduced to \(Int(cap)) fps. Move to shade.")
        case .shutdown:
            return ThermalRecommendation(shouldWarn: true, frameRateCap: 0,
                                         message: "Phone too hot - capture paused to cool down.")
        }
    }
}
