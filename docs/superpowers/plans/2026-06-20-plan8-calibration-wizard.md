# Plan 8 — Calibration Wizard (`Position → Detect → Fine-tune → Verify`)

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` (or `superpowers:subagent-driven-development`) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Implement each task fully before moving on; commit + push to `main` after each. This is the expanded, self-contained execution plan for **Plan 8** of the Direction-B UI build — the implementer has **zero prior context**, so everything needed is here.

**Goal:** Restructure the existing single-screen calibrator (`CalibrationScreen.swift` + `CalibrationView.swift`) into the 4-step **landscape, dark** calibration wizard — `Position → Auto-detect → Fine-tune → Verify` — with a pure, never-blocking state machine, a v1 fit-quality indicator derived from the homography reprojection residual, custom-dimensions entry, and the 0.5× ultra-wide fallback. The auto-detect **engine** is stubbed in this plan (it returns `.failed`, which drops the user to the guaranteed manual path); the real detector is Plan 3.5. Manual corner-drag + tap-test is the guaranteed calibration path throughout.

**Architecture:**
- **Core logic (TDD, in `PickleVisionCore`):** two new pure types — `FitQuality` (homography reprojection residual → `.good`/`.fair` bucket + a 0–4 segment score) and `CalibrationFlow` (a pure state machine: `Step`, advisory `SetupChecks`, `AutoDetectState`, and the calibration draft — corners, layout, custom dims, overlay toggle, tap point, computed `CourtModel?`, `fitQuality`). No SwiftUI. These land **first** so the views consume real types.
- **Views (clean-build verified, in the app target under `PickleVision/PickleVision/Calibration/`):** a host `CalibrationWizardView` (frozen-`latestImage` canvas on the left + a 204pt right rail) that switches between four step views — `PositionStepView`, `AutoDetectStepView`, `FineTuneStepView`, `VerifyStepView` — plus two cards (`CustomDimensionsSheet`, `UltraWideFallbackCard`). The existing `CalibrationView` (drag + loupe) is **reused and restyled**, not rewritten. Finally `CalibrationScreen.swift` is swapped to host the wizard, preserving `freeze()` / session reuse and the express-re-cal entry (which lands directly on Step 3 Fine-tune with a preloaded `StoredCalibration`'s corners + layout).
- **Consumes Plan 5 (Design System), already built** — `DesignSystem/Theme.swift` (`PVColor`, `PVFont`) and `DesignSystem/Components.swift` (`InstrumentPill`, `StatusReadout`, `PrimaryButton`, `SecondaryButton`, `SegmentedChips`, `PVCard`, `DashedPlaceholder`, `CourtOverlay`). **Do NOT redefine these** — read `DesignSystem/` for exact initializers at execution time and call them by name. If a Plan-5 symbol's exact initializer differs from what a step below assumes, prefer the real Plan-5 symbol and adapt the call site (the token names/intents here are stable; only initializer shapes may differ).

**Tech Stack:** Swift 5 / SwiftUI; `PickleVisionCore` Swift package (`swift-tools-version: 5.9`, iOS 16 / macOS 13); XCTest; `xcodebuild`; SF Pro / SF Mono; SF Symbols; vector overlays (`Path`/`Canvas`); on-device only; iPhone 16 Pro.

---

## Global Constraints

Copied verbatim from `docs/superpowers/specs/2026-06-19-ui-design-direction-b-instrument-daylight.md` + `docs/design/handoff-instrument-daylight.md`. **Every task implicitly includes these.**

- **Canonical references:** tokens/layout/copy = `docs/design/handoff-instrument-daylight.md`; visuals = `docs/design/screenshots/06..10`. Treat the handoff's exact hex/weights/copy as the spec.
- **Never hard-block on a CV result.** Position checks are guidance; `Continue anyway` is **always enabled**; "Calibrate manually" is always available; auto-detect failure drops to manual drag. Manual tap is the guaranteed path. The `SetupChecks(steady, framed, angle)` never gate a transition.
- **Honesty rule.** Never show a computed accuracy number we can't produce. v1 shows IN/OUT, court coords, "N/4 corners set", and a single qualitative **fit-quality from the homography reprojection residual** (qualitative label + 4-segment bar). Per-zone ±in and detect % are Phase 2 — **omit from v1 UI**. Auto-detect shows "Court found" with **no percentage**.
- **Bind to existing types — do not invent data models.** New core types are limited to `FitQuality` + `CalibrationFlow`. Everything else binds to: `CameraService`, `CalibrationStore`/`StoredCalibration`/`CodablePoint`, `CourtModel`, `CourtProfile`, `CourtLayout`, `CustomDimensions(widthFeet,lengthFeet,nonVolleyZoneFeet)`, `CalibrationDraft`, `Homography`, `AspectFillMapper`. (Handoff's "StabilityCheck" does not exist — not needed here.)
- **Per-screen orientation:** all calibration steps are **landscape** — apply `.lockOrientation(.landscape)` on the wizard host. Rail sits **beside** the frame (right column) so fingers never cover the court.
- **On-device only** — no login/account/cloud. **Target: iPhone 16 Pro.**
- **Fonts:** ship **SF Pro Display / SF Pro Text / SF Mono** via `PVFont`. **Court overlay is vector** — `Path`/`Shape`/`Canvas`, never raster. Icons = SF Symbols.
- **Process:** logic = TDD (failing XCTest → `swift test` fails → implement → passes → commit); views = clean build (**0 errors, 0 warnings**) + name the matching `docs/design/screenshots/NN-*.png` for the USER's on-device visual gate → commit. **Commit + push to `main` after each task.**

### Coordinate-space invariant (read before any core/view task)

`CalibrationDraft.corners` are **normalized image coordinates in `[0,1]`**, top-left origin, order `[nearLeft, nearRight, farRight, farLeft]`. `CalibrationDraft.courtModel()` builds the homography **from those normalized corners** to court feet. Therefore `CourtModel.courtPoint(forImage:)` and `imagePoint(forCourt:)` operate in **normalized image space**, NOT pixels. The existing tap-test in `CalibrationScreen.swift` confirms this: it calls `AspectFillMapper.imageNormalized(fromView:)` and feeds the **normalized** point to `courtPoint(forImage:)`. **All new code must keep this convention** — `FitQuality` computes its residual in normalized image space; views map view→normalized via `AspectFillMapper` before any `CourtModel` call.

---

## File Structure

New core (TDD):
- `PickleVisionCore/Sources/PickleVisionCore/FitQuality.swift`
- `PickleVisionCore/Tests/PickleVisionCoreTests/FitQualityTests.swift`
- `PickleVisionCore/Sources/PickleVisionCore/CalibrationFlow.swift`
- `PickleVisionCore/Tests/PickleVisionCoreTests/CalibrationFlowTests.swift`

New app views (clean build):
- `PickleVision/PickleVision/Calibration/CalibrationWizardView.swift` (host + a `CalibrationModel: ObservableObject` view-model wrapping `CalibrationFlow`)
- `PickleVision/PickleVision/Calibration/PositionStepView.swift`
- `PickleVision/PickleVision/Calibration/AutoDetectStepView.swift`
- `PickleVision/PickleVision/Calibration/FineTuneStepView.swift`
- `PickleVision/PickleVision/Calibration/VerifyStepView.swift`
- `PickleVision/PickleVision/Calibration/CustomDimensionsSheet.swift`
- `PickleVision/PickleVision/Calibration/UltraWideFallbackCard.swift`

Modified:
- `PickleVision/PickleVision/CalibrationView.swift` (restyle drag + loupe to optic-yellow tokens; **reused**)
- `PickleVision/PickleVision/CalibrationScreen.swift` (swap single-screen body → host the wizard; keep `freeze()` / session reuse; add express-re-cal entry)

> **App files auto-include** (synchronized Xcode groups) — no `.pbxproj` edits. Just create files under `PickleVision/PickleVision/Calibration/`.

---

## Commands (use these exact strings)

- **Build app:**
  ```
  xcodebuild -project "PickleVision/PickleVision.xcodeproj" -scheme PickleVision -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
  ```
  Pass = ends with `** BUILD SUCCEEDED **` and **0 warnings** (grep the log for `warning:` → must be empty).
- **Test core:**
  ```
  swift test --package-path PickleVisionCore
  ```
- **Commit + push (run from repo root):**
  ```
  git add -A && git commit -m "<message>" && git push origin main
  ```
  End every commit message body with:
  ```

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  ```

---

## Tasks

Order: **core logic first** (Task 1 `FitQuality`, Task 2 `CalibrationFlow`), then the host (Task 3), then the four step views (Tasks 4–7) that consume them, then the edge-case cards (Task 8), then the host swap + express-re-cal (Task 9).

---

### Task 1 — `FitQuality` (core, TDD)

Compute the homography reprojection residual from the 4 image corners, bucket into `.good`/`.fair`, and expose a 0–4 segment score for the bar. Deterministic, pure, no SwiftUI.

**Files:**
- Test: `PickleVisionCore/Tests/PickleVisionCoreTests/FitQualityTests.swift`
- Impl: `PickleVisionCore/Sources/PickleVisionCore/FitQuality.swift`

**Interfaces (exact Swift):**
```swift
public enum FitQuality: Equatable {
    case good
    case fair

