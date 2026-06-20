# Phase G: Review experience (synced overlays, highlights, export) - Scope Plan

> Scope-level plan. Expand to a detailed task plan when this phase is reached.
> This is the product-polish layer; guard hard against gold-plating
> (`docs/CONSIDERATIONS.md`).

Read `docs/CONSIDERATIONS.md` and `docs/superpowers/ROADMAP.md` first; the
principles and the shared interface vocabulary there govern this phase. This plan
uses those type names exactly. The visual layer follows the Direction-B
"Instrument - Daylight" design language (`docs/design/handoff-instrument-daylight.md`):
dark full-bleed video screens, optic-yellow computed overlay, `PVColor` / `PVFont`
tokens, overlays that never cover the court playing area.

## 1. Goal

The SwingVision-grade review layer: play back a recorded `SessionClip` with synced
overlays (ball track, line calls, score), jump between rallies and contested
calls, and export or share one highlight clip with the overlay burned in. Deliver
a deliberately small first version: scrub + overlay toggle + jump-to-contested-call
+ export-one-highlight. Everything beyond that is deferred (Section 9).

## 2. Why it matters / where it sits

Phases A-F produce the data (clips, `[JudgedBounce]`, `RallyModel`, `Score`,
`ShotStat`) but present it only in the minimal confirmation views built along the
way (the Phase B3 `ClipReviewView` is overlay-on-playback to verify a call, not a
review UX). Phase G is the layer where Avo actually watches a session back and
gets value from the data already computed: this is the payoff view, not new
intelligence. It sits last in the B-G line by design (ROADMAP "critical path"):
it consumes a validated in/out pipeline (B3), rally segmentation and scoring (E),
and stats (F), and adds nothing those phases must wait on. Per `CONSIDERATIONS.md`,
later phases add proportionally less value and this one is the most prone to
over-building, so the scope bar here is "useful to one user reviewing his own
match," not "a media product."

## 3. Depends on / unblocks

Depends on:
- Phase B3: the clip-review overlay foundation (`ClipReviewView`, `ClipProcessor`)
  and the cached `[JudgedBounce]` per clip. G extends this view rather than
  starting over.
- Phase A: `SessionClip`, `ClipStore` (the recording plus its JSON sidecar), and
  `CalibrationStore` to resolve `SessionClip.courtID` to a `CourtModel` for the
  overlay's court geometry. The clip list (Phase A's `HistoryView`) is the entry
  point.
- Phase E: `RallyModel` (in-play rally segmentation) and `Score` (the scoring
  state machine output) - the source of rally boundaries and the score-at-time
  used by the timeline and the score overlay.
- Phase F: `ShotStat` (shot speed/placement) - optional readouts shown on the
  review overlay; G must degrade gracefully when these are absent.

Unblocks:
- Nothing downstream in the roadmap depends on G. It is a leaf. Phase H
  (multi-phone/advanced) is independent. This is intentional: G is where real
  on-court usage is meant to pull (or not pull) further polish, rather than the
  roadmap pushing it.

## 4. Approach

Build on the existing Phase B3 review view and the Phase E/F data; reuse the
Direction-B design system throughout. Capture-then-process still holds: by the
time a clip is reviewed it has already been processed, so G reads cached results
and never re-runs the pipeline during scrubbing.

1. Review screen. Extend the B3 `AVPlayer`-backed `ClipReviewView` into a full
   review screen: scrub bar with frame-accurate seeking, play/pause, and the
   existing overlays drawn synced to `AVPlayer` periodic time observation.
2. Overlay toggle. A single control to turn overlay layers on/off: ball track,
   line calls, score. Reuse the existing `CourtOverlay` for court geometry and the
   B3 verdict overlay for calls. Each layer is independently toggleable so Avo can
   watch clean video or annotated video.
3. Event timeline. A rally/calls timeline strip beneath the scrubber that marks
   rally boundaries (from `RallyModel`) and contested calls
   (`JudgedBounce` whose `LineVerdict` is `.tooCloseToCall`, plus near-band `.in`/
   `.out`). Tapping a marker seeks the player to that event. This is the
   "jump between rallies and contested calls" capability.
