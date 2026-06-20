# Phase D: Players + Kitchen faults (scope-level plan)

Scope-level plan. Expand to a detailed task plan when this phase is reached. Per CONSIDERATIONS.md, this is later-phase work that adds proportionally less than in/out; let real usage pull it.

Phase reference: ROADMAP.md row **D - Players + Kitchen faults**. Depends on **B3** (in/out pipeline) and `CourtModel`.

## 1. Goal

Detect and track the players on court, and call kitchen (non-volley-zone, "NVZ") foot faults: a player who volleys (hits the ball before it bounces) while a foot is in the NVZ. Every such call is advisory and carries the same too-close-to-call honesty as line calls; on-the-line foot positions and ambiguous contact attribution are flagged, not guessed.

## 2. Why it matters / where it sits

Kitchen faults are the second-most-common spatial call in pickleball after in/out, so they are the natural extension once the in/out foundation (Phase B) is validated. They sit one layer above in/out on the architecture spine: they reuse the same `CourtModel` court-space machinery and the same `BounceEvent` trajectory output from Phase B, adding only a `PlayerDetector` and deterministic fault logic on top.

Honest framing up front: this is genuinely harder than in/out and worth proportionally less (CONSIDERATIONS.md). In/out is pure geometry on one bounce point. A kitchen fault requires three fragile things to line up at once: knowing the contact was a volley, knowing which player made contact, and knowing where that player's foot was at the contact instant. Each is a single-camera estimate with its own error band. The phase only earns its place if real usage on Avo's courts pulls it; the roadmap should not.

## 3. Depends on / unblocks

Depends on:
- **B3 (In/Out pipeline)**: provides the `BallTrack` and `BounceEvent` stream that the volley test and contact-instant estimate read from. Phase D adds no new ball machinery.
- **`CourtModel`**: provides the image <-> court homography and court geometry, including the NVZ polygon, for every court-space test.
- The pretrained YOLO-nano (COCO person class) export path validated for the ball detector in B2/B4 is reused here for players, so most of the on-device export risk is already retired before D begins.

Unblocks:
- **Phase E (Rally + Scoring)**: serve context and player-side information from `PlayerTrack` feed serve legality and scoring logic.
- **Phase F (Stats + Speed)**: player positions enable placement/coverage stats.

## 4. Approach

Players come essentially free from a pretrained YOLO-nano on the COCO person class; no training, no labeled pickleball data. This is the cheap half of the phase and is why it is deliberately separated from the data-hungry ball detector (CONSIDERATIONS.md: the hard data problem is concentrated onto the ball, not the players).

Track detected players across frames with ByteTrack (the simplest solid default, matching the tracking leaning in ROADMAP.md). Escalate to OC-SORT only if identity swaps between the four players become a real problem in clips, exactly as the ball tracker escalates only once bounces break track identity.

Map player feet to court space through the existing homography. A player's feet are on the ground plane, so a foot image point projects validly to a court point through `CourtModel` (unlike the ball, which is off the ground and cannot be projected without trajectory inference). The NVZ test is then a point-in-polygon check of the foot court point against `CourtModel`'s NVZ geometry, structurally identical to `isInBounds`.

Push the decision into deterministic code; the nets only locate players and the ball. The fault is deterministic given two inputs derived from existing components:
- (a) Was the contact a volley? Derivable from the Phase B `BallTrack` and bounce timing: a volley is a contact that happens before the ball's next `BounceEvent` on that side.
- (b) Was the contacting player's foot in the NVZ at the contact instant? A point-in-polygon test of the foot court point against `CourtModel.nvz`.

A `KitchenFaultJudge` combines these, mirroring how `LineJudge` combines a `BounceEvent` with `CourtModel`. If both hold confidently, it is a fault; if either input is ambiguous (uncertain contact instant, uncertain attribution, foot on the line within the uncertainty band), the verdict is advisory / needs-confirmation rather than a confident fault.

## 5. Key components & interfaces

Reuses (from ROADMAP.md shared interface vocabulary, exact names):
- `CourtModel` - image <-> court homography and court geometry, including the NVZ polygon. All court-space tests go through it; the detector only locates.
- `BallTrack`, `BounceEvent` - from Phase B, the trajectory and bounce stream the volley test and contact-instant estimate read.
- `LineCall` with its `.tooCloseToCall` verdict and uncertainty band - the honesty template the fault verdict follows.