    /// Number of filled segments in the 4-segment bar (0...4).
    public var segments: Int

    /// Qualitative label shown in the UI ("Good" / "Fair").
    public var label: String

    /// Evaluates fit quality from the 4 *normalized* image corners
    /// ([nearLeft, nearRight, farRight, farLeft]) for the given layout.
    /// Reprojection residual = mean distance, in normalized image units,
    /// between each input corner and the corner reprojected by the inverse
    /// homography (court corner -> image). Degenerate corners -> .fair / 0 segs.
    public static func evaluate(corners: [CGPoint],
                                layout: CourtLayout,
                                customDimensions: CustomDimensions? = nil) -> (quality: FitQuality, residual: Double)
}
```

**Why this is well-defined:** `Homography(source: corners, destination: profile.calibrationCorners)` maps normalized-image→court. Its `.inverse` maps court→normalized-image. Reproject each `profile.calibrationCorners[i]` through the inverse and measure its distance to the original `corners[i]`. For an exact 4-point DLT fit this residual is ~0 (machine epsilon), so a clean quad is `.good`/4 segments; a degenerate/near-collinear quad yields no homography (or a large residual) → `.fair`/low. We add a small synthetic-noise path in the test (perturb one corner) to exercise the `.fair` bucket via the threshold, since a pure 4-corner DLT is always near-exact on its own inputs. The threshold is on the residual magnitude.

**Thresholds (encode as written):**
- No homography (`Homography(...) == nil`) **or** no inverse → `(.fair, residual: .infinity)`, `segments == 0`.
- `residual <= 1e-6` (normalized units) → `.good`, `segments == 4`.
- `1e-6 < residual <= 1e-3` → `.good`, `segments == 3`.
- `1e-3 < residual <= 1e-2` → `.fair`, `segments == 2`.
- `residual > 1e-2` → `.fair`, `segments == 1`.

> Note for the implementer: a true 4-point DLT reprojects its own corners to ~machine-epsilon, so real fine-tuned quads land in the `.good`/4 bucket. The graded thresholds exist so the bar still moves for pathological/degenerate inputs and so the type is honest about residual — they are NOT a fabricated accuracy number (we surface only the qualitative label + bar in the UI, never the residual value; see honesty rule).

**Steps:**

- [ ] **1a. Write the failing test.** Create `FitQualityTests.swift`:
  ```swift
  import XCTest
  import CoreGraphics
  @testable import PickleVisionCore

  final class FitQualityTests: XCTestCase {
      // A clean perspective trapezoid in normalized image space
      // ([nearLeft, nearRight, farRight, farLeft]).
      private func cleanCorners() -> [CGPoint] {
          [CGPoint(x: 0.20, y: 0.90), CGPoint(x: 0.80, y: 0.90),
           CGPoint(x: 0.65, y: 0.30), CGPoint(x: 0.35, y: 0.30)]
      }

      func test_clean_quad_is_good_full_segments() {
          let (q, residual) = FitQuality.evaluate(corners: cleanCorners(),
                                                  layout: .regulationPickleball)
          XCTAssertEqual(q, .good)
          XCTAssertEqual(q.segments, 4)
          XCTAssertEqual(q.label, "Good")
          XCTAssertLessThanOrEqual(residual, 1e-6)
      }

      func test_degenerate_collinear_quad_is_fair_zero_segments() {
          // Four nearly-collinear points -> no valid homography.
          let collinear = [CGPoint(x: 0.10, y: 0.50), CGPoint(x: 0.40, y: 0.50),
                           CGPoint(x: 0.70, y: 0.50), CGPoint(x: 0.95, y: 0.50)]
          let (q, residual) = FitQuality.evaluate(corners: collinear,
                                                  layout: .regulationPickleball)
          XCTAssertEqual(q, .fair)
          XCTAssertEqual(q.segments, 0)
          XCTAssertEqual(q.label, "Fair")
          XCTAssertFalse(residual.isFinite || residual <= 1e-2 && residual >= 0 && q == .good)
      }

      func test_wrong_corner_count_is_fair_zero_segments() {
          let (q, _) = FitQuality.evaluate(corners: [CGPoint(x: 0.2, y: 0.9)],
                                           layout: .regulationPickleball)
          XCTAssertEqual(q, .fair)
          XCTAssertEqual(q.segments, 0)
      }

      func test_custom_layout_clean_quad_is_good() {
          let dims = CustomDimensions(widthFeet: 18, lengthFeet: 40, nonVolleyZoneFeet: 7)
          let (q, _) = FitQuality.evaluate(corners: cleanCorners(),
                                           layout: .custom, customDimensions: dims)
          XCTAssertEqual(q, .good)
          XCTAssertEqual(q.segments, 4)
      }

      func test_segments_and_label_are_consistent() {
          XCTAssertEqual(FitQuality.good.label, "Good")
          XCTAssertEqual(FitQuality.fair.label, "Fair")
      }
  }
  ```
- [ ] **1b. Run the test — confirm it FAILS to compile/run** (the type doesn't exist yet):
  ```
  swift test --package-path PickleVisionCore --filter FitQualityTests
  ```
  Expected: compile error `cannot find 'FitQuality' in scope` (this is the failing-test gate).
- [ ] **1c. Implement** `FitQuality.swift`:
  ```swift
  import CoreGraphics

  /// A v1, honesty-rule-compliant fit indicator: a qualitative bucket plus a
  /// 0–4 segment count for the bar, derived from the homography reprojection
  /// residual of the four calibrated corners. We surface only the label and the
  /// bar in the UI — never the raw residual — because per-zone ± inches are a
  /// Phase-2 (measured-on-court) number we cannot produce yet.
  public enum FitQuality: Equatable {
      case good
      case fair

      public var segments: Int {
          switch self {
          case .good: return 4   // overridden by `evaluate` via the tuple's bar count
          case .fair: return 1
          }
      }

      public var label: String {
          switch self {
          case .good: return "Good"
          case .fair: return "Fair"
          }
      }

      /// Returns the qualitative bucket, the residual (normalized image units),
      /// and — via `barSegments(for:)` below — the 0...4 bar count.
      public static func evaluate(corners: [CGPoint],
                                  layout: CourtLayout,
                                  customDimensions: CustomDimensions? = nil)
      -> (quality: FitQuality, residual: Double) {
          let r = residual(corners: corners, layout: layout, customDimensions: customDimensions)
          let q: FitQuality = (r <= 1e-3) ? .good : .fair
          return (q, r)
      }

      /// 0...4 segments for the bar, given a residual (normalized image units).
      public static func barSegments(for residual: Double) -> Int {
          guard residual.isFinite else { return 0 }
          if residual <= 1e-6 { return 4 }
          if residual <= 1e-3 { return 3 }
          if residual <= 1e-2 { return 2 }
          return 1
      }

      /// Mean reprojection distance, in normalized image units, between each
      /// input corner and the corresponding court corner mapped back to image
      /// space via the inverse homography. `.infinity` when no homography exists.
      private static func residual(corners: [CGPoint],
                                   layout: CourtLayout,
                                   customDimensions: CustomDimensions?) -> Double {
          guard corners.count == 4 else { return .infinity }
          let profile = CourtProfile.make(layout: layout, custom: customDimensions)
          guard let h = Homography(source: corners, destination: profile.calibrationCorners),
                let inv = h.inverse else { return .infinity }
          var sum = 0.0
          for i in 0..<4 {
              let back = inv.project(profile.calibrationCorners[i])
              sum += hypot(Double(back.x - corners[i].x), Double(back.y - corners[i].y))
          }
          return sum / 4.0
      }
  }
  ```
  > The `segments` instance property is a convenience for callers that already hold a `FitQuality` (used in the test). The **bar** in the UI uses `FitQuality.barSegments(for: residual)` so it can show 0–4. To satisfy `test_clean_quad_is_good_full_segments` (`q.segments == 4`) and `test_degenerate_..._zero_segments` (`q.segments == 0`), make the test's `q.segments` reads agree: for `.good`, return 4; for the degenerate cases the test asserts `q.segments == 0` while `q == .fair`. Reconcile by having the **view-model** carry the bar count from `barSegments(for:)` and the **tests** assert on `barSegments` for the 0/2/etc. cases. **Implementer action:** change the two segment assertions in 1a that need 0 to assert on `FitQuality.barSegments(for: residual)` instead of `q.segments`, i.e.:
  > ```swift
  > // in test_degenerate_collinear_quad_is_fair_zero_segments:
  > XCTAssertEqual(FitQuality.barSegments(for: residual), 0)
  > // in test_wrong_corner_count_is_fair_zero_segments:
  > let (q, residual) = FitQuality.evaluate(...)
  > XCTAssertEqual(FitQuality.barSegments(for: residual), 0)
  > ```
  > and keep `q.segments == 4` only for the `.good` clean-quad case. This keeps the bar count honest (residual-driven) and the enum convenience (`.good → 4`) simple. Make this edit in 1a before running 1d.
- [ ] **1d. Run the test — confirm it PASSES:**
  ```
  swift test --package-path PickleVisionCore --filter FitQualityTests
  ```
  Expected: `Executed 5 tests, with 0 failures`.
- [ ] **1e. Run the full suite** (no regressions):
  ```
  swift test --package-path PickleVisionCore
  ```
  Expected: all tests pass.
- [ ] **1f. Commit + push:**
  ```
  git add -A && git commit -m "feat(core): FitQuality — qualitative fit from homography reprojection residual + 0–4 bar (Plan 8 T1)" && git push origin main
  ```

---

### Task 2 — `CalibrationFlow` state machine (core, TDD)

A pure state machine: the `Step` enum, advisory `SetupChecks` (informs guidance but **never gates** a transition), `AutoDetectState`, and the calibration draft (corners, layout, custom dims, overlay-visible, tap-test point, computed `CourtModel?`, `fitQuality`). No SwiftUI.

**Files:**
- Test: `PickleVisionCore/Tests/PickleVisionCoreTests/CalibrationFlowTests.swift`
- Impl: `PickleVisionCore/Sources/PickleVisionCore/CalibrationFlow.swift`

**Interfaces (exact Swift):**
```swift
public enum CalibrationStep: Int, CaseIterable, Equatable {
    case position, detect, fineTune, verify
}

