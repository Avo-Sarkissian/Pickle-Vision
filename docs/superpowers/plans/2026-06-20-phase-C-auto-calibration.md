# Phase C: Auto-calibration

Scope-level plan. Expand to a detailed task plan when this phase is reached.

Last updated 2026-06-20. See `docs/superpowers/ROADMAP.md` for where this sits and `docs/CONSIDERATIONS.md` for the governing principles. Terminology here is normative and matches the roadmap's shared interface vocabulary and the existing calibration code.

## 1. Goal

Auto-place the four court corners (and optionally a few more keypoints) on a single frozen frame so calibration becomes one tap to confirm instead of four manual drags. The detected corners seed the existing `CalibrationFlow.corners`; the user confirms or nudges them in the existing Fine-tune step. Manual drag stays the GUARANTEED fallback and is never hard-blocked on CV, exactly as today.

## 2. Why it matters / where it sits

Calibration is the one-time setup gate in front of every session. The wizard already has an AUTO-DETECT step (`AutoDetectStepView`, `CalibrationFlow.AutoDetectState`) whose engine is honestly stubbed: `runAutoDetectStub()` simulates a scan and always resolves to `.failed`, routing the user to the guaranteed manual path. Phase C fills that stub in with a real `CourtKeypointDetector` so the common case is confirm-not-drag.

This is a quality-of-life phase, not a foundation phase. It sits after the in/out work (B1-B5) because the refereeing brain is the high-value, lower-risk core and because Phase C wants a B5-style tap-test eval to judge "good enough." Per `docs/CONSIDERATIONS.md`, manual calibration already delivers the value; auto-calibration only saves effort, so it must never become a blocker. It also preserves the load-bearing boundary: this phase produces corner SEEDS only and changes nothing about how `CourtModel` is built.

## 3. Depends on / unblocks

- Depends on: Phase 0-1 (the manual wizard, `CalibrationFlow`, `CalibrationDraft`, `CourtModel`, the frozen-frame capture, and the existing `.idle -> .finding -> .found/.failed` routing that already accepts detected corners via `resolveAutoDetect`). Also depends on a B5-style tap-test eval to set and check the "good enough" gate on Avo's courts.
- Unblocks: nothing downstream depends on Phase C. It is pulled by real on-court usage (manual drag getting tedious), not by the roadmap. The refereeing pipeline (B-G) runs identically whether corners were placed by hand or by the detector, because both produce the same normalized `corners` consumed by `CalibrationDraft`.

## 4. Approach

Treat court-keypoint detection as a DISTINCT CV job from ball/player detection, per the "two distinct CV jobs" split in `docs/CONSIDERATIONS.md`. This is keypoint / heatmap regression to a small set of known fixed court points, NOT object detection and NOT a YOLO job (YOLO belongs to the ball and players in the B/D phases).

Adapt existing weights rather than train from scratch: there is no labeled pickleball corpus, and the design is meant to avoid needing one. Adapt a TennisCourtDetector-style heatmap net that regresses each court keypoint to a heatmap peak. Apple Vision rectangle/contour detection (`VNDetectRectanglesRequest` / contour detection) is a reasonable interim that needs zero weights and can ship first to prove the wiring end to end.

The job runs OFF-DEVICE-friendly and on a single frozen frame: there is no real-time requirement, so it can run on the captured still without thermal concern, and the heatmap net can be developed and measured on the Mac before any on-device export is considered. The detector returns candidate normalized corners (or `nil`); on a confident result the wizard moves to `.found` and the user lands on Fine-tune to confirm or nudge; on `nil` or low confidence it resolves to `.failed`, which already routes to the guaranteed manual path.

## 5. Key components & interfaces

- New protocol `CourtKeypointDetector`: given the frozen frame, returns candidate normalized [0,1] corner points (or `nil` when it cannot find the court). Normalized [0,1] to the capture frame, matching the calibration convention used everywhere. A richer return that also carries the optional extra keypoints and a per-point or overall confidence (provisionally `CourtKeypointResult`) is the likely concrete shape; names to be fixed at task-plan time.
- Concrete conformers, swappable behind the protocol exactly as detectors sit behind their protocols and calibration sits behind `CourtModel`:
  - `VisionRectangleCourtDetector` (interim, Apple Vision, no weights).
  - `HeatmapCourtKeypointDetector` (adapted TennisCourtDetector-style net), the recommended target.