4. Highlight extraction. A small, deterministic selector that picks notable
   segments - contested calls and notable rallies (e.g. longest rally, score-point
   rallies) - from the already-computed `RallyModel` / `[JudgedBounce]` / `Score`.
   No ML; pure rules over existing data.
5. Export one highlight. Take one selected segment and produce a shareable clip
   with the overlay burned in, via `AVAssetExportSession` plus an
   `AVVideoComposition` that composites the overlay (Core Animation /
   `CALayer` or `AVVideoCompositing`) onto the clipped time range. Hand the result
   to the system share sheet.

## 5. Key components & interfaces

Reuses, unchanged (exact shared-vocabulary / earlier-phase names): `SessionClip`,
`ClipStore`, `CourtModel`, `CalibrationStore`, `JudgedBounce`, `LineCall`,
`LineVerdict`, `RallyModel`, `Score`, `ShotStat`, `CourtOverlay`, and the Phase B3
`ClipReviewView` / `ClipProcessor`. G consumes these; it introduces no new
pipeline stage and no new geometry/physics.

New, app-level (presentation/orchestration only, in the app target, not in
`PickleVisionCore` - it touches AVFoundation and SwiftUI):

- `ReviewView` - the SwiftUI review screen. `AVPlayer`-driven, with scrubber,
  play/pause, the overlay toggle, the event timeline, and an export affordance.
  Evolves the B3 `ClipReviewView`; do not fork a parallel screen.
- `ReviewViewModel` (or equivalent) - holds the `AVPlayer`, current time, the
  cached `[JudgedBounce]` / `RallyModel` / `Score` for the clip, and the overlay
  toggle state. Drives overlays from periodic time observation.
- `ReviewOverlayLayer` set - the toggleable layers (track / calls / score). Reuse
  `CourtOverlay` and the B3 verdict overlay; the score overlay reads `Score` at
  the current time.
- `HighlightExtractor` - deterministic selector:
  `func highlights(rallies: RallyModel, judged: [JudgedBounce], score: Score) -> [Highlight]`.
  Pure rules, no ML.
- `Highlight` - a value type: a time range (`start: TimeInterval`,
  `end: TimeInterval`), a `kind` (e.g. `.contestedCall` / `.notableRally`), and a
  short honest label. Drives both the timeline markers and what export offers.
- `HighlightExporter` - wraps `AVAssetExportSession` + `AVVideoComposition` to
  clip one `Highlight`'s range and burn in the overlay, returning a file URL for
  the share sheet.

Presentation conventions (reuse existing tokens, do not invent): IN uses
`PVColor.inBounds`, OUT uses `PVColor.outBounds`, `tooCloseToCall` uses
`PVColor.amber`; the optic-yellow track/court geometry uses `PVColor.optic`;
labels use `PVFont.mono`, titles `PVFont.display`. Overlays hug the corners and
never cover the court playing area (handoff orientation rule). Honesty rule
carries forward: show "too close to call" literally; never render a fabricated
confidence or precision number. `LineCall.distanceToLineFeet` /
`uncertaintyBandFeet` and `ShotStat` values may be shown only as the honest
computed values they are.

## 6. Decisions & leanings (recommend + flag uncertainty)

- Scope of v1: RECOMMEND the deliberately small first version - scrub + overlay
  toggle + jump-to-contested-call + export one highlight - and stop there. This is
  the section of the roadmap most prone to scope creep; treat every addition as
  guilty until proven pulled by real usage.
- Burned-in overlay vs separate track on export: RECOMMEND burned-in for v1.
  Shareability is the goal (one clip Avo can send to a partner), and a burned-in
  overlay is self-contained and plays anywhere. A separate overlay track / data
  sidecar is more flexible but only matters for re-editing, which is out of scope.
- Highlight selection rules: RECOMMEND start with two kinds only - every contested
  call (`tooCloseToCall` and near-band calls) and a couple of notable rallies
  (e.g. the longest). Deterministic, explainable, no ML. UNCERTAIN what "notable"
  should mean beyond rally length; defer richer heuristics until reviewing real
  sessions shows what Avo actually wants to jump to.
