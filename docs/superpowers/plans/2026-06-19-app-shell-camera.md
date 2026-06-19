# App Shell + Camera Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the `PickleVision` iOS app — a SwiftUI shell that opens the Main camera at the best high-frame-rate format, shows a stable live preview with a status HUD, handles camera permission, and reacts to thermal pressure — so you can mount the phone and confirm the capture pipeline is correctly configured.

**Architecture:** A SwiftUI app target (`PickleVision`) that depends on the local `PickleVisionCore` Swift package built in Plan 1. The two *decisions* the camera layer makes — which `AVCaptureDevice.Format` to use and how to react to heat — are pure functions living in `PickleVisionCore` (`CameraFormatSelector`, `ThermalPolicy`), unit-tested headlessly. The device glue (`CameraService`, the preview view, the screens) lives in the app target and is verified by compiling and running on a real iPhone.

**Tech Stack:** Swift 5.9+ (app target in **Swift 5 language mode**), SwiftUI, AVFoundation, the local `PickleVisionCore` package. **No third-party dependencies.** Xcode-managed project (committed `.xcodeproj`).

This is **Plan 2 of 4** for Phase 0–1. Spec: `docs/superpowers/specs/2026-06-19-foundation-court-calibration-design.md`. Plan 1 (`PickleVisionCore`) is complete on `main`.

## Global Constraints

- **Platforms / language:** iOS 16.0 deployment target; app target uses **Swift 5 language mode** (avoids Swift 6 strict-concurrency churn in AVFoundation glue). The `PickleVisionCore` package stays as-is (tools 5.9).
- **Camera:** Main back **wide-angle** lens only (`.builtInWideAngleCamera`, `.back`). **No multi-cam, no front camera.**
- **Capture target:** **1080p height, highest frame rate ≤ 120 fps**, chosen by `CameraFormatSelector(targetHeight: 1080, maxFrameRate: 120)`. Cap the active frame duration to the chosen rate.
- **No third-party dependencies** anywhere.
- **Privacy:** the app **must** declare `NSCameraUsageDescription` or it crashes on first camera access.
- **Verification reality:** the camera does not run in the Simulator. Logic tasks gate on `swift test`. Device tasks gate on (a) a clean `xcodebuild` compile and (b) an on-device run by the user — that on-device run is the real acceptance.
- **Coordinate/naming carryovers from Plan 1:** `CameraFormatCandidate`, `CameraFormatSelector`, `ThermalLevel`, `ThermalRecommendation`, `ThermalPolicy` are NEW public types added to `PickleVisionCore`.

---

## File Structure

```
PickleVision.xcodeproj                         # created by you in Task 1, committed
PickleVision/                                   # app target sources (Xcode's app group)
  PickleVisionApp.swift                         # @main app entry (exists after Task 1; edited Task 6)
  HomeView.swift                                # Task 6 — landing screen
  CameraScreen.swift                            # Task 6 — preview + HUD
  CameraPreviewView.swift                       # Task 5 — UIViewRepresentable preview
  CameraService.swift                           # Task 4 — AVFoundation capture
  Info.plist / target settings                  # NSCameraUsageDescription (Task 1)
PickleVisionCore/                               # existing package (Plan 1)
  Sources/PickleVisionCore/
    CameraFormatSelector.swift                  # Task 2
    ThermalPolicy.swift                          # Task 3
  Tests/PickleVisionCoreTests/
    CameraFormatSelectorTests.swift             # Task 2
    ThermalPolicyTests.swift                     # Task 3
```

---

### Task 1: Create the Xcode app project (USER, guided)

**This task is done by you in Xcode, not by an agent.** It is a one-time ~6-step setup. After it, agents take over.

**Files:**
- Create (via Xcode): `PickleVision.xcodeproj` and the `PickleVision/` app source group at the repo root.

