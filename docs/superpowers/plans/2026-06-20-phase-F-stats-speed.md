# Phase F: Stats + Speed

Scope-level plan. Expand to a detailed task plan when this phase is reached.
Later-phase work; let real usage pull it.

Read `docs/CONSIDERATIONS.md` and `docs/superpowers/ROADMAP.md` first; the
principles and the shared interface vocabulary there govern this phase. This plan
uses those type names exactly.

## 1. Goal

Derive shot speed, ball placement heatmaps, and rally/session stats from the data
the earlier phases already produce. Shot speed comes from court-space displacement
of the ball between frames near contact; placement heatmaps from bounce
court-points; rally length, shot counts, and other aggregates from the rally
segmentation. No new ML and no new detector: this phase is deterministic
arithmetic on existing outputs.

## 2. Why it matters / where it sits

This is a later, lower-leverage phase by design. Per `docs/CONSIDERATIONS.md`,
calibration and in/out deliver most of the value; players, kitchen, speed, and
scoring are harder and add proportionally less, so this should be pulled by real
on-court usage, not by the roadmap. It sits near the top of the stack: it consumes
the validated in/out pipeline (`JudgedBounce` from Phase B3) and the rally and
scoring layer (`RallyModel`, `Score` from Phase E), and it feeds the review
experience (Phase G), where these numbers are actually presented. It adds no new
intelligence to the spine; it is a deterministic aggregation layer that turns
existing geometry and timing into the handful of stats Avo actually wants.

## 3. Depends on / unblocks

Depends on:
- **Phase B3 (In/Out pipeline):** the `[JudgedBounce]` per clip (each carrying a
  `courtPoint` and a real presentation `time`), which are the bounce court-points
  for placement heatmaps and the contact-region anchors for speed.
- **Phase E (Rally + Scoring):** `RallyModel` (rally/in-play segmentation) and
  `Score`, which provide rally boundaries, shot counts, and the aggregation units
  (per rally, per session).
- The **`BallTrack`** (Phase B1) and the clip's real frame timing (presentation
  timestamps via the Phase B3 pipeline, with `SessionClip.fps` as metadata, not
  the timeline) needed to compute displacement-over-time for speed.
- **`CourtModel`** for the feet-per-image scale that converts image displacement
  to real court distance. F consumes a resolved `CourtModel`; it does not reach
  into the calibration layer.

Unblocks:
- **Phase G (Review experience):** the synced-overlay/highlights/export experience
  presents the `ShotStat` values, heatmaps, and session aggregates this phase
  computes. F produces the numbers; G presents them.

It does not unblock the in/out, players, or scoring work, which all sit below it.

## 4. Approach

All deterministic, all in `PickleVisionCore`, all unit-testable against fixtures.

1. **Shot speed.** Compute speed from court-space displacement of the ball between
   frames near contact divided by the real frame interval. The `CourtModel`
   homography gives the feet-per-image scale at a court location; the real frame
   timing gives the time between samples (use real presentation-time deltas, not an
   assumed constant `fps`). Anchor the contact window using the bounce/rally
   structure already available (a `JudgedBounce` and the `RallyModel`'s shot
   boundaries), and report speed over a short window around contact rather than a
   single frame pair, to damp single-frame jitter.
2. **Placement heatmaps.** Bin the `JudgedBounce` `courtPoint`s into a court-space
   grid to produce a placement heatmap. This is pure binning of points already
   computed by the in/out pipeline; it inherits the in/out pipeline's coordinate
   convention and adds no new geometry.
3. **Rally/session aggregates.** Derive rally length, shot counts, and other
   aggregates from `RallyModel` (and `Score` where relevant): counts, durations,
   simple distributions. Pure reduction over existing per-rally/per-clip data.
4. **Honest presentation.** Carry an explicit uncertainty/confidence caveat with
   every speed number (see Decisions). Extend the existing History/session screen
   to show these stats; do not build a separate dashboard.

## 5. Key components & interfaces

Reuses, unchanged (exact shared-vocabulary names): `CourtModel`, `BallTrack`,
`BounceEvent` / `JudgedBounce`, `RallyModel`, `Score`, `SessionClip`,
`RefereeCore` output. F consumes these; it does not bypass `CourtModel`.