- Process timing: G reads the cached `[JudgedBounce]` / `RallyModel` / `Score`
  from earlier phases and does NOT re-run the pipeline during review. Export is the
  only place it does new heavy work (compositing). RECOMMEND export on demand for
  the one chosen highlight, not pre-rendering all highlights.
- Where the new code lives: app target, NOT `PickleVisionCore`. `HighlightExtractor`
  is the gray case - its rules are deterministic and unit-testable, so it COULD sit
  in core. RECOMMEND keeping it app-level for v1 unless it ends up needing fixture
  tests; flag this as a small, reversible call.
- Compositing approach: UNCERTAIN whether a Core Animation layer
  (`AVVideoCompositionCoreAnimationTool`) or a custom `AVVideoCompositing` is the
  right path for burning in the SwiftUI/`Canvas`-drawn overlay; the overlay is
  currently SwiftUI, and rendering it into a `CALayer`/pixel buffer for export is
  the real unknown here. Resolve with a spike on one short clip before committing,
  not by assumption.

## 7. Risks / pitfalls (flagged upfront)

- Gold-plating - the headline risk. This is the product-polish layer and the most
  tempting place to over-build (galleries, social, cloud, multi-session
  analytics). Mitigation: hold the line at the v1 scope above; let real on-court
  usage pull anything more (`CONSIDERATIONS.md`). Every feature past the four in
  the goal needs a usage reason, not a roadmap reason.
- Export performance and overlay compositing. Re-encoding video with a composited
  overlay on-device is the heaviest single operation in the project and can be slow
  or thermally throttle (`CONSIDERATIONS.md` hardware reality). Mitigation: export
  one short highlight on demand, show progress, keep the clip short; do not export
  whole sessions. Treat the compositing path as a spike (Section 6) before relying
  on it.
- Overlay-to-playback sync on scrub. Drawing a call or score at the wrong
  `AVPlayer` time makes correct data look wrong. Mitigation: drive all overlays
  from `AVPlayer` periodic time observation and the same normalized image
  coordinates the core consumed (same discipline as B3).
- Burned-in honesty. Once an overlay is burned into a shared clip it cannot be
  walked back. Mitigation: the export overlay obeys the same honesty rule as live
  overlays - show `tooCloseToCall` literally, never a fabricated number. A wrong or
  over-confident burned-in call is worse than a live one.
- Parallax (carried from B1/B3). Only the bounce point maps validly to court
  space; the airborne track is drawn in image space and must not be presented as a
  court-space call. The score overlay reflects `Score` from E, not a re-derivation.
- `CourtModel` boundary. The review/export code must consume `CourtModel` output
  (court points, verdicts, geometry) and resolve the court through
  `CalibrationStore` at the app level; it must not reach into the calibration layer
  (`CONSIDERATIONS.md` boundary rule).

## 8. Success gate (works-on-court)

Avo can open a real recorded session in the review screen, scrub it with the ball
track / line calls / score overlays toggling correctly and synced to playback,
jump to the contested calls via the timeline, and export and share one highlight
clip with the overlay burned in - and the burned-in calls and score match what the
review overlay showed. Passing unit tests (e.g. `HighlightExtractor` rules) is
necessary but not sufficient; the gate is reviewing and sharing a real session.

## 9. Out of scope / deferred

- Social features: in-app sharing networks, comments, accounts. Out of scope - this
  is an on-device, no-account personal tool (handoff).
- Cloud: upload, sync, backup, cloud rendering. Deferred.
- Multi-session galleries / libraries beyond the existing clip list, cross-session
  analytics, leaderboards, trends over time. Deferred; the entry point stays the
  Phase A `HistoryView` clip list.
- In-editor clip editing: trimming by hand, multiple-highlight reels, transitions,
  music, titles, custom export presets. Out of scope; export is one segment with a
  burned-in overlay.
- A separate (non-burned-in) overlay track or sidecar export for re-editing.
  Deferred (Section 6 decision favors burned-in for v1).
- Live/real-time review during capture. G is capture-then-process review of a
  finished recording.
- Any change to the deterministic core, the pipeline, scoring, or stats. G
  consumes B3/E/F output unchanged; if review exposes a bug, fix it in the owning
  phase's tests, not in the review layer.
- Multi-phone review (combining two camera angles). Phase H territory.