- [ ] **Step 1: New project.** Open Xcode → **File ▸ New ▸ Project…** → **iOS ▸ App** → Next. Set:
  - Product Name: **PickleVision**
  - Team: your personal team (your Apple ID — add it under Xcode ▸ Settings ▸ Accounts if needed)
  - Organization Identifier: anything unique, e.g. `com.avosarkissian`
  - Interface: **SwiftUI**, Language: **Swift**, Storage: **None**. Uncheck tests/Core Data.

- [ ] **Step 2: Save INTO the repo.** On the save dialog, navigate to `/Users/avosarkissian/Documents/VS Code/Pickle Vision` and save there (so `PickleVision.xcodeproj` sits next to the existing `PickleVisionCore/` and `docs/`). **Uncheck "Create Git repository"** (the repo already exists).

- [ ] **Step 3: Set deployment + language mode.** Select the project ▸ the **PickleVision** target ▸ **General** → set **Minimum Deployments = iOS 16.0**. Then **Build Settings** → search "Swift Language Version" → set it to **Swift 5**.

- [ ] **Step 4: Add the local package.** **File ▸ Add Package Dependencies… ▸ Add Local…** → select the `PickleVisionCore` folder → Add Package → attach the **PickleVisionCore** library product to the **PickleVision** target.

- [ ] **Step 5: Add the camera privacy string.** Select the target ▸ **Info** tab → add a row: key **"Privacy - Camera Usage Description"** (`NSCameraUsageDescription`), value: `Pickle Vision uses the camera to watch the court and call the lines.`

- [ ] **Step 6: Build, run, commit.** Pick an iOS Simulator (e.g. iPhone 16 Pro) and **Run (⌘R)** — you should see the default white screen with "Hello, world!". Then commit:

```bash
cd "/Users/avosarkissian/Documents/VS Code/Pickle Vision"
git add PickleVision.xcodeproj PickleVision
git commit -m "chore(app): scaffold PickleVision iOS app target + PickleVisionCore dependency"
git push origin main
```

**Done when:** `import PickleVisionCore` compiles in the app (you can test by adding `import PickleVisionCore` to `ContentView.swift` and building), and the empty app runs in the Simulator.

> Tell the agent, when execution reaches Task 2+, the exact name of the app's source folder and the `@main` file (Xcode names them `PickleVision/` and `PickleVisionApp.swift` by default; confirm before agents edit them).

---

### Task 2: CameraFormatSelector (TDD, PickleVisionCore)

**Files:**
- Create: `PickleVisionCore/Sources/PickleVisionCore/CameraFormatSelector.swift`
- Test: `PickleVisionCore/Tests/PickleVisionCoreTests/CameraFormatSelectorTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct CameraFormatCandidate: Equatable` with `width: Int, height: Int, maxFrameRate: Double, isBinned: Bool, supportsMultiCam: Bool` and a memberwise `init(width:height:maxFrameRate:isBinned:supportsMultiCam:)` (last two defaulting to `false`).
  - `struct CameraFormatSelector` with `init(targetHeight: Int = 1080, maxFrameRate: Double = 120)` and `func select(from candidates: [CameraFormatCandidate]) -> CameraFormatCandidate?`.

- [ ] **Step 1: Write the failing tests**

`CameraFormatSelectorTests.swift`:

