# Phase B5: Eval harness

Scope-level plan. Expand to a detailed task plan when this phase is reached. Note: build this EARLY alongside Phase B2/B3, since it is the gate mechanism for the whole B line.

Last updated 2026-06-20. See `docs/superpowers/ROADMAP.md` for where this sits and `docs/CONSIDERATIONS.md` for the governing principles. Terminology here is normative and matches the roadmap's shared interface vocabulary.

## 1. Goal

Turn "works on a real court" from a feeling into a measured gate. Deliver recorded-clip fixtures plus tap-test ground truth, an eval runner that compares pipeline output to ground truth, and a report covering call accuracy, bounce precision/recall, the too-close-to-call rate, and error distance near the line. This is the project's real metric, per `docs/CONSIDERATIONS.md`.

## 2. Why it matters / where it sits

`docs/CONSIDERATIONS.md` is explicit: a CV/hardware feature is "done" only when it works on a real court; passing unit tests is necessary but not sufficient, and the recorded-clip fixtures plus the tap-test are the real metrics. This phase is what makes that definition operational. It sits at the end of the B line as the gate that decides whether the deterministic core (`Tracker` -> `BounceDetector` -> `LineJudge` -> `LineCall`, chained by `RefereeCore`) plus the `BallDetector` actually produce honest in/out verdicts on Avo's courts. Without it, "B is done" is a guess. Build it early (alongside B2/B3, not after) so the gate exists while the detector and pipeline are being developed, rather than being retrofitted once the work is nominally complete. The same structure becomes the template for the C and D gates.

## 3. Depends on / unblocks

- Depends on: Phase B1 (the `RefereeCore` facade and all the value types it produces: `BallObservation`, `BallTrack`, `Bounce`, `LineCall`, `JudgedBounce`), Phase A (recorded `SessionClip`s bound to a `CourtModel`, and the existing in-app tap-test that reads a court coordinate and in/out for a tapped point), and for the clip-fixture level Phase B2 (`BallDetector`) and B3 (the clip -> detector -> tracker -> bounces -> calls pipeline).
- Unblocks: declaring Phase B "done" against a real-court target. It is also the eval template that later auto-calibration (C) and player/kitchen (D) gates copy. It does not unblock those phases' implementation, only their acceptance.

## 4. Approach

Two fixture levels, built in order of cost.

1. Trajectory fixtures (no ML, fast, deterministic). Hand-authored or hand-labeled `[BallObservation]` sequences paired with expected verdicts, replayable in `swift test` directly against Phase B1's `RefereeCore` with zero ML and zero device dependency. These run in milliseconds, are fully deterministic, and catch core regressions (a change to `Tracker`, `BounceDetector`, or `LineJudge` that shifts a verdict). They are the first line of defense and live in the test bundle.

2. Clip fixtures (real footage, full pipeline). A small set of real recorded clips from Avo's courts with labeled bounce ground truth (court position plus in/out), run through the full Phase B3 pipeline (`BallDetector` -> `Tracker` -> `BounceDetector` -> `LineJudge`). The tap-test already in the app is the ground-truth source: tap where the ball actually bounced, read the court coordinate and the in/out result through `CourtModel`, and store that as the label. This exercises the parts the trajectory fixtures cannot (real detection, real motion blur at the bounce, real homography error) and is where the works-on-a-real-court gate is actually decided.

The eval runner diffs the pipeline's `[JudgedBounce]` against the stored ground truth, matches detected bounces to reference bounces by time and court proximity, and emits the metrics. Keep it a personal-tool harness: a handful of fixtures and a readable report, not a benchmark suite.

## 5. Key components & interfaces

Reusing Phase B1 types throughout; this phase adds a ground-truth type and a runner, and introduces no new pipeline stages.

- A `ReferenceBounce` ground-truth type: a court point (`courtPoint: CGPoint` in court feet, matching `BounceEvent`/`JudgedBounce`), the expected verdict (`LineVerdict` from B1: `.in` / `.out` / `.tooCloseToCall`), and a timestamp (`time: TimeInterval`). This is the labeled "what actually happened," sourced from the tap-test.
- An eval runner (name provisional, e.g. `EvalRunner`) that takes a sequence of `JudgedBounce` (pipeline output) plus a sequence of `ReferenceBounce` (ground truth) and emits a metrics summary (name provisional, e.g. `EvalReport`): call accuracy, bounce precision/recall, too-close-to-call rate, and error distance near the line. It matches each `JudgedBounce` to a `ReferenceBounce` by time window and court proximity, then scores the verdict.
- A fixture format: trajectory fixtures are `[BallObservation]` plus `[ReferenceBounce]`, stored as JSON in the test bundle and replayed against `RefereeCore.evaluate`. Clip fixtures are a `SessionClip` (the recording, already JSON-sidecar per Phase A) plus a sidecar label JSON holding the `[ReferenceBounce]` for that clip. Keep the JSON simple and aligned with the existing `SessionClip` sidecar convention.
- Boundary held: ground truth is captured through the tap-test, which reads court coordinates via `CourtModel`. The harness consumes `CourtModel` output (court points, verdicts) and never reaches into the calibration/persistence layer. It does not introduce or modify `CourtModel`, `BallDetector`, `Tracker`, `BounceDetector`, `LineJudge`, or `LineCall`; it only measures their output.

