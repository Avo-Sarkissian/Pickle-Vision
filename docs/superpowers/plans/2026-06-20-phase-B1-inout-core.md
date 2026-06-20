# Phase B1: In/Out Core (deterministic) - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Turn a ball trajectory (image points over time) plus a `CourtModel` into bounce events and honest line calls (in / out / too-close-to-call), with zero ML and zero device dependency.

**Architecture:** Pure value types and functions in `PickleVisionCore`. A `Tracker` smooths a noisy, gappy sequence of `BallObservation` into a `BallTrack`. A `BounceDetector` finds bounces as vertical-image-velocity sign flips (down then up), sub-frame interpolated. A `LineJudge` maps the bounce point through `CourtModel` (valid only at the bounce, where the ball is on the ground) and returns a `LineCall` with a physics uncertainty band. A `RefereeCore` facade chains them. Everything is unit-tested against synthetic trajectories; recorded-clip fixtures plug in later (Phase B5).

**Tech Stack:** Swift, `CoreGraphics`, `simd` (already used), XCTest. No new dependencies.

## Global Constraints

- No em-dashes in prose or comments. Hyphens only.
- Depends only on `CourtModel`; never reaches into the calibration/persistence layer.
- Honesty/physics: single-camera calls are advisory. Within the uncertainty band the verdict is `tooCloseToCall`. No fabricated precision.
- Image points are normalized [0,1] to the frame, matching the calibration convention.
- Key physics caveat to document in code: an airborne ball does NOT map correctly to court space through the ground homography (parallax). Only the bounce point (ball on the ground) maps validly. Bounce detection therefore happens in image space; court mapping happens only at the detected bounce.
- Verification: `swift test`. This whole phase is testable without a camera.

---

### Task B1.1: BallObservation, BallTrack, Tracker

**Files:**
- Create: `PickleVisionCore/Sources/PickleVisionCore/BallTracking.swift`
- Test: `PickleVisionCore/Tests/PickleVisionCoreTests/TrackerTests.swift`

**Interfaces:**
- Produces:
  - `struct BallObservation: Equatable { var imagePoint: CGPoint; var time: TimeInterval; var confidence: Double }`
  - `struct TrackSample: Equatable { var imagePoint: CGPoint; var time: TimeInterval; var velocity: CGVector /* image units per second */ }`
  - `struct BallTrack: Equatable { var samples: [TrackSample] }`
  - `struct Tracker { var minConfidence: Double = 0.3; var maxGap: TimeInterval = 0.1; func track(_ observations: [BallObservation]) -> BallTrack }`

