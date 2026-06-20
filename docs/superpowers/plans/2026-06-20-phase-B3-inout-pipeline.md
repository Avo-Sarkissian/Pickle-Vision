# Phase B3: In/Out Pipeline (clip -> calls -> overlay) - Scope Plan

> Scope-level plan. Expand to a detailed task plan when this phase is reached
> (Phase B1 core and Phase B2 detector available).

Read `docs/CONSIDERATIONS.md` and `docs/superpowers/ROADMAP.md` first; the
principles and the shared interface vocabulary there govern this phase. This plan
uses those type names exactly.

## 1. Goal

Chain a recorded clip end to end and render the result: `SessionClip` -> decode
frames -> `BallDetector` -> `Tracker` -> `BounceDetector` -> `LineJudge`, then
draw the resulting `JudgedBounce`s as overlays on clip playback. This is the
first real in/out call on a real clip, the first time the deterministic
refereeing brain (Phase B1) runs on actual ball positions (Phase B2) on footage
shot on a calibrated court (Phase A).

## 2. Why it matters / where it sits

Phases A, B1, and B2 each deliver one isolated piece: clips bound to a court, the
deterministic core, and the ball detector. None of them produces a call on real
footage. B3 is the integration phase that connects them and is where the project
first does the thing it exists to do: watch a clip and say in / out /
too-close-to-call on a real bounce. It sits on the critical path between the
isolated components and everything layered above (D players/kitchen, E scoring, F
stats, G review), all of which assume a working in/out pipeline. It is
orchestration, not new intelligence: the geometry/physics already exists in
`PickleVisionCore`; B3 wires app-level decode + detection into it and presents
the output.

## 3. Depends on / unblocks

Depends on:
- Phase A: `SessionClip`, `ClipStore`, and clips actually recorded on a calibrated
  court (the input unit). `CalibrationStore` to resolve `SessionClip.courtID` to a
  `CourtModel`.
- Phase B1: `BallObservation`, `BallTrack`, `Tracker`, `Bounce`, `BounceDetector`,
  `LineCall`, `LineVerdict`, `LineJudge`, `JudgedBounce`, and the `RefereeCore`
  facade (`evaluate(_:court:) -> [JudgedBounce]`). B3 consumes these unchanged.
- Phase B2: a working `BallDetector` (protocol) implementation that turns a frame
  into `[BallObservation]`. B3 is its first real consumer in a full pipeline.

Unblocks:
- Phase B4 (on-device + live): B3 defines the off-device pipeline B4 ports and
  thermally gates.
- Phase B5 (eval harness): B3's `[JudgedBounce]` output is what B5 measures
  against tap-test ground truth.
- Phases D, E, F, G: all build on a validated in/out pipeline and its review view.

## 4. Approach

Capture-then-process, no real-time pressure (per CONSIDERATIONS.md: a few seconds
of delay costs nothing for personal use, and this is the default execution model
in the roadmap spine).

1. Resolve the court. From the `SessionClip`, load the `StoredCalibration` for
   `clip.courtID` via `CalibrationStore.load(id:)` and resolve to a `CourtModel`
   via `CalibrationStore.courtModel(from:)`. App-level code does this resolution
   so the pipeline receives a ready `CourtModel` and never reaches into the
   calibration layer (CONSIDERATIONS.md boundary rule).
2. Decode frames. Open the clip's video file (via `ClipStore.fileURL(for:)`) with
   `AVAssetReader` + `AVAssetReaderTrackOutput`, pulling frames as
   `CVPixelBuffer`s with their real presentation timestamps.
3. Detect per frame. Run the `BallDetector` on each decoded frame to produce
   `[BallObservation]`, stamping each observation with the frame's real
   presentation time (not an assumed constant fps) and converting detector image
   coordinates to the normalized [0,1] convention the core expects.
4. Judge. Feed the full `[BallObservation]` for the clip into Phase B1's
   `RefereeCore.evaluate(_:court:)` to get `[JudgedBounce]`. Cache the result keyed
   to the clip id so playback does not re-run the pipeline.
5. Render. Present an `AVPlayer`-based review view of the same clip with overlays:
   the ball track drawn over playback and, at each `JudgedBounce`'s timestamp, the
   IN / OUT / too-close verdict shown at the bounce's image point, synced to
   `AVPlayer` time.

## 5. Key components & interfaces

Reuses, unchanged (exact Phase B1 / shared-vocabulary names): `SessionClip`,
`ClipStore`, `CourtModel`, `CalibrationStore`, `BallDetector` (protocol),
`BallObservation`, `Tracker`, `BallTrack`, `BounceDetector`, `Bounce`,
`LineJudge`, `LineCall`, `LineVerdict`, `JudgedBounce`, `RefereeCore`.

New, app-level (orchestration only, lives in the app target, not in
`PickleVisionCore`):

- `ClipProcessor` - the orchestrator. Takes a `SessionClip` + `CourtModel` +
  `BallDetector` and returns `[JudgedBounce]`. Owns decode + per-frame detection +
  the call into `RefereeCore`. Sketch:
  `func process(clip: SessionClip, court: CourtModel, detector: BallDetector) async throws -> [JudgedBounce]`.
  It does NOT contain geometry or physics; it only feeds the core. Async because
  decode + inference over a clip takes real wall time.
- `ClipFrame` (or reuse a thin struct) - a decoded frame plus its real
  presentation `time: TimeInterval`, the unit fed to the detector so observation
  timestamps come from presentation times.
