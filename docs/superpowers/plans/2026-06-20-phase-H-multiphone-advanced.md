# Phase H: Multi-phone + advanced

> Scope-level plan and optional/future. Pursue only if single-camera physics
> proves to be the limiting factor in practice. Let real usage decide.

Read `docs/CONSIDERATIONS.md` and `docs/superpowers/ROADMAP.md` first. This plan
uses their normative vocabulary (`CourtModel`, `BallObservation`, `BallTrack`,
`BounceEvent`, `LineJudge`, `LineCall`, `SessionClip`) and stays inside the
project's personal-tool scope discipline.

## 1. Goal

Add a second phone (one per baseline) to break the single-camera accuracy
ceiling. A single monocular elevated camera cannot resolve sub-inch and so every
`LineCall` near a line carries an `uncertaintyBandFeet` within which the verdict
is `.tooCloseToCall`. Two ground-plane views plus epipolar geometry give a real
3D position for the ball at the bounce, which shrinks that too-close-to-call band
and improves genuinely contested near-the-line calls. True bounce height and
player occlusion also improve with the second angle.

## 2. Why it matters / where it sits

Phase H is the last row of the roadmap and is explicitly the payoff for an
architecture invariant that has been protected since Phase 0-1: `CourtModel` and
the coordinate layer are device-agnostic. Because nothing downstream of
`CourtModel` reaches into the calibration layer, a second device can be bolted on
without reworking tracking, physics, scoring, stats, or review.

It matters only where single-camera physics is the actual limiter: the
contested-call band and true 3D bounce height. Everywhere else, a second phone
adds setup friction and complexity for proportionally narrow gains. This is the
one phase where the honesty-and-physics constraint (advisory calls, real
uncertainty band) can be measurably improved rather than just honestly reported.

## 3. Depends on / unblocks

- Depends on: mature Phases B-G. Specifically a validated single-camera in/out
  pipeline (B1-B5), a working `BallDetector`, and an eval harness (B5) with
  labeled clips and tap-test ground truth to measure against.
- Depends on: the device-agnostic `CourtModel` boundary remaining intact. If any
  earlier phase reached around `CourtModel` into calibration, that debt must be
  paid before H is feasible.
- Unblocks: nothing further on the roadmap. H is terminal and optional.

## 4. Approach

1. Each phone calibrates its own `CourtModel` independently, one per baseline.
   This is clean precisely because calibration already sits behind `CourtModel`
   and is device-agnostic. No new calibration concept is needed per device, just
   two instances tied to the same physical court.
2. Each phone records its own `SessionClip` and produces its own
   `BallObservation` stream through the existing `BallDetector` + `Tracker`.
3. The two clips are synced in time. Candidate methods (all unverified): a shared
   audible cue such as a clap, a visible flash, or alignment on capture
   timestamps. Sync precision directly bounds triangulation quality, so this is
   the make-or-break step.
4. A new `StereoBounceResolver` consumes the two `CourtModel`s and the two
   time-synced `BallObservation` streams, establishes epipolar geometry between
   the views, and triangulates the ball's 3D position at the bounce. It emits an
   improved `BounceEvent` (a real ground-plane `courtPoint` plus a true height),
   not a monocular approximation.
5. The rest of the pipeline is unchanged. `LineJudge` consumes the improved
   `BounceEvent` exactly as before and produces a `LineCall` with a tighter
   `uncertaintyBandFeet`. Scoring, stats (Phase F), and review (Phase G) consume
   the improved bounce position with no code changes.

The two-camera path is a better source of `BounceEvent`s feeding the same
deterministic spine, not a parallel pipeline. Single-camera stays the guaranteed
fallback (extending the never-hard-block invariant): if the second phone is
absent or sync fails, the system degrades to the validated monocular path.

## 5. Key components & interfaces

Existing (reused unchanged, by exact roadmap name):

- `CourtModel`: two instances, one per phone, each independently calibrated to
  the same court. The device-agnostic boundary is what makes two instances
  trivial.