/// Advisory setup signals. ADVISORY ONLY — they inform guidance copy but must
/// NEVER gate a transition (never hard-block on a CV/sensor result).
public struct SetupChecks: Equatable {
    public var steady: Bool
    public var framed: Bool
    public var angle: Bool
    public init(steady: Bool = false, framed: Bool = false, angle: Bool = false)
    /// e.g. 2 of 3 passing — used only for the "2 / 3 — go anyway" caption.
    public var passingCount: Int { get }
    public var total: Int { get }   // always 3
}

public enum AutoDetectState: Equatable {
    case idle, finding, found, failed
}

/// Pure calibration state. SwiftUI view-model wraps this; all transitions are
/// total (no transition is ever blocked by a check or a CV result).
public struct CalibrationFlow: Equatable {
    public private(set) var step: CalibrationStep
    public var checks: SetupChecks
    public var autoDetect: AutoDetectState

    // Draft
    public var corners: [CGPoint]               // normalized image, [NL,NR,FR,FL]
    public var layout: CourtLayout
    public var customDimensions: CustomDimensions?
    public var overlayVisible: Bool
    public var tapPoint: CGPoint?               // normalized image point of last tap-test

    public init(step: CalibrationStep = .position,
                corners: [CGPoint] = CalibrationDraft.defaultCorners(),
                layout: CourtLayout = .regulationPickleball,
                customDimensions: CustomDimensions? = nil)

    // Derived
    public var draft: CalibrationDraft { get }
    public var courtModel: CourtModel? { get }
    public var cornersSetCount: Int { get }     // always 4 once defaults/loaded; for "N/4 corners set"
    public var isComplete: Bool { get }
    public var fitQuality: (quality: FitQuality, residual: Double) { get }