**Algorithm:** drop observations below `minConfidence`; sort by time; reject single-point spatial outliers (a point whose jump from both neighbours exceeds a multiple of the local median step); fill gaps up to `maxGap` by linear interpolation; compute velocity by central finite difference. Keep it simple and deterministic. (A Kalman filter is a later upgrade, noted, not required for B1.)

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class TrackerTests: XCTestCase {
    private func obs(_ x: Double, _ y: Double, _ t: Double, _ c: Double = 1) -> BallObservation {
        BallObservation(imagePoint: CGPoint(x: x, y: y), time: t, confidence: c)
    }

    func test_low_confidence_observations_dropped() {
        let track = Tracker().track([obs(0.1,0.1,0), obs(0.9,0.9,0.01,0.05), obs(0.2,0.2,0.02)])
        XCTAssertEqual(track.samples.count, 2)   // the 0.05-confidence outlier is dropped
    }

    func test_velocity_is_finite_difference() {
        // Constant rightward motion: x = t, y = 0.5
        let track = Tracker().track([obs(0.0,0.5,0), obs(0.1,0.5,0.1), obs(0.2,0.5,0.2)])
        let mid = track.samples[1]
        XCTAssertEqual(mid.velocity.dx, 1.0, accuracy: 1e-6)   // 0.2 over 0.2s
        XCTAssertEqual(mid.velocity.dy, 0.0, accuracy: 1e-6)
    }

    func test_spatial_outlier_rejected() {
        let track = Tracker().track([obs(0.10,0.5,0), obs(0.95,0.5,0.01), obs(0.12,0.5,0.02), obs(0.14,0.5,0.03)])
        XCTAssertFalse(track.samples.contains { abs($0.imagePoint.x - 0.95) < 1e-9 })
    }
}
```

- [ ] **Step 2: Run, confirm failure.** `swift test --package-path PickleVisionCore --filter TrackerTests` -> FAIL.

- [ ] **Step 3: Implement `BallTracking.swift`** with the types above and the `Tracker.track` algorithm (confidence filter -> sort -> outlier rejection -> central-difference velocity). Document the gap-fill and outlier rule inline.

- [ ] **Step 4: Run, confirm pass.**

- [ ] **Step 5: Commit** `feat(core): BallObservation/BallTrack + deterministic Tracker`.

---

### Task B1.2: BounceDetector

**Files:**
- Create: `PickleVisionCore/Sources/PickleVisionCore/BounceDetector.swift`
- Test: `PickleVisionCore/Tests/PickleVisionCoreTests/BounceDetectorTests.swift`

**Interfaces:**
- Consumes: `BallTrack`, `TrackSample`.
- Produces:
  - `struct Bounce: Equatable { var imagePoint: CGPoint; var time: TimeInterval; var prominence: Double }`
  - `struct BounceDetector { var minProminence: Double = 0.01; func bounces(in track: BallTrack) -> [Bounce] }`

**Algorithm:** a bounce is where vertical image velocity `dy` flips from positive (moving down the screen) to negative (moving up). Find sign changes of `dy` from + to -; interpolate the zero-crossing time and image point between the bracketing samples; `prominence` = local image-y travel around the event (to reject jitter). Document the parallax caveat (this is the ground-contact instant; airborne mapping is invalid).

- [ ] **Step 1: Write failing test (synthetic bounce)**

```swift
import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class BounceDetectorTests: XCTestCase {
    // Ball falls (image-y increasing) to a low point then rises: one bounce.
    private func parabolaTrack() -> BallTrack {
        // y(t) peaks (max image-y) at t=0.5; x drifts right.
        var obs: [BallObservation] = []
        for i in 0...10 {
            let t = Double(i) * 0.1
            let y = 0.9 - 4 * (t - 0.5) * (t - 0.5)   // max at t=0.5, y=0.9
            obs.append(BallObservation(imagePoint: CGPoint(x: 0.2 + 0.05 * t, y: y), time: t, confidence: 1))
        }
        return Tracker().track(obs)
    }

    func test_detects_single_bounce_near_low_point() {
        let bounces = BounceDetector().bounces(in: parabolaTrack())
        XCTAssertEqual(bounces.count, 1)
        XCTAssertEqual(bounces[0].time, 0.5, accuracy: 0.06)
        XCTAssertEqual(bounces[0].imagePoint.y, 0.9, accuracy: 0.02)
    }

    func test_monotonic_motion_has_no_bounce() {
        let obs = (0...5).map { BallObservation(imagePoint: CGPoint(x: 0.2, y: 0.1 + 0.1 * Double($0)), time: Double($0) * 0.1, confidence: 1) }
        XCTAssertTrue(BounceDetector().bounces(in: Tracker().track(obs)).isEmpty)
    }
}
```

- [ ] **Step 2: Run, confirm failure.**
- [ ] **Step 3: Implement `BounceDetector.swift`** (dy sign-flip + sub-frame interpolation + prominence gate).
- [ ] **Step 4: Run, confirm pass.**
- [ ] **Step 5: Commit** `feat(core): BounceDetector via vertical-image-velocity sign flip`.

---

### Task B1.3: CourtModel.distanceToBoundary + LineJudge

**Files:**
- Modify: `PickleVisionCore/Sources/PickleVisionCore/CourtModel.swift`
- Create: `PickleVisionCore/Sources/PickleVisionCore/LineJudge.swift`
- Test: `PickleVisionCore/Tests/PickleVisionCoreTests/LineJudgeTests.swift`

**Interfaces:**
- Add to `CourtModel`: `func distanceToInBoundsBoundaryFeet(courtPoint: CGPoint) -> Double` (>= 0, min distance to any in-bounds polygon edge; reuses the existing private `distanceToSegment`).
- Produces:
  - `enum LineVerdict: Equatable { case `in`, out, tooCloseToCall }`
  - `struct LineCall: Equatable { var verdict: LineVerdict; var distanceToLineFeet: Double; var uncertaintyBandFeet: Double }`
  - `struct LineJudge { var uncertaintyBandFeet: Double = 0.33; func call(bounce: Bounce, court: CourtModel) -> LineCall? }` (returns nil if the bounce point cannot be mapped, e.g. non-finite).

**Logic:** `court.courtPoint(forImage: bounce.imagePoint)` (guard finite); `d = distanceToInBoundsBoundaryFeet`; `inside = isInBounds`; if `d <= uncertaintyBandFeet` -> `.tooCloseToCall`; else `inside ? .in : .out`. The default band (~4 inches) is a placeholder for the single-camera reality; document that a principled band would propagate pixel error through the homography Jacobian (future refinement).

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class LineJudgeTests: XCTestCase {
    // Court model from a clean normalized quad (regulation 20x44).
    private func model() -> CourtModel {
        let corners = [CGPoint(x:0.18,y:0.82), CGPoint(x:0.82,y:0.82), CGPoint(x:0.64,y:0.30), CGPoint(x:0.36,y:0.30)]
        return CalibrationDraft(corners: corners, layout: .regulationPickleball).courtModel()!
    }
    private func bounce(atCourt c: CGPoint, using m: CourtModel) -> Bounce {
        Bounce(imagePoint: m.imagePoint(forCourt: c)!, time: 0, prominence: 1)
    }

    func test_clearly_inside_is_in() {
        let m = model()
        let call = LineJudge().call(bounce: bounce(atCourt: CGPoint(x: 10, y: 22), using: m), court: m)!
        XCTAssertEqual(call.verdict, .in)
    }

    func test_clearly_outside_is_out() {
        let m = model()
        let call = LineJudge().call(bounce: bounce(atCourt: CGPoint(x: -2, y: 22), using: m), court: m)!
        XCTAssertEqual(call.verdict, .out)
    }

    func test_within_band_is_too_close() {
        let m = model()
        // 1 inch inside the x=0 sideline at mid-court.
        let call = LineJudge(uncertaintyBandFeet: 0.33).call(bounce: bounce(atCourt: CGPoint(x: 0.08, y: 22), using: m), court: m)!
        XCTAssertEqual(call.verdict, .tooCloseToCall)
    }
}
```

