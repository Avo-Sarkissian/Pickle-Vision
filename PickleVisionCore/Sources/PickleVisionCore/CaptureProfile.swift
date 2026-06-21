import Foundation

/// A user-facing capture-quality preference. Each case is a thin policy over
/// `CameraFormatSelector(targetHeight:maxFrameRate:)` - the same selector the
/// camera already uses. iPhone 16 Pro reality: the main lens does 4K up to 120
/// and 1080p up to 240, so there is NO 4K·240 case. `ThermalPolicy` still
/// overrides the effective cap at runtime.
public enum CaptureProfile: String, CaseIterable, Codable {
    case auto
    case uhd120
    case fhd240
    case fhd120
    case batterySaver

    public enum Badge: Equatable { case recommended, `default` }

    public var targetHeight: Int {
        switch self {
        case .uhd120: return 2160
        default:      return 1080
        }
    }

    public var maxFrameRate: Double {
        switch self {
        case .fhd240:       return 240
        case .batterySaver: return 60
        default:            return 120   // .auto, .uhd120, .fhd120
        }
    }

    public var displayTitle: String {
        switch self {
        case .auto:         return "Auto"
        case .uhd120:       return "4K · 120 fps"
        case .fhd240:       return "1080p · 240 fps"
        case .fhd120:       return "1080p · 120 fps"
        case .batterySaver: return "Battery saver"
        }
    }

    public var subtitle: String? {
        switch self {
        case .auto:   return "Adapts to light, steps down on heat"
        case .fhd240: return "fast, flat shots"
        default:      return nil
        }
    }

    public var badge: Badge? {
        switch self {
        case .uhd120: return .recommended
        case .fhd120: return .default
        default:      return nil
        }
    }

    public var isRecommended: Bool { badge == .recommended }
    public var isDefault: Bool { badge == .default }

    public var formatSelector: CameraFormatSelector {
        CameraFormatSelector(targetHeight: targetHeight, maxFrameRate: maxFrameRate)
    }
}