    // Transitions — ALL total, none gated by checks or autoDetect.
    public mutating func goToStep(_ s: CalibrationStep)
    public mutating func advance()              // position->detect->fineTune->verify (clamped at verify)
    public mutating func back()                 // verify->fineTune->detect->position (clamped at position)
    /// "Continue anyway" from Position. Always succeeds regardless of checks.
    public mutating func continueFromPosition()
    /// "Calibrate manually" — skip auto-detect, jump straight to Fine-tune.
    public mutating func calibrateManually()
    /// Begin a stubbed auto-detect. In v1 the engine is not present.
    public mutating func startAutoDetect()
    /// Engine result hook (Plan 3.5 calls this; v1 stub resolves to .failed).
    public mutating func resolveAutoDetect(_ result: AutoDetectState, detectedCorners: [CGPoint]?)
    /// From a failed/any auto-detect, drop to the guaranteed manual path.
    public mutating func dropToManual()
    /// Express re-calibration: preload a saved court and land on Fine-tune.
    public static func forExpressReCal(corners: [CGPoint],
                                       layout: CourtLayout,
                                       customDimensions: CustomDimensions?) -> CalibrationFlow
}
```

**Transition semantics to encode:**
- `continueFromPosition()` → sets `step = .detect`, **ignores `checks` entirely** (no guard).
- `calibrateManually()` → sets `step = .fineTune` (skips detect). Always allowed from any step.
- `startAutoDetect()` → sets `autoDetect = .finding` and `step = .detect`.
- `resolveAutoDetect(.found, detectedCorners:)` → `autoDetect = .found`; if `detectedCorners?.count == 4`, copy them into `corners`.
- `resolveAutoDetect(.failed, _)` → `autoDetect = .failed`. **Manual path stays reachable** — `step` unchanged, and `dropToManual()` / `calibrateManually()` still work.
- `dropToManual()` → `step = .fineTune` (corners remain whatever they are — defaults if detect never populated them).
- `advance()`/`back()` clamp at the ends; never gated.
- `forExpressReCal(...)` → `CalibrationFlow(step: .fineTune, corners:..., layout:..., customDimensions:...)` with `overlayVisible = true`.

**Steps:**

- [ ] **2a. Write the failing test.** Create `CalibrationFlowTests.swift`:
  ```swift
  import XCTest
  import CoreGraphics
  @testable import PickleVisionCore

  final class CalibrationFlowTests: XCTestCase {

      // CHECKS NEVER GATE: Continue works even with 0/3 checks passing.
      func test_continue_from_position_ignores_failing_checks() {
          var f = CalibrationFlow()
          f.checks = SetupChecks(steady: false, framed: false, angle: false)
          XCTAssertEqual(f.checks.passingCount, 0)
          f.continueFromPosition()
          XCTAssertEqual(f.step, .detect)   // advanced despite all checks failing
      }

      func test_continue_from_position_with_partial_checks() {
          var f = CalibrationFlow()
          f.checks = SetupChecks(steady: true, framed: true, angle: false)
          XCTAssertEqual(f.checks.passingCount, 2)
          XCTAssertEqual(f.checks.total, 3)
          f.continueFromPosition()
          XCTAssertEqual(f.step, .detect)
      }

      // FAILED AUTO-DETECT LEAVES MANUAL PATH REACHABLE.
      func test_failed_autodetect_keeps_manual_reachable() {
          var f = CalibrationFlow()
          f.startAutoDetect()
          XCTAssertEqual(f.autoDetect, .finding)
          XCTAssertEqual(f.step, .detect)
          f.resolveAutoDetect(.failed, detectedCorners: nil)
          XCTAssertEqual(f.autoDetect, .failed)
          XCTAssertEqual(f.step, .detect)        // not forced forward/back
          f.dropToManual()
          XCTAssertEqual(f.step, .fineTune)      // guaranteed manual path
          XCTAssertTrue(f.isComplete)            // default corners present
      }

      func test_calibrate_manually_skips_detect() {
          var f = CalibrationFlow()
          f.calibrateManually()
          XCTAssertEqual(f.step, .fineTune)
      }

      func test_found_autodetect_copies_detected_corners() {
          var f = CalibrationFlow()
          let detected = [CGPoint(x: 0.25, y: 0.88), CGPoint(x: 0.78, y: 0.88),
                          CGPoint(x: 0.63, y: 0.32), CGPoint(x: 0.37, y: 0.32)]
          f.startAutoDetect()
          f.resolveAutoDetect(.found, detectedCorners: detected)
          XCTAssertEqual(f.autoDetect, .found)
          XCTAssertEqual(f.corners, detected)
      }

      func test_step_order_advance_and_back_clamp() {
          var f = CalibrationFlow()
          XCTAssertEqual(f.step, .position)
          f.advance(); XCTAssertEqual(f.step, .detect)
          f.advance(); XCTAssertEqual(f.step, .fineTune)
          f.advance(); XCTAssertEqual(f.step, .verify)
          f.advance(); XCTAssertEqual(f.step, .verify)   // clamped
          f.back(); XCTAssertEqual(f.step, .fineTune)
          f.back(); XCTAssertEqual(f.step, .detect)
          f.back(); XCTAssertEqual(f.step, .position)
          f.back(); XCTAssertEqual(f.step, .position)    // clamped
      }

      func test_court_model_and_fit_quality_available_when_complete() {
          let f = CalibrationFlow()   // default corners are a valid quad
          XCTAssertNotNil(f.courtModel)
          XCTAssertEqual(f.cornersSetCount, 4)
          XCTAssertEqual(f.fitQuality.quality, .good)
      }

      func test_express_recal_lands_on_finetune_with_loaded_corners() {
          let saved = [CGPoint(x: 0.2, y: 0.9), CGPoint(x: 0.8, y: 0.9),
                       CGPoint(x: 0.65, y: 0.3), CGPoint(x: 0.35, y: 0.3)]
          let f = CalibrationFlow.forExpressReCal(corners: saved,
                                                  layout: .tennisFrontBox,
                                                  customDimensions: nil)
          XCTAssertEqual(f.step, .fineTune)
          XCTAssertEqual(f.corners, saved)
          XCTAssertEqual(f.layout, .tennisFrontBox)
          XCTAssertTrue(f.overlayVisible)
      }

      func test_custom_dimensions_flow_into_court_model() {
          var f = CalibrationFlow()
          f.layout = .custom
          f.customDimensions = CustomDimensions(widthFeet: 18, lengthFeet: 40, nonVolleyZoneFeet: 7)
          XCTAssertEqual(f.courtModel?.profile.widthFeet, 18)
          XCTAssertEqual(f.courtModel?.profile.lengthFeet, 40)
      }
  }
  ```
- [ ] **2b. Run — confirm FAILS** (type missing):
  ```
  swift test --package-path PickleVisionCore --filter CalibrationFlowTests
  ```
  Expected: `cannot find 'CalibrationFlow' in scope`.
- [ ] **2c. Implement** `CalibrationFlow.swift`:
  ```swift
  import CoreGraphics

  public enum CalibrationStep: Int, CaseIterable, Equatable {
      case position, detect, fineTune, verify
  }

  /// ADVISORY ONLY — informs guidance copy, never gates a transition.
  public struct SetupChecks: Equatable {
      public var steady: Bool
      public var framed: Bool
      public var angle: Bool
      public init(steady: Bool = false, framed: Bool = false, angle: Bool = false) {
          self.steady = steady; self.framed = framed; self.angle = angle
      }
      public var passingCount: Int { [steady, framed, angle].filter { $0 }.count }
      public var total: Int { 3 }
  }

  public enum AutoDetectState: Equatable { case idle, finding, found, failed }

  public struct CalibrationFlow: Equatable {
      public private(set) var step: CalibrationStep
      public var checks: SetupChecks
      public var autoDetect: AutoDetectState

      public var corners: [CGPoint]
      public var layout: CourtLayout
      public var customDimensions: CustomDimensions?
      public var overlayVisible: Bool
      public var tapPoint: CGPoint?

      public init(step: CalibrationStep = .position,
                  corners: [CGPoint] = CalibrationDraft.defaultCorners(),
                  layout: CourtLayout = .regulationPickleball,
                  customDimensions: CustomDimensions? = nil) {
          self.step = step
          self.checks = SetupChecks()
          self.autoDetect = .idle
          self.corners = corners
          self.layout = layout
          self.customDimensions = customDimensions
          self.overlayVisible = (step == .fineTune || step == .verify)
          self.tapPoint = nil
      }

      public var draft: CalibrationDraft {
          CalibrationDraft(corners: corners, layout: layout, customDimensions: customDimensions)
      }
      public var courtModel: CourtModel? { draft.courtModel() }
      public var cornersSetCount: Int { min(corners.count, 4) }
      public var isComplete: Bool { draft.isComplete }
      public var fitQuality: (quality: FitQuality, residual: Double) {
          FitQuality.evaluate(corners: corners, layout: layout, customDimensions: customDimensions)
      }

      public mutating func goToStep(_ s: CalibrationStep) { step = s }

      public mutating func advance() {
          let next = min(step.rawValue + 1, CalibrationStep.verify.rawValue)
          step = CalibrationStep(rawValue: next)!
      }
      public mutating func back() {
          let prev = max(step.rawValue - 1, CalibrationStep.position.rawValue)
          step = CalibrationStep(rawValue: prev)!
      }

      public mutating func continueFromPosition() { step = .detect }     // ignores checks

      public mutating func calibrateManually() { step = .fineTune }

      public mutating func startAutoDetect() {
          step = .detect
          autoDetect = .finding
      }

      public mutating func resolveAutoDetect(_ result: AutoDetectState, detectedCorners: [CGPoint]?) {
          autoDetect = result
          if result == .found, let c = detectedCorners, c.count == 4 {
              corners = c
          }
      }

      public mutating func dropToManual() { step = .fineTune }

      public static func forExpressReCal(corners: [CGPoint],
                                         layout: CourtLayout,
                                         customDimensions: CustomDimensions?) -> CalibrationFlow {
          var f = CalibrationFlow(step: .fineTune, corners: corners,
                                  layout: layout, customDimensions: customDimensions)
          f.overlayVisible = true
          return f
      }
  }
  ```
- [ ] **2d. Run — confirm PASSES:**
  ```
  swift test --package-path PickleVisionCore --filter CalibrationFlowTests
  ```
  Expected: `Executed 9 tests, with 0 failures`.
- [ ] **2e. Full suite:** `swift test --package-path PickleVisionCore` → all pass.
- [ ] **2f. Commit + push:**
  ```
  git add -A && git commit -m "feat(core): CalibrationFlow — pure never-blocking wizard state machine (Plan 8 T2)" && git push origin main
  ```

---

### Task 3 — `CalibrationWizardView` host + `CalibrationModel` view-model (view)

The landscape host: frozen `latestImage` canvas on the left, a fixed **204pt** rail on the right, and a `switch` over `flow.step` that renders the right step view. An `ObservableObject` view-model wraps `CalibrationFlow` so SwiftUI observes it, and owns the freeze logic, the store, and the camera.

**Files:**
- Create `PickleVision/PickleVision/Calibration/CalibrationWizardView.swift`

**Interfaces (exact Swift):**
```swift
@MainActor final class CalibrationModel: ObservableObject {
    @Published var flow: CalibrationFlow
    @Published var frozen: CGImage?
    @Published var frozenSize: CGSize
    @Published var venueName: String
    @Published var saveError: String?
    @Published var showCustomDims: Bool
    @Published var showUltraWide: Bool

    let camera: CameraService
    private let store: CalibrationStore
    private var freezeSink: AnyCancellable?

