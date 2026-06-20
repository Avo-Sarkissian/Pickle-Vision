# Pickle-Vision Roadmap: to a SwingVision-class product

Last updated 2026-06-20. This is the master roadmap. It names the phases, their
order, the architecture spine, and the interfaces that span phases. Each phase
links to its own plan (detailed for near-term, scope-level for later).

Read `docs/CONSIDERATIONS.md` first. The principles there govern every phase. In
short: personal tool for one user on a few known courts; scope discipline over
feature count; physics sets the accuracy ceiling (advisory calls, not Hawk-Eye);
`CourtModel` is the load-bearing boundary; push intelligence into deterministic
code and concentrate the ML/data problem onto the ball detector; capture-then-
process is fine; let real on-court usage pull the next phase; a CV feature is
"done" only when it works on a real court.

## The destination

A single mounted iPhone that, after a one-time court calibration, watches a
match and produces: line calls (in/out), kitchen (non-volley-zone) faults,
rally and shot segmentation, automatic scoring, shot speed and placement stats,
and a review experience with synced overlays and highlights. The honest
framing: every spatial call is advisory and carries a "too close to call" band
set by single-camera physics, never a fabricated precision number.

## Architecture spine (holds across all phases)

```
Camera/clip --> [BallDetector] --> BallObservation[]  --\
                                                          >--> [Tracker] --> BallTrack --> [BounceDetector] --> BounceEvent --> [LineJudge(CourtModel)] --> LineCall
Camera/clip --> [PlayerDetector] --> PlayerObservation[] -/                                                                        |
                                                                                                                                   v
                                                                                          [RallyModel] --> [Scorer] --> Score / Stats / Review
```

- The **neural nets do one job each**: locate the ball, locate players. Everything
  after a detection is deterministic, debuggable with a calculator, and lives in
  `PickleVisionCore` so it is device-agnostic and unit-testable against fixtures.
- **Detectors sit behind protocols** (`BallDetector`, `PlayerDetector`), exactly
  as calibration sits behind `CourtModel`. The model/version (TrackNet, YOLO26,
  etc.) is an implementation detail swappable without touching tracking or physics.
- **Capture-then-process** is the default execution model. A recorded clip plus
  its `CourtModel` is the unit everything downstream consumes. Live/real-time is a
  later optimization gated on thermals.

## Shared interface vocabulary

These types are introduced by the phase that first needs them and are reused
downstream. Names are normative so every phase plan stays consistent. All image
points are normalized [0,1] to the capture frame (matching the calibration
convention), so they are resolution-independent.

- `CourtModel` (exists): image <-> court homography, `isInBounds`, court geometry.
- `BallObservation { imagePoint: CGPoint /* normalized */, time: TimeInterval, confidence: Double }`
- `BallDetector` (protocol): `func detect(in frame) -> [BallObservation]` (zero or more candidates per frame, with confidence).
- `BallTrack`: smoothed, gap-filled trajectory of `BallObservation`s with velocity.
- `BounceEvent { imagePoint, courtPoint: CGPoint, time, incomingVelocity }` (a bounce = vertical-image-velocity sign flip, sub-frame interpolated).
- `LineCall { verdict: .in | .out | .tooCloseToCall, distanceToLineFeet: Double, uncertaintyBandFeet: Double }`
- `LineJudge`: maps a `BounceEvent` through `CourtModel` to a `LineCall`, applying the physics uncertainty band.
- `SessionClip { id, courtID: UUID, fps: Double, frameSize: CGSize, recordedAt: Date, url }` (a recording bound to the court it was shot on).
- `PlayerObservation`, `PlayerTrack` (Phase D), `RallyModel`, `Score` (Phase E), `ShotStat` (Phase F).

## Phases

Phase 0-1 are done. Phase letters avoid clashing with the old implementation
"Plan 1-8" numbers (those were the foundation/UI plans inside Phase 0-1).