```swift
import XCTest
@testable import PickleVisionCore

final class CameraFormatSelectorTests: XCTestCase {
    private let selector = CameraFormatSelector(targetHeight: 1080, maxFrameRate: 120)

    func test_prefers_1080p_at_the_cap_over_4k_and_720p() {
        let candidates = [
            CameraFormatCandidate(width: 3840, height: 2160, maxFrameRate: 60),
            CameraFormatCandidate(width: 1920, height: 1080, maxFrameRate: 120),
            CameraFormatCandidate(width: 1920, height: 1080, maxFrameRate: 240),
            CameraFormatCandidate(width: 1280, height: 720,  maxFrameRate: 240),
        ]
        // 1080p that meets the 120 cap with the least excess headroom.
        XCTAssertEqual(selector.select(from: candidates),
                       CameraFormatCandidate(width: 1920, height: 1080, maxFrameRate: 120))
    }

    func test_when_nothing_meets_the_cap_it_takes_the_highest_rate_at_target_height() {
        let candidates = [
            CameraFormatCandidate(width: 1920, height: 1080, maxFrameRate: 30),
            CameraFormatCandidate(width: 1920, height: 1080, maxFrameRate: 60),
        ]
        XCTAssertEqual(selector.select(from: candidates)?.maxFrameRate, 60)
    }

    func test_falls_back_to_closest_height_when_no_1080p() {
        let candidates = [
            CameraFormatCandidate(width: 3840, height: 2160, maxFrameRate: 120),
            CameraFormatCandidate(width: 1280, height: 720,  maxFrameRate: 120),
        ]
        // 720 is closer to 1080 than 2160 is.
        XCTAssertEqual(selector.select(from: candidates)?.height, 720)
    }

    func test_empty_returns_nil() {
        XCTAssertNil(selector.select(from: []))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path PickleVisionCore --filter CameraFormatSelectorTests`
Expected: FAIL — `cannot find 'CameraFormatSelector' in scope`.

- [ ] **Step 3: Implement the selector**

`CameraFormatSelector.swift`:

```swift
import Foundation

/// A capture format abstracted from `AVCaptureDevice.Format` so the selection
/// logic can be unit-tested without a camera.
public struct CameraFormatCandidate: Equatable {
    public let width: Int
    public let height: Int
    public let maxFrameRate: Double
    public let isBinned: Bool
    public let supportsMultiCam: Bool

    public init(width: Int, height: Int, maxFrameRate: Double,
                isBinned: Bool = false, supportsMultiCam: Bool = false) {
        self.width = width
        self.height = height
        self.maxFrameRate = maxFrameRate
        self.isBinned = isBinned
        self.supportsMultiCam = supportsMultiCam
    }
}

/// Picks the best capture format for ball tracking: closest to a target
/// resolution height, then the lowest native frame rate that still reaches the
/// cap (least thermal waste), preferring non-binned, higher-resolution formats.
public struct CameraFormatSelector {
    public let targetHeight: Int
    public let maxFrameRate: Double

    public init(targetHeight: Int = 1080, maxFrameRate: Double = 120) {
        self.targetHeight = targetHeight
        self.maxFrameRate = maxFrameRate
    }

    /// Returns the best candidate, or `nil` if none are usable. The comparator
    /// returns `true` when `a` is a better choice than `b`.
    public func select(from candidates: [CameraFormatCandidate]) -> CameraFormatCandidate? {
        let usable = candidates.filter { $0.maxFrameRate >= 1 }
        guard !usable.isEmpty else { return nil }
        return usable.min { a, b in
            let da = abs(a.height - targetHeight)
            let db = abs(b.height - targetHeight)
            if da != db { return da < db }                       // closest to target height

            let aMeets = a.maxFrameRate >= maxFrameRate
            let bMeets = b.maxFrameRate >= maxFrameRate
            if aMeets != bMeets { return aMeets }                 // meeting the cap wins
            if aMeets {                                           // both meet: least excess headroom
                if a.maxFrameRate != b.maxFrameRate { return a.maxFrameRate < b.maxFrameRate }
            } else {                                              // neither meets: highest available
                if a.maxFrameRate != b.maxFrameRate { return a.maxFrameRate > b.maxFrameRate }
            }
            if a.isBinned != b.isBinned { return !a.isBinned }    // prefer non-binned
            return a.width > b.width                              // prefer higher resolution
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path PickleVisionCore --filter CameraFormatSelectorTests`
Expected: PASS — 4 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add PickleVisionCore
git commit -m "feat(core): add CameraFormatSelector"
```

---

### Task 3: ThermalPolicy (TDD, PickleVisionCore)

**Files:**
- Create: `PickleVisionCore/Sources/PickleVisionCore/ThermalPolicy.swift`
- Test: `PickleVisionCore/Tests/PickleVisionCoreTests/ThermalPolicyTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum ThermalLevel: Int, Comparable { case nominal, fair, serious, critical, shutdown }`
  - `struct ThermalRecommendation: Equatable { let shouldWarn: Bool; let frameRateCap: Double?; let message: String? }`
  - `struct ThermalPolicy` with `init(baseFrameRate: Double = 120)` and `func recommendation(for level: ThermalLevel) -> ThermalRecommendation`.

- [ ] **Step 1: Write the failing tests**

`ThermalPolicyTests.swift`:

```swift
import XCTest
@testable import PickleVisionCore