- [ ] **Step 2: Run, confirm failure.**
- [ ] **Step 3: Implement** `distanceToInBoundsBoundaryFeet` on `CourtModel` (expose distance to nearest polygon edge) and `LineJudge.swift`.
- [ ] **Step 4: Run, confirm pass.**
- [ ] **Step 5: Commit** `feat(core): LineJudge with too-close-to-call band + CourtModel boundary distance`.

---

### Task B1.4: RefereeCore facade (trajectory -> calls)

**Files:**
- Create: `PickleVisionCore/Sources/PickleVisionCore/RefereeCore.swift`
- Test: `PickleVisionCore/Tests/PickleVisionCoreTests/RefereeCoreTests.swift`

**Interfaces:**
- Consumes: `BallObservation`, `Tracker`, `BounceDetector`, `LineJudge`, `CourtModel`.
- Produces:
  - `struct JudgedBounce: Equatable { var bounce: Bounce; var courtPoint: CGPoint; var call: LineCall }`
  - `struct RefereeCore { var tracker = Tracker(); var detector = BounceDetector(); var judge = LineJudge(); func evaluate(_ observations: [BallObservation], court: CourtModel) -> [JudgedBounce] }`

**Logic:** `track -> bounces -> for each bounce, judge -> JudgedBounce` (skip bounces that fail to map). This is the unit Phase B3 calls with detector output, and Phase B5 measures against tap-test ground truth.

- [ ] **Step 1: Write failing test (synthetic rally with one in, one out)**

Construct two parabola segments whose low points map (via a known `CourtModel`) to a clearly-inside court point and a clearly-outside one; assert `evaluate` returns two `JudgedBounce`s with `.in` then `.out`.

- [ ] **Step 2: Run, confirm failure.**
- [ ] **Step 3: Implement `RefereeCore.swift`.**
- [ ] **Step 4: Run, confirm pass.**
- [ ] **Step 5: Commit** `feat(core): RefereeCore facade (trajectory -> judged bounces)`.

---

## Self-review notes

- Spec coverage: tracking (B1.1), bounce detection (B1.2), in/out + too-close band (B1.3), end-to-end facade (B1.4). Covered.
- Type consistency: `BallObservation`, `TrackSample`, `BallTrack`, `Bounce`, `LineCall`, `JudgedBounce` are defined once and reused. `imagePoint` is normalized [0,1] everywhere.
- No ML, no device, no data: the entire phase is synthetic-fixture testable now. This is the deliberate "deterministic spine" from the roadmap.
- Boundary held: only `CourtModel` is consumed; `distanceToInBoundsBoundaryFeet` is added to `CourtModel` itself (it is court geometry), keeping callers off the calibration internals.

## Known limitations to carry forward (flag, do not silently hide)

- The bounce heuristic (image-y velocity sign flip) assumes a camera roughly behind/above the baseline; a steep cross-court bounce or heavy spin can confound it. Phase B5's recorded-clip fixtures are where this gets stress-tested.
- The uncertainty band is a fixed default (~4 in). A principled, position-dependent band via the homography Jacobian is a worthwhile later refinement; until then the band is conservative and honest.
- Real ball positions come from Phase B2; B1 is validated on synthetic and (in B5) hand-labeled trajectories.