- `ClipReviewView` - SwiftUI `AVPlayer`-backed review screen that plays the clip
  and overlays the ball track and the per-bounce verdict at the right
  playback time. Reached from the clip list (Phase A's `HistoryView`).
- A results cache (e.g. on `ClipStore` as a JSON sidecar, or in-memory keyed by
  clip id) so a clip is processed up front once and scrubbing reuses the
  `[JudgedBounce]`.

Presentation conventions (reuse existing tokens, do not invent):
- IN verdict uses `PVColor.inBounds`; OUT uses `PVColor.outBounds`;
  `tooCloseToCall` uses `PVColor.amber` (the existing caution token). The court
  overlay itself reuses `CourtOverlay` and its zone fills.
- Honesty wording per CONSIDERATIONS.md and existing UI: the call is advisory.
  Show "too close to call" literally for the band verdict; never show a fabricated
  confidence/precision number (no per-call percentage). Optionally show
  `LineCall.distanceToLineFeet` and `LineCall.uncertaintyBandFeet` as honest,
  computed values.

## 6. Decisions & leanings (recommend + flag uncertainty)

- Process up front vs stream while scrubbing: RECOMMEND process-the-whole-clip up
  front and cache `[JudgedBounce]`. Clips are short, this is simpler, and it
  aligns with the capture-then-process model. Streaming-while-scrubbing is a later
  optimization only if up-front processing is too slow to tolerate.
- Frame timestamps: USE the asset's real presentation timestamps from
  `AVAssetReader`, not `SessionClip.fps` as an assumed constant. Variable frame
  delivery and dropped frames would otherwise corrupt bounce timing, which is the
  one thing that must be accurate for the call. `SessionClip.fps` is treated as
  metadata, not the timeline.
- Coordinate convention: the `BallDetector` returns image coordinates in whatever
  the detector's own frame is (pixels or its own normalized frame). `ClipProcessor`
  is responsible for converting to the [0,1]-normalized-to-capture-frame
  convention the core uses, using the clip's `frameSize`. UNCERTAIN until B2 is
  built: the exact detector output convention and any letterbox/orientation
  mismatch between the recorded asset and the calibration frame. Flag this as the
  most likely source of a silent wrong-coordinate bug; pin it down against a real
  clip in B5, not by assumption.
- Async/threading: decode + inference off the main thread; publish
  `[JudgedBounce]` back for the review view. UNCERTAIN: whether to process on open
  or pre-process the whole clip library; lean process-on-open for a personal tool.
- Where `ClipProcessor` lives: app target, NOT `PickleVisionCore`. It touches
  AVFoundation and the `BallDetector` impl and is pure orchestration. The
  deterministic core stays device-agnostic and fixture-testable (CONSIDERATIONS.md
  boundary rule).

## 7. Risks / pitfalls

- Frame timing / fps accuracy: an assumed constant fps misplaces bounces in time.
  Mitigation: real presentation timestamps end to end. This is the headline risk
  for call correctness.
- Overlay-to-playback sync: drawing the verdict at the wrong `AVPlayer` time, or
  in the wrong image location, makes a correct call look wrong. Mitigation: drive
  overlays from `AVPlayer` periodic time observation and the same normalized image
  coordinates the core consumed.
- Coordinate mapping: detector image coords -> the normalized convention the core
  expects. A letterbox, an orientation difference, or a pixel-vs-normalized mixup
  silently shifts every bounce off the line. Mitigation: convert explicitly in
  `ClipProcessor` using the clip `frameSize`; verify against a known bounce in B5.
- Decode + inference performance: running `BallDetector` per frame over a clip may
  be slow off-device and slower on-device. Mitigation: this is exactly why B4 is a
  separate, thermal-gated phase; B3 stays off-device-first and capture-then-process.
- Detector misses at the bounce frame: a missed ball on the worst-motion-blur
  frame leaves the kinematics nothing to compute (CONSIDERATIONS.md). This is a B2
  quality problem surfacing in B3; B3 should degrade honestly (no bounce, no
  fabricated call) rather than guess.
- Parallax (carried from B1): only the bounce point maps validly to court space;
  airborne positions do not. The track overlay is drawn in image space; only the
  `JudgedBounce` court-space verdict is shown as a call. Do not draw an airborne
  ball as if it were on the court.

## 8. Success gate (works-on-court)

On a real recorded clip from a calibrated court, the pipeline's IN / OUT /
too-close-to-call verdict at a known bounce matches the tap-test ground truth for
that bounce. Passing unit tests is necessary but not sufficient; the real metric
is the recorded-clip + tap-test comparison (this is the gate B5 formalizes). The
review overlay must show the verdict at the correct timestamp and image location
on playback.

## 9. Out of scope / deferred

- On-device execution and near-live capture-then-process: Phase B4.
- The formal eval harness, fixture set, and accuracy/precision/"too close" rate
  metrics: Phase B5 (B3 produces the `[JudgedBounce]` that B5 measures).
- Any change to the deterministic core's geometry or physics: B3 consumes B1
  unchanged. If a real clip exposes a core bug, fix it in B1's tests, not in the
  pipeline.
- Players, kitchen faults, rally segmentation, scoring, stats, highlights/export:
  Phases D-G.
- A polished media-manager review experience: Phase G. B3's review view is the
  minimal overlay-on-playback needed to confirm the call, not the final UX.
- Real-time per-frame call display during capture: deferred; B3 is
  capture-then-process.
