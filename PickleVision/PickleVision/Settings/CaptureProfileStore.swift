import Foundation
import Combine
import SwiftUI
import PickleVisionCore

/// Persists the user's selected `CaptureProfile` in `UserDefaults`. Default is
/// `.auto`. The `UserDefaults` suite is injectable so it can be exercised in a
/// preview / isolated suite without touching the standard domain.
final class CaptureProfileStore: ObservableObject {
    private static let key = "captureProfile"
    private let defaults: UserDefaults

    @Published var profile: CaptureProfile {
        didSet { defaults.set(profile.rawValue, forKey: Self.key) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.key),
           let stored = CaptureProfile(rawValue: raw) {
            self.profile = stored
        } else {
            self.profile = .auto
        }
    }
}

#if DEBUG
/// Round-trips the store against an isolated suite. Runs in the preview below
/// (the app target has no XCTest bundle). Asserts in DEBUG builds only.
private func _captureProfileStoreSelfCheck() {
    let suiteName = "pv.captureprofile.selfcheck"
    let suite = UserDefaults(suiteName: suiteName)!
    suite.removePersistentDomain(forName: suiteName)

    let a = CaptureProfileStore(defaults: suite)
    assert(a.profile == .auto, "default should be .auto")
    a.profile = .uhd120
    let b = CaptureProfileStore(defaults: suite)
    assert(b.profile == .uhd120, "selection should persist")
    suite.removePersistentDomain(forName: suiteName)
}

#Preview("CaptureProfileStore self-check") {
    _captureProfileStoreSelfCheck()
    return Text("CaptureProfileStore OK")
}
#endif