## 6. Decisions & leanings

- Define "correct near the line" carefully. A call that lands inside the `LineJudge` uncertainty band should be scored as a correct `tooCloseToCall`, not as a miss. Penalizing the pipeline for honestly declining a sub-inch call would punish exactly the honesty the project mandates. Recommendation: the eval runner treats a `tooCloseToCall` verdict on a ground-truth-near-the-line bounce as correct.
- Recommendation: report separate accuracy for clear calls vs close calls. A single blended number hides the part that matters: clear calls should be near-perfect, and close calls should be correctly flagged as too-close rather than wrongly decided. Two buckets keep the gate honest and diagnostic.
- Recommendation: keep the fixture format simple JSON, aligned with the `SessionClip` sidecar pattern from Phase A, so labeling and inspection stay low-friction.
- Explicit uncertainty: the right target numbers (how high "high" is for clear calls, how to count a close call that the pipeline decides confidently and gets right anyway) are not settled here and should be fixed against the first batch of real clips, not guessed in advance. The match tolerance for pairing a `JudgedBounce` to a `ReferenceBounce` (time window, court-distance threshold) is also an unverified knob to tune on real data. The reliability of ground truth right at the line is itself uncertain (see risks).

## 7. Risks / pitfalls (flagged upfront)

- Ground-truth labeling effort and subjectivity right at the line. A human tapping where a ball bounced is itself imprecise to within roughly the same band the system is being judged against, and this is exactly where single-camera physics is weakest. The ground truth near the line may be no more authoritative than the pipeline, so near-line scoring should lean on the too-close-to-call convention rather than treating a hand-tapped point as exact.
- Fixture rot. As the pipeline evolves (new detector, tuned bands), fixtures and target thresholds can drift out of alignment; trajectory fixtures especially can encode assumptions that a later refactor invalidates. Keep them few and revisit them when the core changes.
- Small sample size. This is a personal project on a few known courts: a handful of clips will not be statistically robust, and a single mislabeled bounce can swing a metric. Report counts alongside rates and resist over-reading small differences.
- Tap-test as both feature and ground truth: if the tap-test reads court coordinates through the same `CourtModel` the pipeline uses, calibration error is shared between truth and prediction and partly cancels in the in/out comparison. That is acceptable for the in/out gate (both see the same court) but note it explicitly so the error-distance metric is not over-interpreted as absolute physical accuracy.

## 8. Success gate (works-on-a-real-court definition)

This phase IS the gate for Phase B, and the template for the C and D gates. Define a concrete target before running, for example: clear calls correct at a high rate, and close calls correctly flagged as `tooCloseToCall` rather than wrongly decided. Hitting that target on the real clip fixtures is what makes Phase B "done." The trajectory fixtures gate is subordinate: they must stay green in `swift test` (no core regression), but green trajectory fixtures alone do not satisfy the works-on-a-real-court definition. The exact target rates are deliberately left to be set against the first real clips (see decisions), so the gate is honest rather than a number invented up front.

## 9. Out of scope / deferred

- A large or general-purpose benchmark suite, many courts, or many players: deliberately avoided. This is a handful of fixtures for one user on known courts.
- Automated ground-truth labeling (any attempt to derive bounce truth without the human tap-test): out of scope; the tap-test is the ground-truth source by design.
- Eval of anything past in/out: kitchen faults, scoring, stats, and player tracking get their own gates later (D/E/F), reusing this harness's structure but not built here.
- A principled position-dependent uncertainty band via the homography Jacobian: that is a `LineJudge` refinement noted in Phase B1, not part of the harness; B5 measures whatever band the pipeline currently uses.
- On-device/live eval: B5 measures the capture-then-process pipeline on recorded clips. Live/thermal evaluation belongs with B4's thermal testing, not here.