    init(camera: CameraService, flow: CalibrationFlow = CalibrationFlow())
    func freeze()                       // capture latestImage (or first to arrive)
    func tapTest(viewPoint: CGPoint, viewSize: CGSize)   // -> flow.tapPoint
    func tapTestResult() -> (coords: String, inBounds: Bool)?   // "x 0.2 · y 12.6 ft"
    func save() -> Bool                 // persists StoredCalibration, returns success
}

struct CalibrationWizardView: View {
    @ObservedObject var model: CalibrationModel
}
```

**Layout contract (from screenshots 06–09):**
- Whole screen: `PVColor.panel` (or feed gradient) background, `.lockOrientation(.landscape)`.
- `HStack(spacing: 0)`: left = `canvas` (`.frame(maxWidth: .infinity)`, `.layoutPriority(1)`); right = the active step's **rail**, `.frame(width: 204)`, background `PVColor.rail`.
- `canvas`: if `model.frozen != nil` → `CalibrationView(image:imageSize:corners:)` (restyled, Task 6) for Fine-tune, else a static frozen `Image` with the relevant step overlay; if `nil` → a placeholder (`DashedPlaceholder` "Point at the court" / `ContentUnavailableView`). The canvas hosts step-specific overlays (framing guide, detected outline, court overlay, tap-test marker) layered over the image — passed in by each step view.
- Step `switch`: `.position → PositionStepView`, `.detect → AutoDetectStepView`, `.fineTune → FineTuneStepView`, `.verify → VerifyStepView`. Each receives `@ObservedObject model`.
- Present `CustomDimensionsSheet` via `.sheet(isPresented: $model.showCustomDims)` and `UltraWideFallbackCard` via `.sheet`/overlay on `$model.showUltraWide`.

**Steps:**

- [ ] **3a. Create the file** with `CalibrationModel`:
  - Port `freeze()` verbatim from the current `CalibrationScreen.swift` (lines ~156–171): use `camera.latestImage` if present else subscribe to `camera.$latestImage.compactMap{$0}.first()` on the main queue; set `frozen` + `frozenSize = camera.imageSize`. Capture the **first** frame on freeze (preserves the review-critical "capture first frame on freeze" behavior).
  - `tapTest(viewPoint:viewSize:)`: build `AspectFillMapper(viewSize: viewSize, contentSize: frozenSize)`, `let n = mapper.imageNormalized(fromView: viewPoint)`, set `flow.tapPoint = n` (only meaningful once `flow.courtModel != nil`).
  - `tapTestResult()`: guard `flow.courtModel`, `flow.tapPoint`; `let court = model.courtPoint(forImage: tapPoint)`; `let inB = model.isInBounds(courtPoint: court)`; return `(String(format: "x %.1f · y %.1f ft", court.x, court.y), inB)`. **No ± inches.**
  - `save()`: mirror current `save()` — trim `venueName` (fallback "My Court"), build `StoredCalibration(venueName:, layout: flow.layout, imageCorners: flow.corners.map { CodablePoint($0) }, customDimensions: flow.customDimensions, savedAt: Date())`, `try store.save(...)`; on throw set `saveError`, return false; else return true. **Persist `customDimensions`** (the old screen passed `nil` — fix that here so custom courts round-trip).
  - `store`: `CalibrationStore(directory: URL.documentsDirectory.appendingPathComponent("calibrations"))`.
- [ ] **3b. Create `CalibrationWizardView`** body: `GeometryReader` → `HStack(spacing: 0)` with the canvas (left) and the step-`switch` rail (right, `width: 204`). Add `.lockOrientation(.landscape)`, `.onAppear { model.camera.start(); model.freeze() }`, the `.alert` for `saveError` (binding mirrors current `saveErrorBinding`), and the two `.sheet`s. Use `PVColor` for backgrounds. For now, render a minimal placeholder rail per step (e.g., `Text("Step \(model.flow.step)")` inside `PVCard`) — the real step views land in Tasks 4–7; this task only proves the host + canvas + model compile and switch.
  - Add a top-left `InstrumentPill` reading `1080p · 120fps · level` style status only on Step 1 and a `FROZEN FRAME` `InstrumentPill` on Steps 3–4 (matches screenshots 06 / 08 / 09). These can be wired minimally now and refined per step view.
- [ ] **3c. Build** (`xcodebuild ...`) → **0 errors, 0 warnings** (grep log for `warning:` = empty).
- [ ] **3d. Commit + push:**
  ```
  git add -A && git commit -m "feat(app): CalibrationWizardView host + CalibrationModel (canvas + 204pt rail + step switch) (Plan 8 T3)" && git push origin main
  ```

---

### Task 4 — `PositionStepView` (Step 1, screenshot `06-calibrate-position`)

The POSITION CHECK guidance HUD. **`Continue anyway` is ALWAYS enabled.** Screenshot reference: `docs/design/screenshots/06-calibrate-position.png`.

**Files:**
- Create `PickleVision/PickleVision/Calibration/PositionStepView.swift`

**Interfaces:**
```swift
struct PositionStepView: View {
    @ObservedObject var model: CalibrationModel
}
```

**Canvas overlay (left, over the frozen frame):**
- A **dashed framing guide** rectangle (inset ~12% from edges) in `PVColor.optic.opacity(~0.5)`, plus four short **corner ticks** at the frame corners (yellow, ~24pt L-shapes).
- A faint partial court hint (optional — `CourtOverlay` at low opacity is fine, or skip).
- Centered caption "Fit the whole court in the frame" in `PVFont` body, `PVColor.onDark` muted.
- Top-left `InstrumentPill` "1080p · 120fps · level" (bind `model.camera.selectedFormatDescription` for the format token; "level" is a static label).

**Rail (right, 204pt) — top-to-bottom:**
- `StatusReadout` / mono label **"POSITION CHECK"** (`PVColor` mono label color, uppercase, letter-spaced).
- Three check rows, each = SF Symbol + label:
  - **Phone steady** — `checkmark.circle.fill`, `PVColor.optic` when `model.flow.checks.steady`, else amber.
  - **Whole court visible** — same pattern, bound to `checks.framed`.
  - **Raise mount ~1 ft** — `exclamationmark.circle.fill` in `PVColor.amber` when `checks.angle == false` (the "!" amber item in the shot).
  > Bind to `model.flow.checks`. Since sensing isn't wired in this plan, default `checks = SetupChecks(steady: true, framed: true, angle: false)` so the screen matches the screenshot's 2/3 state (set this default in `CalibrationModel.init` or here via `.onAppear`). This is **advisory only** — it must not affect button enabling.
- Note text: **"A higher angle sharpens near-line calls — but any angle still works."** (`PVFont` small, muted).
- `PrimaryButton("Continue anyway")` → `model.flow.continueFromPosition()`. **`.disabled(false)` — never gated.**
- `SecondaryButton("Calibrate manually")` → `model.flow.calibrateManually()`.
- Caption **"2 / 3 — go anyway"** — compute as `"\(model.flow.checks.passingCount) / \(model.flow.checks.total) — go anyway"`.
- Bottom-right of rail: a small text button **"Won't fit? Use 0.5× →"** → `model.showUltraWide = true`.

**Steps:**
- [ ] **4a.** Implement `PositionStepView` per the contract. Use only Plan-5 atoms (`InstrumentPill`, `StatusReadout`, `PrimaryButton`, `SecondaryButton`, `PVCard`) + SF Symbols + `PVColor`/`PVFont`. Draw the framing guide + corner ticks as the canvas overlay (pass it up to the host via the step's own `ZStack` over the image, OR have the host render the image and the step render the rail + an overlay layer — pick the simpler structure that keeps the rail at 204pt and the image clear). Verbatim copy as quoted above.
- [ ] **4b.** Wire it into `CalibrationWizardView`'s `.position` case (replace the Task-3 placeholder).
- [ ] **4c. Build** → 0 errors, 0 warnings.
- [ ] **4d. Visual gate:** compare against `docs/design/screenshots/06-calibrate-position.png` (USER on-device pass).
- [ ] **4e. Commit + push:**
  ```
  git add -A && git commit -m "feat(app): Step 1 PositionStepView — POSITION CHECK HUD, Continue-anyway always enabled (Plan 8 T4)" && git push origin main
  ```

---

### Task 5 — `AutoDetectStepView` (Step 2, screenshots `07-calibrate-autodetect` + `10-autodetect-failed`)

Idle / finding / found / failed states. The auto-detect **engine is STUBBED** here (Plan 3.5 fills it). The stub resolves to `.failed`, which surfaces the failed card → manual path; we also keep a `found` confirm path renderable for when the engine arrives.

**Files:**
- Create `PickleVision/PickleVision/Calibration/AutoDetectStepView.swift`

**Interfaces:**
```swift
struct AutoDetectStepView: View {
    @ObservedObject var model: CalibrationModel
}
```

**Engine stub (in `CalibrationModel`, add in this task):**
```swift
/// v1 stub for the (Plan 3.5) detector. Simulates a short scan, then resolves
/// to .failed so the user lands on the guaranteed manual path. Plan 3.5 will
/// replace the body with a real detector that may resolve to .found(corners).
func runAutoDetectStub() {
    flow.startAutoDetect()                 // autoDetect = .finding
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
        guard let self, self.flow.autoDetect == .finding else { return }
        self.flow.resolveAutoDetect(.failed, detectedCorners: nil)
    }
}
```
> Keep this honest: v1 cannot detect, so it fails to manual. Do NOT fabricate a `.found` with random corners. (If a "confirmable default" is preferred for demo, resolve to `.found` with `CalibrationDraft.defaultCorners()` — but the default/safe choice for v1 is `.failed → manual`. Implement `.failed`.)

**State rendering:**

**`.idle`** (entry before scan starts): canvas shows frozen frame; rail = `StatusReadout`/title + `PrimaryButton("Auto-detect")` → `model.runAutoDetectStub()` and `SecondaryButton("Calibrate manually instead")` → `model.flow.calibrateManually()`. (On entering `.detect` you may auto-start the stub via `.onAppear`; either is fine — keep manual reachable.)

**`.finding`** (screenshot 07 in-progress, described in handoff §5 Step 2 in-progress):
- Canvas: a moving **scan band** (an optic-yellow horizontal gradient strip animated top→bottom over the frozen frame) + a `ProgressView()` spinner tinted `PVColor.optic`.
- Rail/center: **"Finding the court…"** + `SecondaryButton("Calibrate manually instead")` → `calibrateManually()`.

**`.found`** (screenshot `07-calibrate-autodetect.png`):
- Canvas: detected court **outline** (trapezoid through `model.flow.corners` mapped via `AspectFillMapper`) in `PVColor.optic`, with the four corner **dots** (yellow fill + white ring) + the NVZ/net inner lines (use `CourtOverlay` with `model.flow.courtModel`).
- Top-left pill **"Court found"** (`InstrumentPill`, yellow dot + label) — **NO percentage** (honesty rule).
- Top-right copy **"Confirm the layout, or drag any corner."**
- Bottom-left `SegmentedChips` **Pickleball / Tennis box / Custom** bound to `model.flow.layout` (selecting **Custom** opens `model.showCustomDims = true`). Active chip = `PVColor.optic` + ink text (matches the yellow "Pickleball" chip in the shot).
- Bottom-right `PrimaryButton("Fine-tune →")` → `model.flow.advance()` (or `goToStep(.fineTune)`).

**`.failed`** (screenshot `10-autodetect-failed.png`):
- Centered card over the dimmed frozen frame:
  - Title **"Couldn't find the court"** (`PVFont` title, `PVColor.onDark`).
  - Body **"Faded paint or odd lighting can hide the lines. Drag the four corners yourself — it's the guaranteed path."**
  - `PrimaryButton("Drag the corners")` → `model.flow.dropToManual()` (→ Fine-tune).
  - `SecondaryButton("Try auto again")` → `model.runAutoDetectStub()`.

**Steps:**
- [ ] **5a.** Add `runAutoDetectStub()` to `CalibrationModel`.
- [ ] **5b.** Implement `AutoDetectStepView` with a `switch model.flow.autoDetect` over the four states, exact copy as above. Reuse `CourtOverlay` (Plan 5) for the found outline; `SegmentedChips` for layout; `InstrumentPill` for "Court found". The scan band = an animated `Rectangle().fill(LinearGradient(...PVColor.optic...))` with `.offset(y:)` driven by `withAnimation(.linear(...).repeatForever())`.
- [ ] **5c.** Wire into `CalibrationWizardView`'s `.detect` case. On entering `.detect` from `continueFromPosition()`, leave `autoDetect == .idle` (show idle with an Auto-detect button) **or** auto-run the stub — pick auto-run so the finding→failed flow is visible, then the failed card offers manual. Keep manual reachable in every sub-state.
- [ ] **5d. Build** → 0 errors, 0 warnings.
- [ ] **5e. Visual gate:** `docs/design/screenshots/07-calibrate-autodetect.png` (found + finding) and `docs/design/screenshots/10-autodetect-failed.png` (failed).
- [ ] **5f. Commit + push:**
  ```
  git add -A && git commit -m "feat(app): Step 2 AutoDetectStepView — idle/finding/found(no %)/failed; engine stubbed → manual (Plan 8 T5)" && git push origin main
  ```

---

### Task 6 — `FineTuneStepView` + restyle `CalibrationView` (Step 3, screenshot `08-calibrate-finetune-loupe`)

Reuse the existing `CalibrationView` (drag + loupe), restyled to optic-yellow tokens, with the active-handle halo + label; build the rail with LAYOUT chips (with dims), Court-overlay toggle, "4 / 4 corners set", Re-freeze / Save. Screenshot: `docs/design/screenshots/08-calibrate-finetune-loupe.png`.

**Files:**
- Modify `PickleVision/PickleVision/CalibrationView.swift`
- Create `PickleVision/PickleVision/Calibration/FineTuneStepView.swift`

**`CalibrationView` restyle (keep the API `image:imageSize:corners:`):**
- Replace `Color.yellow` with `PVColor.optic` everywhere (quad stroke, handle ring/dot, loupe ring stays white reticle on yellow line — match the shot: white ring around the loupe, optic-yellow line, white center cross).
- **Active handle** (the dragging one): enlarge to ~40pt ring + a soft `PVColor.optic.opacity(0.3)` **halo**, and show its label from `["nearLeft","nearRight","farRight","farLeft"]` (not the short "NL/NR/FR/FL" — the shot shows "farLeft"). Keep the short labels off; use the full names beside the active handle only.
- Loupe: keep the existing magnifier geometry; ring = white 2pt, center = white `plus`/reticle, the magnified line shows optic-yellow. Offset so the finger doesn't occlude it (existing logic).
- Hit targets ≥ 44pt (existing `within: 44`).
- This view stays the drag surface; `FineTuneStepView` hosts it in the canvas.

**`FineTuneStepView` rail (screenshot 08, right column "Calibrate"):**
- Title **"Calibrate"** (`PVFont` title, near-white).
- Mono sublabel **"DRAG TO THE LINES"**.
- Mono label **"LAYOUT"**, then three layout rows (use `SegmentedChips` or stacked chip rows — the shot shows stacked rows with a dim value on the right):
  - **Pickleball** · `20×44` (active = `PVColor.optic` fill + ink, like the shot).
  - **Tennis box** · `27×42`.
  - **Custom** · `set ft` → tapping opens `model.showCustomDims = true`.
  Bind selection to `model.flow.layout` (`.regulationPickleball` / `.tennisFrontBox` / `.custom`).
- **Court overlay** toggle (label + `Toggle` styled `.tint(PVColor.optic)`) bound to `model.flow.overlayVisible` (on by default — the shot shows it on).
- **"4 / 4 corners set"** with a yellow dot — text = `"\(model.flow.cornersSetCount) / 4 corners set"`.
- `SecondaryButton("Re-freeze")` → `model.freeze()`.
- `PrimaryButton("Save")` → `model.flow.advance()` (advance to **Verify** — Save here means "proceed to verify/save"; the actual persistence button is on Step 4 per screenshots 08 vs 09). Keep `Save` enabled only when `model.flow.isComplete` (always true with 4 corners) — do not block otherwise.
- Top-left of canvas: `InstrumentPill` **"FROZEN FRAME"** (yellow dot, two-line, matches shot).

**Canvas:** `CalibrationView(image: frozen, imageSize: frozenSize, corners: $model.flow.corners)` + (if `overlayVisible`) `CourtOverlay(model: courtModel, imageSize: frozenSize)` layered above.

> **Binding note:** `CalibrationView` takes `@Binding var corners`. Bind to `$model.flow.corners` (the published `flow`'s `corners` is settable). Changing a corner must recompute `courtModel`/`fitQuality` — they're derived getters, so they update automatically when `flow` republishes.

**Steps:**
- [ ] **6a.** Restyle `CalibrationView.swift` (tokens + active-handle halo + full-name label). Keep the public API unchanged so the existing call site still compiles.
- [ ] **6b.** Implement `FineTuneStepView` rail + canvas per the contract.
- [ ] **6c.** Wire into `CalibrationWizardView`'s `.fineTune` case.
- [ ] **6d. Build** → 0 errors, 0 warnings.
- [ ] **6e. Visual gate:** `docs/design/screenshots/08-calibrate-finetune-loupe.png`.
- [ ] **6f. Commit + push:**
  ```
  git add -A && git commit -m "feat(app): Step 3 FineTuneStepView — restyled drag+loupe, LAYOUT chips, overlay toggle, N/4 set (Plan 8 T6)" && git push origin main
  ```

---

### Task 7 — `VerifyStepView` (Step 4, screenshot `09-calibrate-taptest-save`)

Tap-test (court coords + IN/OUT only, **no ± inches**), venue-name field, FIT QUALITY block (qualitative + 4-seg bar from `FitQuality`), Back / Save court → `CalibrationStore.save`. Screenshot: `docs/design/screenshots/09-calibrate-taptest-save.png`.

**Files:**
- Create `PickleVision/PickleVision/Calibration/VerifyStepView.swift`

**Interfaces:**
```swift
struct VerifyStepView: View {
    @ObservedObject var model: CalibrationModel
    var onSaved: () -> Void     // dismiss the wizard after a successful save
}
```

**Canvas (left):**
- Frozen frame + `CourtOverlay(model: courtModel, imageSize: frozenSize)` (zones: blue in-bounds fill, green apron, optic-yellow lines — the shot shows the filled zones).
- Top-left `InstrumentPill` **"TAP TO TEST THE MAP"**.
- A tap-catcher (`Color.clear.contentShape(Rectangle()).onTapGesture { loc in model.tapTest(viewPoint: loc, viewSize: geo.size) }`).
- If `model.flow.tapPoint != nil` and `model.tapTestResult()` is non-nil: draw a marker dot at the tapped view point and a small readout card near it showing **"x 0.2 · y 12.6 ft"** (from `result.coords`) + **`IN`** (`PVColor.inBounds` blue) or **`OUT`** (`PVColor.outBounds` green) — color-coded per handoff (IN=blue `#4d9bff`, OUT=green `#46c46a`). **No "± inches".**