final class ThermalPolicyTests: XCTestCase {
    private let policy = ThermalPolicy(baseFrameRate: 120)

    func test_nominal_and_fair_are_unrestricted() {
        for level in [ThermalLevel.nominal, .fair] {
            let r = policy.recommendation(for: level)
            XCTAssertFalse(r.shouldWarn)
            XCTAssertNil(r.frameRateCap)
        }
    }

    func test_serious_warns_and_caps_to_60() {
        let r = policy.recommendation(for: .serious)
        XCTAssertTrue(r.shouldWarn)
        XCTAssertEqual(r.frameRateCap, 60)
        XCTAssertNotNil(r.message)
    }

    func test_critical_caps_to_30() {
        XCTAssertEqual(policy.recommendation(for: .critical).frameRateCap, 30)
    }

    func test_shutdown_pauses_capture() {
        let r = policy.recommendation(for: .shutdown)
        XCTAssertEqual(r.frameRateCap, 0)
        XCTAssertTrue(r.shouldWarn)
    }

    func test_level_is_ordered() {
        XCTAssertTrue(ThermalLevel.nominal < ThermalLevel.critical)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path PickleVisionCore --filter ThermalPolicyTests`
Expected: FAIL — `cannot find 'ThermalPolicy' in scope`.

- [ ] **Step 3: Implement the policy**

`ThermalPolicy.swift`:

```swift
import Foundation

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
                                         message: "Phone is warming up — reduced to \(Int(cap)) fps.")
        case .critical:
            let cap = min(30, baseFrameRate)
            return ThermalRecommendation(shouldWarn: true, frameRateCap: cap,
                                         message: "Phone is hot — reduced to \(Int(cap)) fps. Move to shade.")
        case .shutdown:
            return ThermalRecommendation(shouldWarn: true, frameRateCap: 0,
                                         message: "Phone too hot — capture paused to cool down.")
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path PickleVisionCore --filter ThermalPolicyTests`
Expected: PASS — 5 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add PickleVisionCore
git commit -m "feat(core): add ThermalPolicy"
```

---

### Task 4: CameraService (device, app target)

**Files:**
- Create: `PickleVision/CameraService.swift`

**Interfaces:**
- Consumes: `CameraFormatCandidate`, `CameraFormatSelector` (Task 2), `ThermalLevel`, `ThermalRecommendation`, `ThermalPolicy` (Task 3).
- Produces: `@MainActor final class CameraService: NSObject, ObservableObject` exposing `let session: AVCaptureSession`, and `@Published` `permission: CameraService.PermissionState`, `isRunning: Bool`, `selectedFormatDescription: String`, `measuredFPS: Int`, `thermal: ThermalRecommendation`; plus `func start()` and `func stop()`.

**Verification model:** no unit test (needs a camera). Gate = a clean compile, then an on-device run in Task 6. The implementer must build the app target (see Step 3) and report the compile result.

- [ ] **Step 1: Write `CameraService.swift`**

```swift
import AVFoundation
import Combine
import QuartzCore
import PickleVisionCore

@MainActor
final class CameraService: NSObject, ObservableObject {
    enum PermissionState { case unknown, authorized, denied }

    @Published private(set) var permission: PermissionState = .unknown
    @Published private(set) var isRunning = false
    @Published private(set) var selectedFormatDescription = "—"
    @Published private(set) var measuredFPS = 0
    @Published private(set) var thermal = ThermalRecommendation(shouldWarn: false, frameRateCap: nil, message: nil)

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "vision.pickle.session")
    private let frameQueue = DispatchQueue(label: "vision.pickle.frames")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let selector = CameraFormatSelector(targetHeight: 1080, maxFrameRate: 120)
    private let thermalPolicy = ThermalPolicy(baseFrameRate: 120)

    private var device: AVCaptureDevice?
    private var pressureObservation: NSKeyValueObservation?
    private var chosenMaxRate: Double = 120
    private var frameTimes: [CFTimeInterval] = []

    /// Requests permission if needed, then configures and starts the session.
    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permission = .authorized
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    self.permission = granted ? .authorized : .denied
                    if granted { self.configureAndStart() }
                }
            }
        default:
            permission = .denied
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        isRunning = false
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureSession()
            if !self.session.isRunning { self.session.startRunning() }
            let running = self.session.isRunning
            Task { @MainActor in self.isRunning = running }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .inputPriority   // we set device.activeFormat ourselves

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        self.device = device

        // Map the device's formats to testable candidates and pick the best.
        let mapped: [(AVCaptureDevice.Format, CameraFormatCandidate)] = device.formats.map { fmt in
            let dims = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
            let maxRate = fmt.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
            return (fmt, CameraFormatCandidate(width: Int(dims.width),
                                               height: Int(dims.height),
                                               maxFrameRate: maxRate,
                                               isBinned: fmt.isVideoBinned,
                                               supportsMultiCam: fmt.isMultiCamSupported))
        }
        if let best = selector.select(from: mapped.map(\.1)),
           let chosen = mapped.first(where: { $0.1 == best })?.0 {
            let rate = min(best.maxFrameRate, 120)
            chosenMaxRate = rate
            if (try? device.lockForConfiguration()) != nil {
                device.activeFormat = chosen
                let duration = CMTime(value: 1, timescale: CMTimeScale(rate))
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
                device.unlockForConfiguration()
            }
            let desc = "\(best.height)p · \(Int(rate))fps"
            Task { @MainActor in self.selectedFormatDescription = desc }
        }

        if session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: frameQueue)
            session.addOutput(videoOutput)
        }

        session.commitConfiguration()
        observePressure(on: device)
    }

    private func observePressure(on device: AVCaptureDevice) {
        pressureObservation = device.observe(\.systemPressureState, options: [.initial, .new]) { [weak self] dev, _ in
            let level = CameraService.map(dev.systemPressureState.level)
            Task { @MainActor in
                guard let self else { return }
                self.thermal = self.thermalPolicy.recommendation(for: level)
                self.applyThermalCap()
            }
        }
    }

    /// Re-applies the active frame duration if thermal pressure capped the rate.
    private func applyThermalCap() {
        let cap = thermal.frameRateCap
        sessionQueue.async { [weak self] in
            guard let self, let device = self.device else { return }
            let target: Double
            if let cap, cap > 0 { target = min(cap, self.chosenMaxRate) }
            else { target = self.chosenMaxRate }
            guard target > 0, (try? device.lockForConfiguration()) != nil else { return }
            let duration = CMTime(value: 1, timescale: CMTimeScale(target))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
        }
    }

    static func map(_ level: AVCaptureDevice.SystemPressureState.Level) -> ThermalLevel {
        switch level {
        case .nominal:  return .nominal
        case .fair:     return .fair
        case .serious:  return .serious
        case .critical: return .critical
        case .shutdown: return .shutdown
        default:        return .nominal
        }
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        Task { @MainActor [weak self] in self?.recordFrame(at: now) }
    }

    @MainActor private func recordFrame(at t: CFTimeInterval) {
        frameTimes.append(t)
        frameTimes.removeAll { t - $0 > 1.0 }
        measuredFPS = frameTimes.count
    }
}
```

- [ ] **Step 2: Add the file to the app target**

Ensure `CameraService.swift` is a member of the **PickleVision** target (Xcode adds it automatically when created inside the app group; if added via the filesystem, check the File Inspector ▸ Target Membership).

- [ ] **Step 3: Compile the app target**

Run (replace the scheme/destination if Xcode named them differently):

```bash
cd "/Users/avosarkissian/Documents/VS Code/Pickle Vision"
xcodebuild -project PickleVision.xcodeproj -scheme PickleVision \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`. If it fails on a Swift 6 concurrency diagnostic, confirm the target's Swift Language Version is **Swift 5** (Task 1, Step 3). Report the build result; there is no runtime check in this task (that happens in Task 6 on device).

- [ ] **Step 4: Commit**

```bash
git add PickleVision/CameraService.swift PickleVision.xcodeproj
git commit -m "feat(app): add CameraService (Main lens, 1080p120, thermal-aware)"
```

---

### Task 5: CameraPreviewView (device, app target)

**Files:**
- Create: `PickleVision/CameraPreviewView.swift`

**Interfaces:**
- Consumes: `AVCaptureSession` (from `CameraService.session`).
- Produces: `struct CameraPreviewView: UIViewRepresentable` taking `let session: AVCaptureSession`.

- [ ] **Step 1: Write `CameraPreviewView.swift`**

```swift
import SwiftUI
import AVFoundation

/// A SwiftUI wrapper around `AVCaptureVideoPreviewLayer` that fills its bounds.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
```

- [ ] **Step 2: Compile the app target**

Run:

```bash
cd "/Users/avosarkissian/Documents/VS Code/Pickle Vision"
xcodebuild -project PickleVision.xcodeproj -scheme PickleVision \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add PickleVision/CameraPreviewView.swift PickleVision.xcodeproj
git commit -m "feat(app): add AVCaptureVideoPreviewLayer-backed CameraPreviewView"
```

---

### Task 6: App shell + CameraScreen (device, app target)

**Files:**
- Create: `PickleVision/HomeView.swift`, `PickleVision/CameraScreen.swift`
- Modify: the `@main` app entry file (default `PickleVision/PickleVisionApp.swift`) to show `HomeView`; remove the template `ContentView.swift` from the target if present.

**Interfaces:**
- Consumes: `CameraService` (Task 4), `CameraPreviewView` (Task 5).
- Produces: `HomeView` (landing screen with a "Start Camera" nav link) and `CameraScreen` (preview + status HUD + permission-denied state).

- [ ] **Step 1: Write `CameraScreen.swift`**

```swift
import SwiftUI

struct CameraScreen: View {
    @StateObject private var camera = CameraService()

    var body: some View {
        ZStack {
            switch camera.permission {
            case .authorized:
                CameraPreviewView(session: camera.session)
                    .ignoresSafeArea()
                hud
            case .denied:
                permissionDenied
            case .unknown:
                Color.black.ignoresSafeArea()
                ProgressView().tint(.white)
            }
        }
        .navigationTitle("Camera")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    private var hud: some View {
        VStack {
            HStack(spacing: 10) {
                pill(camera.selectedFormatDescription)
                pill("\(camera.measuredFPS) fps")
                if camera.thermal.shouldWarn, let msg = camera.thermal.message {
                    pill(msg, warning: true)
                }
                Spacer()
            }
            .padding()
            Spacer()
        }
    }

    private var permissionDenied: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.metering.unknown").font(.largeTitle)
            Text("Camera access is off").font(.headline)
            Text("Pickle Vision needs the camera to see the court.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func pill(_ text: String, warning: Bool = false) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(warning ? Color.orange.opacity(0.9) : Color.black.opacity(0.55))
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }
}
```

- [ ] **Step 2: Write `HomeView.swift`**

```swift
import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "figure.pickleball").font(.system(size: 64))
                Text("Pickle Vision").font(.largeTitle.bold())
                Text("Mount the phone behind the baseline and start the camera.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                NavigationLink {
                    CameraScreen()
                } label: {
                    Label("Start Camera", systemImage: "camera.fill")
                        .font(.headline).padding(.horizontal, 24).padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}
```

- [ ] **Step 3: Point the app entry at `HomeView`**

Edit the `@main` file (default `PickleVision/PickleVisionApp.swift`) so its `WindowGroup` shows `HomeView()` instead of `ContentView()`:

```swift
import SwiftUI

@main
struct PickleVisionApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}
```

Then delete `ContentView.swift` from the project (or leave it unused — but removing it keeps the target clean).

- [ ] **Step 4: Compile the app target**

Run:

```bash
cd "/Users/avosarkissian/Documents/VS Code/Pickle Vision"
xcodebuild -project PickleVision.xcodeproj -scheme PickleVision \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add PickleVision PickleVision.xcodeproj
git commit -m "feat(app): home screen + camera screen with live preview and status HUD"
```

- [ ] **Step 6: On-device acceptance (USER)**

Run the app on your iPhone 16 Pro from Xcode (select your device as the run destination; sign with your Apple ID team). Verify:
1. Launch → Home screen → tap **Start Camera**.
2. The first time, iOS prompts for camera access — tap **Allow**.
3. A **live preview** appears, filling the screen.
4. The HUD shows **"1080p · 120fps"** (or the best your court lighting allows) and a **live fps** counter near ~120 in good light.
5. Background the app or let the phone heat up under sustained use → the thermal pill appears and the fps steps down (hard to force; optional).
6. To check the denied path: revoke camera access in Settings → relaunch → you should see the "Camera access is off" screen with a working **Open Settings** button.

This on-device run is the real acceptance for this plan.

---

## Self-Review (coverage against the spec)

This plan implements the **camera foundation** portion of the Foundation + Calibration spec:

- **§4 `CameraService`** (Main lens, 1080p120 target, thermal `systemPressure` step-down) → Task 4, using the tested `CameraFormatSelector` (Task 2) and `ThermalPolicy` (Task 3).
- **§3 capture assumptions** (Main 1x lens, ~1080p120, no multi-cam) → enforced by `CameraFormatSelector` config and `.builtInWideAngleCamera`.
- **§4 app skeleton (SwiftUI)** and a verifiable live preview → Tasks 1, 5, 6.
- **§8 error handling** (no camera permission → guide to Settings; thermal step-down with warning) → Task 6 permission-denied screen + Task 4 thermal cap.
- **Frame pipeline** for later phases → Task 4's `AVCaptureVideoDataOutput` (currently measures fps; Plan 3 consumes pixel buffers).

**Deferred to later plans (correctly out of scope):** court auto-detection, manual tap calibration, the calibration overlay, and the drift guard (Plans 3–4). This plan only proves a correctly-configured, stable capture pipeline with a preview.

**Verification note:** Tasks 2–3 gate on `swift test`; Tasks 4–6 gate on a clean `xcodebuild` compile plus the on-device run in Task 6. Task 1 and the Task 6 device run are **user-executed**; everything else is agent-executable.

**Placeholder scan:** none — every code step has complete code; every command has an expected result.

**Type consistency:** `CameraFormatSelector.select(from:)`, `ThermalPolicy.recommendation(for:)`, `ThermalRecommendation(shouldWarn:frameRateCap:message:)`, and `CameraService(session/permission/measuredFPS/thermal/start/stop)` are used identically across producing and consuming tasks.