The roadmap already names the new type for this phase: **`ShotStat`** (listed in
the shared interface vocabulary as Phase F's contribution). New types and surfaces:

- **`ShotStat`** (new, in `PickleVisionCore`): the per-shot stat record. Carries
  the computed shot speed plus its honesty fields, for example a speed range or an
  explicit confidence/uncertainty band rather than a single fabricated precise
  number, and the contact `time`/court location it was measured at. Exact fields
  fixed at task-plan time.
- **Pure aggregation functions** (new, in `PickleVisionCore`): deterministic
  functions consuming `[JudgedBounce]` and `RallyModel` (and `Score`) and producing
  `[ShotStat]`, a placement heatmap, and the rally/session aggregates. Names
  provisional (for example a `StatsAggregator` facade with `shotSpeeds(...)`,
  `placementHeatmap(...)`, `sessionStats(...)`), to be pinned when the phase is
  reached. These are arithmetic on existing outputs; they contain no ML.
- **A placement heatmap value type** (new): a court-space grid of binned bounce
  court-points (provisional `PlacementHeatmap`). Stays in court space; presentation
  draws it over the existing court overlay in Phase G.
- **A session-stats value type** (new, provisional `SessionStats`): rally length,
  shot counts, and the other aggregates Avo actually wants, computed per session.
- **A stats view** (new, app target): extend the existing History/session screen
  (the Phase A `HistoryView` clip/session list and the review surface) to show the
  `ShotStat`s, heatmap, and `SessionStats`. This is presentation only; the
  numbers come from the `PickleVisionCore` aggregation functions.

The aggregation functions and value types live in `PickleVisionCore` (deterministic,
device-agnostic, fixture-testable); only the view lives in the app target.

## 6. Decisions & leanings (recommend + flag uncertainty)

- **Speed as a range or with an explicit confidence caveat, not a single precise
  number (recommended).** Speed accuracy is bounded by single-camera depth
  ambiguity and by the bounce-frame detection rate. Per the honesty rule and the
  physics ceiling in `docs/CONSIDERATIONS.md`, report speed with explicit
  uncertainty rather than a fabricated precise value. No accuracy/confidence number
  is shown that cannot actually be computed.
- **Temporal resolution (fps) matters more than spatial here, but settle
  empirically.** Speed is a displacement-over-time measurement, so the frame
  interval and detection-at-bounce rate dominate the error budget more than pixel
  resolution. Consistent with the project leaning that fps generally matters more
  than spatial for a fast ball, but the spec wants this settled empirically, so
  treat it as a measurement, not an assumption.
- **Measure speed over a short window around contact, not a single frame pair
  (recommended, flag).** A single frame-pair displacement is noisy; a short window
  damps jitter. The exact window and which samples count as near-contact are
  uncertain until tried on labeled clips.
- **Court-space displacement only at/near the bounce is geometrically valid.** The
  homography maps the court plane; airborne ball positions carry the single-camera
  depth/parallax ambiguity already flagged in B1/B3. This is the core uncertainty
  in any monocular speed estimate and is exactly why speed is reported as advisory
  with a band, not a precise number. Flag: how tightly speed can be bounded at all
  on a single camera is uncertain until measured against reality.
- **Compute only the stats Avo actually wants.** Personal-tool scope discipline:
  this is the specific small set of stats he will use, not a general analytics
  dashboard for everyone.

## 7. Risks / pitfalls (flagged upfront)

- **Speed accuracy near the physical limit of a single camera.** Depth/parallax on
  one monocular elevated camera caps how precisely speed can be known. The biggest
  risk is over-claiming precision; keep every speed claim honest and advisory.
- **Small sample sizes.** This is a personal project on a few known courts; per
  rally and per session the sample of shots is small, so distributions and averages
  are noisy. Present aggregates without implying statistical strength they do not
  have.
- **Garbage-in from upstream.** A missed ball on the bounce frame (a B2/B3 quality
  issue) leaves speed with nothing to compute; degrade honestly (no fabricated
  speed) rather than guessing. Heatmaps and counts inherit any miss/false-positive
  rate from the in/out and rally layers.
- **Over-claiming precision in the UI.** A clean-looking single number invites
  false confidence. State uncertainty explicitly in the presentation, not just in
  the code.
- **Boundary creep.** Keep aggregation deterministic and in `PickleVisionCore`;
  preserve the `CourtModel` boundary. If a stat tempts the view to reach into
  geometry or the calibration layer, stop and reconsider.

## 8. Success gate (works-against-reality)

On labeled clips from Avo's courts, the computed speeds and stats are plausible
against reality and are presented with honest uncertainty: speed shown as a range
or with an explicit confidence caveat rather than a fabricated precise number,
heatmaps and aggregates consistent with what actually happened in the rallies.
Passing unit tests on fixtures is necessary but not sufficient; the gate is the
plausibility-against-reality check on real labeled clips, with no over-claimed
precision.

## 9. Out of scope / deferred

- **The review experience itself** (synced overlays, highlights, export/share):
  Phase G. F computes the numbers; G presents them.
- **Any new ML, detector, or training.** This phase is arithmetic on existing
  outputs; the detector is B2 and is not touched here.
- **Any change to `CourtModel`, the calibration layer, the deterministic in/out
  core (`Tracker`, `BounceDetector`, `LineJudge`, `RefereeCore`), or the
  `RallyModel`/`Score` layer.** F consumes these unchanged.
- **A general-purpose analytics dashboard or multi-user stats.** Personal-tool
  scope: only the stats Avo actually wants.
- **3D/multi-camera speed reconstruction** that would resolve the depth ambiguity:
  that depends on the second-phone work in Phase H, not F.
