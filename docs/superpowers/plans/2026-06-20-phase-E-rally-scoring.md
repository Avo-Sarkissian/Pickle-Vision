# Phase E: Rally + Scoring

Scope-level plan. Expand to a detailed task plan when this phase is reached. Later-phase work; let real usage pull it.

This plan covers Phase E from `docs/superpowers/ROADMAP.md`: "Rally (in-play) segmentation; pickleball scoring state machine; score overlay." Read `docs/CONSIDERATIONS.md` and the roadmap first; the vocabulary below (`RallyModel`, `Scorer`, `Score`, `BounceEvent`, `BallTrack`, `CourtModel`, `LineJudge`, `PlayerTrack`) is normative and reused from there.

## 1. Goal

Segment match play into rallies (ball in play vs dead ball) and maintain the pickleball score automatically, surfaced as a score overlay. A rally is a ball-in-play interval bounded by a serve and a dead-ball event, derived from the `BallTrack` and the Phase B1 `BounceEvent` stream. The score itself is produced by a deterministic pickleball rules state machine consuming rally outcomes.

## 2. Why it matters / where it sits

Scoring is one of the later, harder phases that `docs/CONSIDERATIONS.md` notes "add proportionally less" than calibration and in/out, and it is explicitly pulled by real usage rather than by the roadmap. It sits at the tail of the architecture spine:

```
... BounceEvent --> [LineJudge(CourtModel)] --> LineCall
                          |
                          v
       [RallyModel] --> [Scorer] --> Score / Stats / Review
```

It consumes a validated in/out foundation (Phase B3) and, for serve context, players from Phase D. It feeds the Review experience (Phase G) and reuses the same rally boundaries that Stats (Phase F) needs, so getting `RallyModel` right has leverage beyond the score itself.

## 3. Depends on / unblocks

- Depends on: **B3** (Clip -> detector -> tracker -> bounces -> calls end-to-end, so a real `BallTrack` and `BounceEvent` stream exist), and optionally **D** (`PlayerTrack` for serve-side and serving-player context). `CourtModel` underpins all of it (which side a bounce lands on, in/out).
- Unblocks: **F** (Stats + Speed reuses `RallyModel` boundaries for per-rally and per-session aggregation) and **G** (Review experience renders the `Score` overlay synced to rally boundaries).

## 4. Approach

Capture-then-process, consistent with the rest of the project. Two cleanly separated layers, both in `PickleVisionCore`:

1. **Rally segmentation (heuristic, deterministic).** Walk the `BallTrack` and `BounceEvent` stream to mark rally start and end. A rally starts at a serve and ends at a dead-ball event. Candidate dead-ball signals, all derivable from existing types: two consecutive bounces on the same side (via `BounceEvent.courtPoint` through `CourtModel`), the ball leaving play (track exits the court polygon or the track ends), or a `LineCall` of `.out` on a bounce. Output is a sequence of `RallyModel` values.
2. **Scoring (pure state machine).** A `Scorer` consumes ordered rally outcomes and emits `Score`. This is exactly the calculator-debuggable deterministic logic `docs/CONSIDERATIONS.md` says to keep out of the ML layer. No neural net touches it; it is fully unit-testable against synthetic rally sequences.

Seed ambiguous events with a quick manual confirmation rather than guessing: who served first, let calls, and any rally whose outcome the heuristic flags as low-confidence. This follows the project invariant that every automatic CV step has a manual fallback and a dismissable path. The score state machine stays fully automatic and testable; only its rally-outcome inputs may be human-confirmed.

Start with doubles scoring (the common case) and treat singles as a flagged variant.

## 5. Key components & interfaces

Reference roadmap vocabulary by exact name; new types named here.

- `RallyModel` (roadmap-named, defined here): `{ id, startTime: TimeInterval, endTime: TimeInterval, outcome: RallyOutcome, confidence: Double }`. Derived from `BallTrack` + `[BounceEvent]` (+ optionally `PlayerTrack`). The `confidence` field is what gates the manual-confirm prompt.
- `RallyOutcome` (new enum): the rally result in scoring terms, e.g. `pointToServingSide`, `pointToReceivingSide` (or, in rally-scoring variants, just `wonByNear`/`wonByFar`), `fault`, `let`, `needsConfirmation`. Kept abstract from team identity so the `Scorer` owns rules, not the segmenter.
- `RallySegmenter` (new): pure function/type mapping `BallTrack` + `[BounceEvent]` + `CourtModel` -> `[RallyModel]`. The only place the bounce-and-trajectory heuristics live. No scoring rules here.
- `Scorer` (roadmap-named, defined here): pure state machine. `func apply(_ outcome: RallyOutcome) -> Score`, plus seed/reset for the initial server. Encodes serve, side-out, points, and server-number rotation. No I/O, no ML, no `CourtModel` dependency.
- `Score` (roadmap-named, defined here): `{ nearSide: Int, farSide: Int, servingSide, serverNumber: Int (1 or 2, doubles), isSideOut: Bool }`. The score overlay renders this; the exact display shape (e.g. "side-server-score" call format) is a UI concern in the app target, not in `PickleVisionCore`.
- `ScoringRules` (new, likely an enum or protocol): `doubles` vs `singles` and `sideOut` vs `rally` scoring, so the `Scorer` is parameterized rather than hardcoded to one ruleset.