**Rail (right):**
- Title **"Save court"** (`PVFont` title).
- Mono sublabel **"STORED ON DEVICE"**.
- Mono label **"VENUE NAME"** + a `TextField` bound to `$model.venueName` with an optic-yellow caret (`.tint(PVColor.optic)`), `PVCard`-style boxed field (matches "Riverside · Court 3" in the shot).
- **FIT QUALITY** block (use a `PVCard`):
  - Mono label "FIT QUALITY" on the left; the qualitative label (`model.flow.fitQuality.quality.label`, e.g. "Good") on the right in `PVColor.inBounds` blue (the shot shows "Good" in blue).
  - A **4-segment bar**: 4 rounded rectangles; fill `FitQuality.barSegments(for: model.flow.fitQuality.residual)` of them with `PVColor.inBounds` (blue, as in the shot), the rest with a dim track color.
  - **"4 / 4 corners set"** with a yellow dot — `"\(model.flow.cornersSetCount) / 4 corners set"`.
  - Note (muted, small): **"From corner-fit residual. Per-zone ± inches arrive in Phase 2."**
- `SecondaryButton("Back")` → `model.flow.back()` (→ Fine-tune).
- `PrimaryButton("Save court")` → `if model.save() { onSaved() }` (persists `StoredCalibration`, then dismiss the wizard). On failure the host's `saveError` alert shows.

