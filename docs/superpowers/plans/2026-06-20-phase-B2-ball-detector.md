# Phase B2: Ball detector

Scope-level plan. Expand to a detailed task plan when this phase is reached (real clips from Phase A in hand).

Last updated 2026-06-20. See `docs/superpowers/ROADMAP.md` for where this sits and `docs/CONSIDERATIONS.md` for the governing principles. Terminology here is normative and matches the roadmap's shared interface vocabulary.

## 1. Goal

A `BallDetector` implementation that locates the ball per frame with confidence, robust specifically at the bounce frame (worst motion blur, where the in/out call matters most).

## 2. Why it matters / where it sits

This is the one data-hungry, ML-heavy component in the whole system, and it is the accuracy bottleneck for in/out. Everything downstream is deterministic geometry/physics (`Tracker` -> `BounceDetector` -> `LineJudge` -> `LineCall`), so a missed ball on the bounce frame leaves the kinematics nothing to compute and no amount of downstream polish recovers it. The physics ceiling is real: one monocular elevated camera cannot resolve sub-inch, so detection quality at the bounce sets how often `RefereeCore` can produce a confident verdict versus `tooCloseToCall`. The architecture deliberately concentrates the hard ML/data problem here and behind a protocol, exactly as calibration sits behind `CourtModel`, so the rest of the stack is insulated from the model choice.

## 3. Depends on / unblocks

- Depends on: Phase A (recorded `SessionClip`s bound to a `CourtModel`, to develop and measure against real footage) and Phase B1 (the deterministic `Tracker`/`BounceDetector`/`LineJudge` consumer that turns a `[BallObservation]` sequence into a `LineCall`).
- Unblocks: Phase B3 (clip -> detector -> tracker -> bounces -> calls, first end-to-end in/out on a real clip), Phase B4 (Core ML on-device port), and Phase B5 (eval harness). It does not unblock player/scoring/stats work, which depend on B3.

## 4. Approach

Lean a TrackNet-style heatmap detector that ingests roughly 3 consecutive frames and uses motion to find a ball that is a blur in any single frame, which is precisely the bounce-frame failure mode a single-frame box detector struggles with. Develop and measure OFF-DEVICE first: process recorded clips on the Mac in Python so the model and Core ML export choice never blocks development (the export gamble is deferred to B4). Start with a baseline (a pretrained ball/tennis-ball detector or a quick heatmap net) to get candidate positions for free, measure it against the bounce-detection metric, then refine only if the gate is not met. Expect this to be the only component that may need Avo's own labeled frames: hundreds of auto-labeled-then-corrected frames from his courts, not hours of footage. Build a small auto-labeling pipeline that runs the baseline detector plus tracking to propagate candidate labels across frames, then hand-correct a few; this keeps human labeling to a minimum.

## 5. Key components & interfaces

- Implements the existing `BallDetector` protocol: `func detect(in frame) -> [BallObservation]`, returning zero or more candidates per frame with confidence. `BallObservation.imagePoint` is normalized [0,1] to the capture frame (resolution-independent, matching the calibration convention).
- Consumes a `SessionClip` (its decoded frames, `fps`, `frameSize`) and its bound `CourtModel`; emits the `[BallObservation]` sequence that B1's deterministic core (referred to in the task framing as `RefereeCore`) consumes to produce a `LineCall`.
- New types this phase introduces (names provisional, to be fixed at task-plan time):
  - An offline harness (e.g. `ClipDetectionHarness`) that runs a `BallDetector` over a clip's decoded frames and produces the `[BallObservation]` sequence, so the Mac-side Python detector and the Swift core are exercised on identical inputs.
  - An auto-labeling pipeline (Python, off-device) that propagates candidate labels via tracking for hand-correction; this is tooling, not shipped app code.
  - A concrete `BallDetector` conformer (e.g. `HeatmapBallDetector`) wrapping the chosen model. The model and version stay an implementation detail behind the protocol, swappable without touching tracking or physics.
- Does not introduce or modify `CourtModel`, `BallTrack`, `BounceEvent`, `LineJudge`, or `LineCall`. This phase feeds the deterministic core through `[BallObservation]`; it does not bypass `CourtModel`.

## 6. Decisions & leanings

- Recommendation: TrackNet-style heatmap detector for the bounce frame. This is the leaning, not a settled fact; confirm against real clips once they exist.
- A YOLO box detector is the alternative but struggles exactly at the blurred bounce, so it is not preferred for the ball. If a YOLO route is taken for any reason, lean YOLO26-nano for the eventual on-device Core ML export (NMS-free, small-object tuned) with v8/v11 as the mature fallback. YOLO26 specifics are unverified here: verify before committing.
- Auto-label-then-correct over hand-labeling from scratch, to keep label effort to hundreds of frames.
- Explicit uncertainty: the baseline detector's real-world bounce-frame hit rate is unknown until measured on Avo's clips; how much (if any) hand-labeled data is actually needed is unknown until the baseline is measured. Treat both as things to measure, not assume.

## 7. Risks / pitfalls (flagged upfront)

- Motion blur at the bounce: the single hardest and most important case; the whole gate hinges on it.
- False positives from other round or bright objects, paddle faces, court markings, or specular highlights; confidence and the tracker's continuity must suppress these rather than letting them poison bounce detection.
- Label effort creeping past "hundreds of frames" into a data-collection project; if that happens, stop and reconsider scope (personal-tool discipline).
- The detector is the accuracy bottleneck for everything downstream: over-investing in downstream phases before this gate is met builds on an unvalidated foundation.
- Off-device-to-on-device gap: a detector that passes off-device in Python may behave differently after Core ML export and quantization; that risk is deliberately deferred to B4, but flag it now so it is not a surprise.

## 8. Success gate (works-on-a-real-court definition)

On real clips from Avo's courts, the ball is detected on and near the bounce frames at a high enough rate that the deterministic core's calls match the tap-test ground truth. The metric is the downstream verdict match, not a raw detection percentage in isolation, per `docs/CONSIDERATIONS.md`: detection-at-bounce is necessary but the real measure is whether `RefereeCore` produces the right in/out (or honest `tooCloseToCall`) versus the tap-test on recorded-clip fixtures.

## 9. Out of scope / deferred

- Core ML port, on-device inference, and any near-live capture-then-process: deferred to B4.
- The formal eval harness with accuracy/precision/"too close" rates: that is Phase B5; B2 only needs enough measurement to clear its own gate.
- Player detection (`PlayerDetector`), tracking-quality work beyond what auto-labeling needs, scoring, and stats: out of scope.
- Hours-of-footage data collection or any general-purpose pickleball ball model: deliberately avoided; this is a personal tool on a few known courts.