- Wiring (no new routing needed; the seams already exist):
  - Replace the body of `CalibrationModel.runAutoDetectStub()` (or add a real sibling) so it calls the chosen `CourtKeypointDetector`, then calls the existing `CalibrationFlow.resolveAutoDetect(_:detectedCorners:)` with `.found` + the four corners on success or `.failed` + `nil` otherwise.
  - `resolveAutoDetect` already writes the corners into `CalibrationFlow.corners` (and already rejects any "found" that is not a valid 4-corner quad, falling back to `.failed` to keep the never-block invariant). No change to that contract.
  - Detected `corners` then flow through `CalibrationFlow.draft` (`CalibrationDraft`) to build the `CourtModel` via `draft.courtModel()`, EXACTLY as today. The `.found` rail's layout chips (`CourtLayout`) and the Fine-tune / Verify steps (including the tap-test in `VerifyStepView`) are unchanged.
- Boundary preserved: this phase introduces only the detector protocol and conformers plus the stub-replacement glue. It does not touch `CourtModel`, `CalibrationDraft`, `CourtLayout`, the homography, or the coordinate layer, all of which stay device-agnostic so a second phone can be added later without rework.

## 6. Decisions & leanings (recommend + flag uncertainty)

- Lean toward the adapted heatmap-net path as the real target, with Vision rectangle/contour detection as the interim that ships first. Rationale: pickleball line layouts differ from tennis (kitchen/non-volley-zone lines, no service-T in the same place, no doubles alleys), and Vision rectangle detection is fragile on a full court with many competing lines, glare, and partial framing. A keypoint heatmap regresses to the SPECIFIC points we want rather than guessing a single dominant quad.
- Explicit uncertainty: adapting tennis-court keypoint weights to pickleball geometry is UNVERIFIED. The keypoint set, line spacing, and aspect ratio differ, so the adapted net may need its keypoint head remapped or a small amount of fine-tuning on Avo's courts. Whether the interim Vision path is "good enough" on its own to defer the net is also unknown until measured. Treat both as things to test on Avo's actual courts, not assumptions.
- The detector never asserts a precision number to the user. Consistent with the honesty rule, the `.found` rail shows a "Court found" pill with no percentage; the user is the verifier.

## 7. Risks / pitfalls (flagged upfront)

- Pickleball vs tennis line layout: the central adaptation risk. Tennis weights know tennis keypoints; mapping them to pickleball corners is the unverified core of this phase.
- Lighting and perspective: glare, faded paint, shadows, and the elevated single-camera angle all degrade line detection; the Vision interim is especially sensitive here.
- Partial-court framing: if the frozen frame does not contain all four corners, the detector should return `nil` (or low confidence) rather than a confident wrong quad. False confidence is worse than an honest failure.
- False confidence in general: a confidently-wrong auto-placement that the user accepts without checking would corrupt every downstream call. The user MUST still verify, and a slightly-off seed must remain cheap to nudge in Fine-tune.
- Underperformance is not a blocker: the honest stub-to-manual routing already exists, so if the detector is poor the user simply lands on manual, exactly as today. Nothing downstream breaks.

## 8. Success gate (works-on-a-real-court definition)

On Avo's courts, auto-placed corners land close enough that confirming them (with at most a small nudge) passes the existing tap-test in the Verify step within the same tolerance a careful manual calibration achieves, and this happens often enough across his known courts to save real effort versus dragging four corners. Manual is always one tap away in every sub-state. A unit-testable necessary condition: a `.found` result always yields a valid 4-corner quad that `CalibrationDraft` accepts and `CourtModel` can build from; the real measure, per `docs/CONSIDERATIONS.md`, is whether it works on the real courts, judged by the tap-test, not by an offline keypoint metric in isolation.

## 9. Out of scope / deferred

- Training a pickleball court-keypoint model from a large labeled corpus: deliberately avoided; adapt existing weights, with at most a small amount of Avo-specific fine-tuning if the gate is not met.
- Real-time or per-frame keypoint detection: unnecessary. Calibration is one-time on a single frozen frame, so there is no live or thermal requirement here.
- Any change to `CourtModel`, the homography, `CalibrationDraft`, `CourtLayout`, or the Fine-tune / Verify / tap-test logic: this phase only produces corner seeds.
- Auto-detecting or auto-selecting the court layout (pickleball vs tennis box vs custom): the layout chips stay user-chosen; the detector only places corners.
- Multi-phone keypoint detection and on-device Core ML export of the keypoint net: off-device on a frozen frame is sufficient for this phase; an on-device port is a later optimization only if it is ever wanted.