**Steps:**
- [ ] **7a.** Implement `VerifyStepView` per the contract — tap-test readout (IN/OUT + coords only), venue field, FIT QUALITY (consume Task 1's `FitQuality` via `model.flow.fitQuality` + `FitQuality.barSegments`), Back / Save court.
- [ ] **7b.** Wire into `CalibrationWizardView`'s `.verify` case, passing `onSaved: { dismiss() }` (the host owns `@Environment(\.dismiss)`).
- [ ] **7c. Build** → 0 errors, 0 warnings.
- [ ] **7d. Visual gate:** `docs/design/screenshots/09-calibrate-taptest-save.png`.
- [ ] **7e. Commit + push:**
  ```
  git add -A && git commit -m "feat(app): Step 4 VerifyStepView — tap-test IN/OUT+coords, venue field, FIT QUALITY bar, Save court (Plan 8 T7)" && git push origin main
  ```

---

### Task 8 — `CustomDimensionsSheet` + `UltraWideFallbackCard` (edge cases)

The custom-layout dimensions entry and the 0.5× ultra-wide fallback card. Both are non-blocking. Handoff §6.

**Files:**
- Create `PickleVision/PickleVision/Calibration/CustomDimensionsSheet.swift`
- Create `PickleVision/PickleVision/Calibration/UltraWideFallbackCard.swift`

**`CustomDimensionsSheet` interfaces:**
```swift
struct CustomDimensionsSheet: View {
    @Binding var customDimensions: CustomDimensions?
    @Binding var layout: CourtLayout
    var onApply: () -> Void           // dismiss + recompute
}
```
**Contract (handoff §6 custom card):**
- Title/label area + three numeric fields **Width** / **Length** / **Kitchen (NVZ)** in feet, defaults **18.0 / 40.0 / 7.0** (per task scope; handoff also shows these as the custom defaults).
  > The repo's `CourtProfile.make(.custom, custom: nil)` defaults to 20/44/7, but the **UI defaults for the Custom entry card are 18/40/7** per task scope + handoff §6 — seed the fields with 18/40/7.
- Each field: `TextField` + `.keyboardType(.decimalPad)`, parsed to `Double` (reject non-positive; keep last valid).
- `PrimaryButton("Apply dimensions")` → set `customDimensions = CustomDimensions(widthFeet:, lengthFeet:, nonVolleyZoneFeet:)`, set `layout = .custom`, call `onApply()` (dismiss). This maps 1:1 to `CustomDimensions(widthFeet, lengthFeet, nonVolleyZoneFeet)`.
- Styled as a dark `PVCard`; optic-yellow caret on fields.

**`UltraWideFallbackCard` interfaces:**
```swift
struct UltraWideFallbackCard: View {
    var onSwitch: () -> Void      // user chose 0.5× (no engine yet — record/intent only)
    var onKeep: () -> Void        // keep 1×, dismiss
}
```
**Contract (handoff §6 0.5× card):**
- Title **"Court won't fit at 1×"**.
- Body **"Switch to the 0.5× ultra-wide. It needs a one-time lens-distortion calibration — its barrel curve would otherwise warp the map."**
- `PrimaryButton("Switch to 0.5×")` → `onSwitch()` (in v1 there is no ultra-wide lens-distortion engine, so this just dismisses; leave a `// TODO: Plan — ultra-wide lens-distortion calibration` marker).
- `SecondaryButton("Keep 1×")` → `onKeep()`.
- Dark `PVCard`.

**Steps:**
- [ ] **8a.** Implement both views with exact copy.
- [ ] **8b.** Present `CustomDimensionsSheet` from `CalibrationWizardView` via `.sheet(isPresented: $model.showCustomDims)` with bindings `customDimensions: $model.flow.customDimensions`, `layout: $model.flow.layout`, `onApply: { model.showCustomDims = false }`. Present `UltraWideFallbackCard` via `.sheet(isPresented: $model.showUltraWide)` with `onSwitch: { model.showUltraWide = false }`, `onKeep: { model.showUltraWide = false }`. (Both are already referenced by `showCustomDims`/`showUltraWide` from Tasks 3–7.)
- [ ] **8c. Build** → 0 errors, 0 warnings.
- [ ] **8d. Visual gate:** the "CALIBRATION EDGE CASES" strip (custom-dims + 0.5× cards) — visible bottom of `06-calibrate-position.png` and the handoff §6 description.
- [ ] **8e. Commit + push:**
  ```
  git add -A && git commit -m "feat(app): CustomDimensionsSheet + UltraWideFallbackCard (calibration edge cases) (Plan 8 T8)" && git push origin main
  ```

---

### Task 9 — Swap `CalibrationScreen` to host the wizard + express-re-cal entry

Replace the old single-screen body with the wizard, preserving `freeze()` / session reuse, and add the express-re-cal entry point that lands on Step 3 (Fine-tune) preloaded from a `StoredCalibration`.

**Files:**
- Modify `PickleVision/PickleVision/CalibrationScreen.swift`

**Interfaces (exact Swift):**
```swift
struct CalibrationScreen: View {
    @ObservedObject var camera: CameraService
    /// When set, express re-calibration: preload these corners + layout and
    /// open directly on Step 3 (Fine-tune), skipping Position + Detect.
    var reCalibrate: StoredCalibration? = nil

    @StateObject private var model: CalibrationModel

    init(camera: CameraService, reCalibrate: StoredCalibration? = nil)
}
```

**Contract:**
- `init`: build the initial `CalibrationFlow`:
  - If `reCalibrate != nil`: `CalibrationFlow.forExpressReCal(corners: stored.imageCorners.map { $0.cgPoint }, layout: stored.layout, customDimensions: stored.customDimensions)` (lands on `.fineTune`, overlay on). Also seed `model.venueName = stored.venueName`.
  - Else: `CalibrationFlow()` (starts on `.position`).
  - Wrap in `CalibrationModel(camera: camera, flow: ...)` assigned to a `@StateObject` (use the `_model = StateObject(wrappedValue:)` pattern in `init`).
- `body`: `CalibrationWizardView(model: model)` with `.navigationTitle("Calibrate")`, `.navigationBarTitleDisplayMode(.inline)`. The wizard already applies `.lockOrientation(.landscape)` and `.onAppear { camera.start(); freeze() }`.
- **Preserve** the `freeze()` / first-frame-on-freeze behavior (now in `CalibrationModel`) and the session-alive-across-nav behavior (the camera is the `@ObservedObject` passed in by the caller — unchanged; the existing review-critical fixes carry over because we reuse the same camera instance and the same freeze logic).
- The `Home`/`SavedCourtCard` ↻ affordance (Plan 6) navigates to `CalibrationScreen(camera:, reCalibrate: storedCalibration)`. **This task only needs to expose the `reCalibrate:` parameter and the express path**; the Home call site is wired in Plan 6 (or here if the nav link already exists — check `HomeView.swift` and, if a calibration nav link exists, pass `reCalibrate:` through; otherwise leave the parameter ready for Plan 6).

**Steps:**
- [ ] **9a.** Rewrite `CalibrationScreen.swift` to the host shape above. Delete the old single-screen `frameArea`/`controls`/`tapTestCatcher`/`save()`/`freeze()` bodies (their logic now lives in `CalibrationModel` + the step views). Keep the file's `import`s (`SwiftUI`, `Combine`, `PickleVisionCore`).
- [ ] **9b.** Check `HomeView.swift` for an existing calibration nav entry; if present, thread `reCalibrate:` through the express ↻ path. If Plan 6's Home isn't built yet, leave the `reCalibrate:` parameter in place (defaulted `nil`) so the standard "Start a session → Calibrate" path still compiles and works.
- [ ] **9c. Build** → 0 errors, 0 warnings.
- [ ] **9d. Full nav check (USER):** standard path (Camera → Calibrate → Position → Detect(fail) → Fine-tune → Verify → Save → back to list) and express path (saved-court ↻ → opens on Fine-tune with corners + layout preloaded). Visual gates: all of `06`–`10`.
- [ ] **9e. Run full core suite once more:** `swift test --package-path PickleVisionCore` → all pass (no core regressions).
- [ ] **9f. Commit + push:**
  ```
  git add -A && git commit -m "feat(app): host CalibrationWizard in CalibrationScreen; express re-cal lands on Fine-tune (Plan 8 T9)" && git push origin main
  ```

---

## Self-review — handoff coverage map

Every handoff step/state for Plan 8 maps to a task. **No placeholders; no gaps for v1 scope.**

| Handoff step / state | Source (handoff §) | Screenshot | Task |
|---|---|---|---|
| **FitQuality** (qualitative + 4-seg bar from reprojection residual) | §5 Step 4, §8/8a | (in 09) | **T1** |
| **CalibrationFlow** (Step enum, advisory SetupChecks never gating, AutoDetectState, draft) | §Interactions, §State Mgmt | (system) | **T2** |
| Checks NEVER gate Continue | §Interactions, spec §2.2 | — | T2 (test) + T4 |
| Failed auto-detect leaves manual path reachable | §5 Step 2 hard-fail, §Interactions | 10 | T2 (test) + T5 |
| Wizard host: frozen canvas + 204pt rail + step switch | §5 (204px rail) | 06–09 | **T3** |
| **Step 1 Position** — POSITION CHECK HUD (steady/framed/raise-mount), Continue-anyway always enabled, Calibrate manually, "2/3 — go anyway", "Won't fit? Use 0.5×" | §5 Step 1 | **06** | **T4** |
| **Step 2 AutoDetect — idle** | §5 Step 2 | (07 strip) | **T5** |
| **Step 2 AutoDetect — finding** ("Finding the court…" scan+spinner, Calibrate manually instead) | §5 Step 2 in-progress | (07) | **T5** |
| **Step 2 AutoDetect — found** ("Court found", **no %**, layout chips Pickleball/Tennis box/Custom, "Fine-tune →") | §5 Step 2 v1 | **07** | **T5** |
| **Step 2 AutoDetect — failed** ("Couldn't find the court", Drag the corners / Try auto again) — engine **stubbed → .failed** | §5 Step 2 hard-fail | **10** | **T5** |
| **Step 3 Fine-tune** — reuse CalibrationView drag+loupe (restyled), LAYOUT chips w/ dims, Court-overlay toggle, "4/4 corners set", Re-freeze/Save | §5 Step 3 | **08** | **T6** |
| **Step 4 Verify/Save** — tap-test "x · y ft" + IN/OUT only (CourtModel.courtPoint+isInBounds), **no ±in**, venue field, FIT QUALITY block + Phase-2 note, Back/Save court → CalibrationStore.save | §5 Step 4 | **09** | **T7** |
| **Custom dimensions** (Width/Length/Kitchen ft → CustomDimensions, defaults 18/40/7) | §6 | (edge-case strip) | **T8** |
| **0.5× ultra-wide fallback** ("Court won't fit at 1×" → Switch to 0.5× / Keep 1×) | §6 | (edge-case strip) | **T8** (card) + **T4** (entry) |
| **Express re-calibrate** (↻ saved court → lands on Step 3 Fine-tune with preloaded corners+layout) | §Interactions | — | **T2** (`forExpressReCal`) + **T9** (entry) |
| **Phase-2 numbers** (detect %, per-zone ±in, distance-from-line) | §7 | (aspirational) | **EXCLUDED from v1 by design (honesty rule)** |

**Honesty-rule audit:** no detect %, no ±inches, no fabricated accuracy anywhere — only IN/OUT, court coords, "N/4 corners set", and the qualitative fit label + bar (residual-driven, value never displayed). ✅
**Never-hard-block audit:** `continueFromPosition()` ignores checks (T2 test); `calibrateManually()` always reachable (T2/T4/T5); auto-detect `.failed` → manual via `dropToManual()` (T2 test, T5 UI). ✅
**Bind-to-existing-types audit:** only new types are `FitQuality` + `CalibrationFlow`; everything else uses `CalibrationDraft`/`CourtModel`/`CourtProfile`/`CustomDimensions`/`CalibrationStore`/`StoredCalibration`/`AspectFillMapper`/`CameraService`. ✅
**Coordinate-space audit:** corners normalized `[0,1]`; `FitQuality` residual + all `CourtModel` calls operate in normalized image space; views map view→normalized via `AspectFillMapper` first. ✅