All of `RallyModel`, `RallyOutcome`, `RallySegmenter`, `Scorer`, `Score`, `ScoringRules` live in `PickleVisionCore` behind clean types, device-agnostic and unit-testable. The score overlay (a SwiftUI view binding to `Score`) lives in the app target, mirroring how earlier overlays consume Core types without leaking UI into Core. The `CourtModel` boundary is preserved: segmentation asks `CourtModel` which side a bounce lands on and whether the ball is in play; it never reaches around it into the calibration layer.

## 6. Decisions & leanings (recommend + flag uncertainty)

- **Recommend: human-in-the-loop confirm for serve and side-out at first; fully automatic, fully testable score state machine.** Serve detection and fault attribution are the weak points (see Risks). The `Scorer` itself is settled deterministic logic; only its inputs are uncertain, so the seam between confirmable-input and automatic-rules is where to draw the line.
- **Recommend: start with doubles, sideout scoring.** It is the common case. Flag singles and rally scoring as variants behind `ScoringRules`; do not build them until usage asks.
- **Lean: derive dead-ball from `BounceEvent` first, trajectory-exit second.** Two-bounces-same-side is the cleanest signal and is already computable from Phase B1 output. Treat trajectory-exit (ball leaving the court polygon) as a secondary signal, since detector dropout can mimic it.
- **Uncertain: how reliably rally boundaries fall out of B1/B3 quality on real clips.** This is unknown until measured; the value of the whole phase rides on it. State it plainly rather than assuming.
- **Uncertain: whether `PlayerTrack` (Phase D) is needed for serve-side, or whether serve can be inferred from the first bounce pattern + a one-time manual "who serves first."** Lean toward the manual seed first; pull in `PlayerTrack` only if the manual confirm proves too frequent in practice.

## 7. Risks / pitfalls

- **Serve / fault / let detection reliability.** These are the weak points. A misclassified serve or fault corrupts all downstream score state. Mitigation: confidence-gated manual confirm; never silently guess an ambiguous event.
- **Scoring rule edge cases.** Server-number rotation, second-server logic, side-out on the first service turn of the game, win-by-2 / freeze-at-10, hand-out vs side-out wording. These are deterministic but fiddly; cover them with synthetic rally-sequence unit tests including known tournament edge cases.
- **Cascading dependence on B1/B3 (and D) quality.** Bad bounces or a dropped track produce bad rally boundaries, which produce a wrong score. Per `docs/CONSIDERATIONS.md`, detection quality at the bounce is the foundation; this phase inherits its limits and cannot exceed them.
- **Needs some manual correction.** This is not a fully hands-off scorer at first, and the plan should not pretend otherwise. The honest framing matches the project's advisory stance: assist the scorekeeper, do not replace them.
- **Proportionally less value than in/out.** Worth saying out loud so this phase is not over-invested relative to the refereeing core.

## 8. Success gate

Per the project definition ("done only when it works on a real court"): on a real game clip, the `Score` tracks correctly through the game with only minimal manual correction (a small number of confirm taps for serve/side-out/ambiguous rallies, no manual rewriting of the running score). Necessary but not sufficient on its own: the `Scorer` passes unit tests over synthetic rally sequences covering doubles sideout scoring and its known edge cases (rotation, side-out, win-by-2).

## 9. Out of scope / deferred

- Singles scoring and rally (point-per-rally) scoring: flagged variants behind `ScoringRules`, deferred until usage asks.
- Fully automatic serve / let detection with no manual confirm: deferred; the first cut keeps a human-in-the-loop seed for ambiguous events.
- Shot-level segmentation and shot speed/placement stats: Phase F. This phase emits `RallyModel` boundaries that F consumes, but does not compute stats.
- The synced review overlay, highlights, and export: Phase G. This phase emits `Score`; G renders and syncs it.
- Live/real-time scoring on-device: deferred to the capture-then-process default; live is a later thermal-gated optimization, consistent with the rest of the roadmap.
- Multi-phone score fusion: Phase H.