- `BallDetector`, `Tracker`, `BallObservation`, `BallTrack`: run per phone,
  untouched.
- `BounceEvent`: the output type is unchanged in shape
  (`imagePoint, courtPoint, time, incomingVelocity`); H supplies a better
  `courtPoint` and can carry a true height.
- `LineJudge`, `LineCall`, `RallyModel`, `Score`, `ShotStat`: all consume the
  improved `BounceEvent` with no change.
- `SessionClip`: one per phone; both bound to the same court via `courtID`.

New types (named here, defined when reached):

- `StereoBounceResolver`: takes two `CourtModel`s and two time-synced
  `BallObservation`/`BallTrack` streams; produces a triangulated `BounceEvent`
  via epipolar geometry. Lives in `PickleVisionCore`, deterministic and
  fixture-testable like the rest of the spine.
- `ClipSync` (working name): aligns two `SessionClip`s onto a common timebase and
  reports its own confidence. Its accuracy is an input the resolver must respect.
- `StereoPair` (working name): the lightweight binding of two `SessionClip`s,
  their two `CourtModel`s, and the resulting `ClipSync` offset for one recorded
  match.

## 6. Decisions & leanings

- Recommend deferring H until Phases B-G are mature and the single-camera ceiling
  is actually felt in real on-court use. Build it only if contested calls prove
  unsatisfying in practice, per the let-real-usage-pull-the-next-phase principle.
- Lean toward triangulating only at and around the bounce rather than full-rally
  stereo tracking. The bounce frame is where the call matters and where the
  monocular band is widest, so concentrate the added complexity there.
- Keep `StereoBounceResolver` deterministic and in `PickleVisionCore`, consistent
  with pushing intelligence into deterministic code. No new neural net is needed;
  the existing per-phone `BallDetector` still does the one ML job.
- Uncertain (flagged): clip time-sync precision is unverified and may dominate
  triangulation error. Two-court calibration (two `CourtModel`s registered to one
  physical court with enough rigor for epipolar geometry) is unverified and may
  be the harder of the two problems. Do not assume either works; spike both
  before committing.

## 7. Risks / pitfalls

- Time-sync precision: triangulation is only as good as the temporal alignment of
  the two streams. A sync error of even one to two frames can erase the accuracy
  gain at the bounce. Highest risk; verify empirically first.
- Two-viewpoint calibration and maintenance: two `CourtModel`s must be accurate
  and stable for epipolar geometry to hold. Re-calibration drift on either phone
  degrades the whole stereo result.
- Setup friction: two phones, two mounts, two calibrations, and a sync step per
  session is heavy for a personal tool. The convenience cost is real and weighs
  against the gains.
- Complexity for narrow gains: only the contested-call band and true 3D bounce
  height genuinely improve. Most of the pipeline sees no benefit, so the
  complexity is concentrated against a proportionally small win.
- Honesty trap: the second view shrinks the band but does not eliminate it.
  Continue to report a real `uncertaintyBandFeet` and `.tooCloseToCall`; do not
  let a "stereo" label imply Hawk-Eye precision the geometry cannot deliver.

## 8. Success gate

Two-view fusion measurably tightens the `uncertaintyBandFeet` and improves
contested near-the-line calls versus the single-camera baseline, measured on the
Phase B5 labeled clips and tap-test ground truth. If the stereo path does not
beat monocular on those fixtures, H is not worth keeping. As with every CV
feature, it is "done" only when it works on a real court, not merely when
fixture tests pass.

## 9. Out of scope / deferred

- More than two phones, or non-baseline placements.
- Full-rally stereo tracking; H targets the bounce, not the whole trajectory.
- Live/real-time stereo. Capture-then-process stays the default; live is a later
  thermal-gated optimization if ever.
- Any change to `LineJudge`, scoring, stats, or review logic. They consume the
  improved `BounceEvent` unchanged by design.
- Multi-court or multi-user generalization. This stays a personal tool on a small
  set of known courts.