| Phase | Title | Delivers | Depends on | Plan status |
|---|---|---|---|---|
| 0-1 | Foundation | App shell, camera, manual calibration, `CourtModel`, Direction-B UI, capture profiles, thermal policy, drift-guard UI | - | DONE |
| **A** | **Session + Capture** | Tap a saved court -> live session with its overlay; record a clip bound to the court; clip library | 0-1 | **Detailed plan** |
| **B1** | **In/Out core (deterministic)** | `Tracker` + `BounceDetector` + `LineJudge` in `PickleVisionCore`; in/out + too-close-to-call from a ball trajectory; TDD on synthetic + recorded fixtures | A (clips), `CourtModel` | **Detailed plan** |
| B2 | Ball detector | `BallDetector` impl developed/measured against real clips, off-device first; detection-at-bounce metric | A (clips), B1 (consumer) | Scope |
| B3 | In/Out pipeline | Clip -> detector -> tracker -> bounces -> calls; verdict overlay on clip review; first end-to-end in/out on a real clip | B1, B2 | Scope |
| B4 | On-device + live | Core ML port of the detector; near-live capture-then-process on the phone; thermal-gated | B3, thermal test | Scope |
| B5 | Eval harness | Recorded-clip fixtures + tap-test ground truth; accuracy/precision/“too close” rates; the works-on-court gate | B1+ | Scope |
| C | Auto-calibration | Court-keypoint heatmap net (TennisCourtDetector-style) to seed/auto-place corners; manual stays the guaranteed fallback | 0-1, B5-style eval | Scope |
| D | Players + Kitchen faults | `PlayerDetector` (YOLO-nano COCO) + tracking; NVZ foot-fault logic at volley contact | B3, `CourtModel` | Scope |
| E | Rally + Scoring | Rally (in-play) segmentation; pickleball scoring state machine; score overlay | B3 (+ D for serve context) | Scope |
| F | Stats + Speed | Shot speed from trajectory+calibration+fps; placement heatmaps; rally/session stats | B3, E | Scope |
| G | Review experience | Clip review with synced overlays (track, calls, score), highlights, export/share | B3, E, F | Scope |
| H | Multi-phone + advanced | Second phone per baseline (device-agnostic `CourtModel` pays off), occlusion/3D | mature B-G | Scope |

## Critical path and why this order

1. **A unblocks everything**: nothing downstream can be built or validated without
   recorded clips bound to a `CourtModel`. It is also small and fixes the current
   "I calibrated but it does nothing" gap.
2. **B1 is the highest-value, lowest-risk work and needs no data or ML**: the
   in/out decision is pure geometry/physics on a trajectory. Build and test it
   against synthetic trajectories now; it is the refereeing brain.
3. **B2 is the only data-hungry piece**: it is deliberately isolated behind
   `BallDetector` and developed against the clips from A, off-device first, so the
   model/export choice never blocks the rest.
4. Everything after B (auto-cal, players, scoring, stats, review) is layered onto
   a validated in/out foundation, and is pulled by real usage rather than the
   roadmap. Their plans are intentionally scope-level until reached.

## Model and tooling leanings (verify before committing; see CONSIDERATIONS.md)

- Ball: lean **TrackNet-style heatmap** (3-frame motion finds the ball at the
  blurred bounce frame, where a box detector struggles and the call matters most).
- Players: **pretrained YOLO-nano, COCO person class**, no training.
- Tracking: **ByteTrack** default; **OC-SORT** once bounces break track identity.
- On-device export: lean **YOLO26-nano** (NMS-free Core ML export, small-object
  tuned) with **v8/v11 as the mature fallback**. Validate the pipeline off-device
  first so the export-maturity gamble never blocks development. YOLO26 specifics
  are unverified here: treat as "lean toward, verify before committing."

## Plan index

- Phase A - Session + Capture (detailed): `plans/2026-06-20-phase-A-session-capture.md`
- Phase B1 - In/Out core, deterministic (detailed): `plans/2026-06-20-phase-B1-inout-core.md`
- Phase B2 - Ball detector (scope): `plans/2026-06-20-phase-B2-ball-detector.md`
- Phase B3 - In/Out pipeline (scope): `plans/2026-06-20-phase-B3-inout-pipeline.md`
- Phase B4 - On-device + live (scope): `plans/2026-06-20-phase-B4-ondevice-live.md`
- Phase B5 - Eval harness (scope, build early): `plans/2026-06-20-phase-B5-eval-harness.md`
- Phase C - Auto-calibration (scope): `plans/2026-06-20-phase-C-auto-calibration.md`
- Phase D - Players + Kitchen faults (scope): `plans/2026-06-20-phase-D-players-kitchen.md`
- Phase E - Rally + Scoring (scope): `plans/2026-06-20-phase-E-rally-scoring.md`
- Phase F - Stats + Speed (scope): `plans/2026-06-20-phase-F-stats-speed.md`
- Phase G - Review experience (scope): `plans/2026-06-20-phase-G-review-experience.md`
- Phase H - Multi-phone + advanced (scope, optional): `plans/2026-06-20-phase-H-multiphone-advanced.md`

## Honesty and physics (non-negotiable, every phase)

- One monocular elevated camera cannot resolve sub-inch. Every line/zone call
  carries an uncertainty band; within it the verdict is `tooCloseToCall`, never a
  fabricated in/out.
- No accuracy/confidence number is shown that we cannot actually compute.
- Never hard-block on a CV step: every automatic step has a manual fallback and a
  dismissable path (the existing calibration invariant extends forward).
