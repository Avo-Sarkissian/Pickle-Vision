# Pickle-Vision - Considerations for Claude Code

These are considerations to weigh, not rules to follow. They capture project context and judgment that's easy to lose across sessions. When they conflict with a specific instruction in a task, the task wins, but flag the tension rather than silently resolving it.

## What this project is

- Personal-use tool for one person (Avo) on a small set of known courts. Not a published app for arbitrary users. When robustness-for-everyone trades against simplicity-that-works-for-these-courts, prefer the latter. Don't gold-plate for edge cases real usage won't hit.
- The accuracy ceiling is set by physics: one monocular, elevated camera. Calls near the line are advisory, not Hawk-Eye. Be skeptical of any feature or claim that implicitly assumes better-than-physical accuracy, and surface that rather than building around it.
- Scope discipline matters more than feature count. Phases 0-2 (calibration + in/out) deliver most of the value. Later phases (players, kitchen, speed, scoring) are harder and add proportionally less. Let real on-court usage pull the next phase, not the roadmap.

## Architecture already in place

- `CourtModel` is the load-bearing interface. Everything downstream (ball, players, kitchen, stats) depends only on it. Preserving that boundary matters more than local cleverness. If a change makes downstream code reach around `CourtModel` into the calibration layer, stop and reconsider, even when it's expedient.
- The phase ordering (foundation before refereeing output) is deliberate. Resist pulling later-phase work forward; it tends to get built on an unvalidated foundation.

## Computer vision (general)

- Detection quality is the foundation the entire physics layer stands on. A missed ball on the bounce frame leaves the kinematics nothing to compute. Effort spent making detection robust at the bounce (worst motion blur) pays off more than downstream polish.
- Prefer deterministic geometry/physics over learned models wherever they suffice: homography, point-in-polygon, kinematic bounce detection (y-velocity sign flip), Kalman smoothing. These are debuggable with a calculator and need no training data. Ideally the neural net does one job: locate the ball. Push intelligence into deterministic code.
- Prefer adapting existing weights (e.g. TennisCourtDetector-style keypoint nets, pretrained ball detectors) over collecting and training on hours of footage. There is no labeled pickleball corpus, and the design is meant to avoid needing one.

## Two distinct CV jobs - don't conflate them

There are two separate detection problems here, with different architectures, export paths, and failure modes. Keeping them mentally separate avoids a common mistake:

- **Court keypoint detection (Phase 0-1, calibration):** finding ~4-15 fixed court points. This is keypoint/heatmap regression to known points, not object detection. A TennisCourtDetector-style heatmap net (or a pose model), with Vision rectangle/contour detection as an interim, fits this. This is NOT a YOLO-detection job.
- **Ball + player detection (Phase 2-3, refereeing):** finding a tiny moving object frame to frame. This is what YOLO-style detection is built for. YOLO belongs here, in Phase 2, not in calibration.

## Detection model considerations (Phase 2-3)

- Treat the ball detector as one swappable component behind an interface (think `BallDetector` returning candidate positions + confidence per frame), exactly as calibration sits behind `CourtModel`. Then the specific model/version is an implementation detail that can change without touching tracking or physics. Avoid hardcoding a model version into the pipeline's bones.
- The ball detector is likely the only component that may need any of Avo's own labeled frames, and even then it's hundreds of auto-labeled-then-corrected frames, not hours. Players come essentially free from pretrained COCO person weights. Trackers and physics need zero data. Court keypoints can adapt existing tennis-court weights. The architecture deliberately concentrates the hard data problem onto this one model.
- For the ball specifically, a TrackNet-style heatmap approach is purpose-built for tiny fast balls: it ingests ~3 consecutive frames and uses motion to find a ball that is a blur in any single frame. A box detector (YOLO) tends to struggle exactly at the bounce frame, where motion blur is worst and where the in/out call needs it most. Weigh a heatmap ball detector against a single YOLO model that also handles players; the convergent pattern in racket-sports projects is players-via-YOLO, ball-via-TrackNet.
- For players, pretrained YOLO-nano (COCO person class) works out of the box with no training. Good default.
- Tracking is a pure algorithm, no training: ByteTrack is the simplest solid default; OC-SORT (motion-direction maintenance) handles the erratic, non-linear motion of a bouncing ball better when bounces start breaking track identity. This aligns with pushing intelligence into deterministic code.

## YOLO version landscape (as of early-mid 2026, verify before committing)

- YOLO26 (released January 2026) is the edge-first generation and, for an on-device Core ML target, is a meaningfully better fit than v8/v11 for three concrete reasons, not marketing: (1) NMS-free export means the Core ML model is self-contained, deleting the entire class of NMS-attachment export bugs that plague v8 Core ML conversion; (2) DFL removal prunes operators that were brittle across compilers, easing quantization (which is what keeps the model lean on the Neural Engine); (3) it was explicitly tuned for small-object accuracy (ProgLoss + STAL), which is the core problem here.
- The counterweight: YOLO26 is new, so v8/v11 have far more battle-tested Core ML conversion scripts, Stack Overflow answers, and known fixes. The tradeoff is better architecture for this exact use case (YOLO26) vs more mature tooling when something breaks (v8/v11). For a solo personal project controlling the whole stack, the NMS-free export alone makes YOLO26 worth leaning toward, while expecting fresh-release rough edges. This is a thing to weigh per-situation, not a settled rule.
- Use the nano variant for on-device. Larger variants will thermal-throttle the 16 Pro and add little for a 10-15px ball.

## Hardware reality

- Thermals are the real ceiling on iPhone, not raw compute. Sustained high-fps capture plus continuous inference throttles the 16 Pro within minutes. Capture-then-process is an acceptable, often preferable, alternative to true real-time here; a few seconds of delay costs nothing for personal use.
- Temporal resolution (fps) generally matters more than spatial (4K) for a tiny fast ball. Trading spatial resolution for frame rate usually serves this project, but the spec wants this settled empirically against thermals on-device, so treat it as a test to run, not an assumption to bake in.

## Working style and verification

- Avo operates as architect/PM and relies on implementation being readable, well-commented, with pitfalls flagged upfront rather than discovered later. Surfacing a known sharp edge early beats a clean-looking solution that hides it.
- A CV/hardware feature is only "done" when it works on a real court (the spec's own definition). Passing unit tests is necessary but not sufficient. The recorded-clip fixtures and the tap-test are the real metrics; lean on them.
- State uncertainty explicitly. When something is a guess or an approximation, say so. False confidence is worse than a flagged unknown.

## Conventions

- No em-dashes in prose or comments. Use hyphens only where genuinely needed (hyphenated words, numbers).
- Keep `CourtModel` and the coordinate layer device-agnostic so a second phone (one per baseline) can be added later without rework.