Introduced/named by Phase D (the roadmap reserves `PlayerObservation`, `PlayerTrack` for this phase; new types named here):
- `PlayerDetector` (protocol): `func detect(in frame) -> [PlayerObservation]`. Sits behind a protocol exactly as `BallDetector` and `CourtModel` do, so the YOLO version is a swappable implementation detail. Default impl wraps pretrained YOLO-nano (COCO person class).
- `PlayerObservation { imageBox / footImagePoint: CGPoint /* normalized [0,1] to capture frame */, time: TimeInterval, confidence: Double }`. Image points stay normalized to the capture frame, matching the calibration convention, so they are resolution- and device-independent. The foot point is the bottom-center of the detection box (the ground-contact estimate).
- `PlayerTrack`: a tracker-produced, identity-stable trajectory of `PlayerObservation`s for one player across a clip (ByteTrack default).
- `BallContactEvent` (new): `{ time: TimeInterval, imagePoint: CGPoint, attributedTrackID, isVolley: Bool, confidence }`. The estimated instant and location where a player struck the ball, derived from the `BallTrack` (sharp trajectory direction change near a `PlayerTrack`), with `isVolley` set by comparing the contact time against the next `BounceEvent`.
- `KitchenFaultJudge` (new, deterministic): combines a `BallContactEvent` with the contacting `PlayerTrack`'s foot court point (via `CourtModel`) and `CourtModel`'s NVZ geometry to produce a verdict. Mirrors `LineJudge`.
- `KitchenFaultCall` (new): `{ verdict: .fault | .clean | .needsConfirmation, footDistanceToNVZLineFeet: Double, uncertaintyBandFeet: Double }`. The `.needsConfirmation` verdict is the kitchen-fault analogue of `.tooCloseToCall`; no fabricated precision.

`CourtModel.nvz` (NVZ polygon in court coordinates) is referenced above. If it is not already present on `CourtModel`, adding it is the one expected `CourtModel` extension this phase needs; it is static court geometry and belongs there, preserving the boundary (downstream code must not reach around `CourtModel` to compute NVZ position itself).

## 6. Decisions & leanings (recommend + flag uncertainty)

- **Players via pretrained YOLO-nano, COCO person class, no training.** High confidence; the convergent pattern and CONSIDERATIONS.md both support it.
- **ByteTrack default, OC-SORT only if identity swaps appear.** Moderate-high confidence; matches the ROADMAP.md tracking leaning. Four players on a small court is a friendlier tracking problem than one erratic ball, so ByteTrack should suffice longer here.
- **Contact instant and who-hit-it attribution: the hard part, flagged as uncertain.** Recommend deriving the contact instant from a sharp direction change in the `BallTrack` near a `PlayerTrack`, and attributing the contact to the nearest player track at that instant. This is an estimate, not a measurement: single-camera depth ambiguity and motion blur make both the instant and the attribution uncertain. Treat ambiguous cases as advisory / `.needsConfirmation` rather than a confident fault. State this uncertainty in the UI, not just in code.
- **Foot-on-the-line uses the same too-close-to-call honesty as line calls.** High confidence on the principle. The foot court point inherits the homography's near-line uncertainty band; within that band the verdict is `.needsConfirmation`, never a fabricated fault.
- **Foot point = bottom-center of the detection box.** Reasonable default but approximate: feet can be apart, weight can be on the back foot, and a foot can be off-frame. Flag as an approximation to revisit (a pose model could give per-foot points later) only if real clips show it mattering. Do not build the pose path speculatively.

## 7. Risks / pitfalls

- **Occlusion**: players block each other or the ball, especially at the net during a volley exchange, dropping detections exactly when the call is being made. Worst at the moment that matters most.
- **Contact-instant timing**: the volley/bounce distinction hinges on ordering the contact time against the next `BounceEvent`; small timing errors flip the verdict. Sub-frame estimation helps but does not remove the risk.
- **Who-hit-it attribution**: with four players close at the net, attributing the contact to the wrong track produces a confident-but-wrong fault. Prefer `.needsConfirmation` over a wrong confident call.
- **Foot-on-line ambiguity**: homography error near the NVZ line is the same physics ceiling as line calls; honor the uncertainty band.
- **All advisory under single-camera physics**: depth ambiguity means a foot's exact court position and the ball's exact contact point are estimates. No call here can exceed the monocular accuracy ceiling.
- **Proportionally less value than in/out (CONSIDERATIONS.md)**: genuinely harder for less payoff. Resist gold-plating; build the deterministic spine and the honesty, defer everything else.

## 8. Success gate

Correct kitchen-fault calls on a small set of labeled clips of real points from Avo's courts, with ambiguous cases honestly flagged (`.needsConfirmation`) rather than guessed. Consistent with the project's "done only when it works on a real court" definition: passing unit tests on `KitchenFaultJudge` against synthetic fixtures is necessary but not sufficient; the recorded-clip check is the real metric. A confident wrong fault counts against the gate more heavily than an honest flag.

## 9. Out of scope / deferred

- Pose estimation / per-foot keypoints (the bottom-center-of-box foot estimate stands until real clips show it is the limiting error).
- OC-SORT (deferred until ByteTrack identity swaps are observed in real clips).
- Other foot faults beyond the NVZ volley fault (service-motion faults, baseline foot faults) - these belong with serve/scoring context in Phase E.
- Serve legality and scoring use of `PlayerTrack` (Phase E).
- Player placement / coverage stats (Phase F).
- Multi-phone player resolution and 3D occlusion handling (Phase H; the device-agnostic `CourtModel` and normalized image points keep this open without rework).
- Live/real-time kitchen-fault calling (capture-then-process is the default; live is a later thermal-gated optimization, as for in/out).
