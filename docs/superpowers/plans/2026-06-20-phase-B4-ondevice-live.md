# Phase B4: On-device + near-live

Scope-level plan. Expand to a detailed task plan when this phase is reached
(Phase B3 pipeline validated off-device).

## 1. Goal

Run the Phase B2 `BallDetector` on the iPhone via Core ML and process a
just-recorded `SessionClip` on-device, so the whole loop (record -> calls)
happens on the phone with no off-device step. The detector runs on the Neural
Engine; the deterministic core (`Tracker`, `BounceDetector`, `LineJudge`,
`RefereeCore`) runs unchanged in `PickleVisionCore`. True frame-by-frame
real-time is a later, thermally-gated stretch, not the bar for this phase.

## 2. Why it matters / where it sits

Phase B3 proves the full in/out pipeline end-to-end on a real clip, but the
detection step there runs off-device. B4 is the port that makes Pickle-Vision an
actual on-court tool: tap a saved court, record a rally, get calls back on the
phone seconds later. It is the first phase where capture-then-process closes the
loop entirely on the 16 Pro. It sits after the pipeline is validated (so the
export-maturity gamble never blocks development) and before the eval harness (B5)
hardens the works-on-court gate, players (D), scoring (E), and the rest.

## 3. Depends on / unblocks

Depends on:
- **B3 (In/Out pipeline)**: the `ClipProcessor` that wires
  clip -> detector -> `Tracker` -> `BounceDetector` -> `LineJudge` and the
  off-device reference verdicts B4 must match.
- **B2 (Ball detector)**: the trained detector to export, plus its
  detection-at-bounce metric as the accuracy reference.
- **Thermal test**: the on-device fps-vs-spatial-resolution and sustained-load
  experiment (the roadmap's "thermal test" dependency for this phase).
- Existing **`ThermalPolicy`** and the capture pause path from Phase 0-1.

Unblocks: real on-court use of the in/out feature, which is what should pull the
later phases. Also unblocks the eval harness (B5) running on-device fixtures, and
the live real-time stretch.

## 4. Approach

- **Export the B2 detector to Core ML.** Two routes mirror the B2 model choice:
  - Heatmap route (TrackNet-style, the leaning ball detector): convert with
    coremltools. The 3-frame motion input and heatmap output stay; only the
    runtime backend changes.
  - YOLO route (if B2 went that way): lean **YOLO26-nano**, whose NMS-free export
    yields a self-contained Core ML model and avoids the NMS-attachment export
    bugs that plague v8 conversion. **v8/v11 are the mature fallback** if YOLO26
    conversion tooling proves too rough.
- **Run on the Neural Engine.** Target `.cpuAndNeuralEngine` compute units;
  measure, do not assume, that the net actually lands on the ANE and not the GPU.
- **Capture-then-process on-device.** Process the recorded `SessionClip` a few
  seconds after recording stops. Capture-then-process is acceptable and often
  preferable here; the few-seconds delay costs nothing for personal use.
- **Quantize** to keep the model lean on the Neural Engine; measure accuracy
  loss against the B2 detection-at-bounce metric before accepting a quantized
  build.
- **Run the thermal experiment** (fps vs spatial resolution under sustained
  capture + inference) as a real on-device test, not a baked-in assumption.
- **Swap the detector behind the protocol**, leaving `ClipProcessor` and the
  deterministic core untouched.

## 5. Key components & interfaces

Reuse, do not redefine, the roadmap's shared interface vocabulary.

- **`BallDetector` (protocol, exists):** `func detect(in frame) -> [BallObservation]`.
  B4 adds one new conforming implementation, e.g. `CoreMLBallDetector`, that
  loads the Core ML model and returns the same `BallObservation` values (image
  points normalized [0,1] to the capture frame). No protocol change.
- **`ClipProcessor` (from B3, reused):** the on-device `CoreMLBallDetector` is
  injected in place of the off-device detector. The wiring
  clip -> `BallDetector` -> `Tracker` -> `BounceDetector` -> `LineJudge` -> `LineCall`
  is identical.
- **`Tracker`, `BounceDetector`, `LineJudge`, `RefereeCore` (PickleVisionCore,
  unchanged):** pure Swift, already device-agnostic, already on-device. B4 does
  not touch them.
- **`CourtModel` (unchanged):** the load-bearing boundary. Only the detector
  implementation changes; nothing reaches around `CourtModel`.
- **`SessionClip` (unchanged):** still the unit of work (clip + its `CourtModel`).
- **`ThermalPolicy` (from Phase 0-1, reused):** its existing capture pause path
  applies when sustained load approaches throttling.
- **New, B4-local:** `CoreMLBallDetector` (the conforming detector); a small
  model-loading/quantization-config helper; a thermal-experiment harness or notes
  capturing the fps/resolution/thermal results. The `.mlpackage` model artifact
  is produced by the export step, not by app code.

## 6. Decisions & leanings (recommend + flag uncertainty)

- **Capture-then-process on-device first (recommended).** Live frame-by-frame
  real-time is a later, thermally-gated stretch, not this phase's bar.
- **Nano variant only.** Larger variants thermal-throttle the 16 Pro and add
  little for a 10-15 px ball.
- **Quantize** the model to stay lean on the Neural Engine; gate acceptance on
  measured accuracy against the B2 metric.
- **fps vs spatial resolution is an experiment to run**, not an assumption.
  Temporal resolution generally matters more than spatial for a tiny fast ball,
  but the spec wants this settled empirically against thermals on-device.
- **YOLO26 maturity is uncertain (flag).** YOLO26 is new, so its Core ML
  conversion tooling is less battle-tested than v8/v11. The NMS-free export is a
  real architectural win for this use case, but verify the conversion path works
  before committing; keep v8/v11 as the fallback. If B2 chose the heatmap route,
  this uncertainty is moot and coremltools is the path.
- **Uncertain until measured:** whether the net lands on the ANE, the achievable
  sustained fps, and the quantization accuracy hit. All three are measurements,
  not predictions.

## 7. Risks / pitfalls

- **Core ML conversion pitfalls:** NMS attachment (the v8 class of bugs the
  YOLO26 NMS-free export is meant to delete), unsupported ops, and quantization
  accuracy loss. The heatmap route avoids NMS entirely but can still hit
  unsupported-op snags in coremltools.
- **Thermals are the real ceiling, not raw compute.** Sustained capture plus
  inference throttles the 16 Pro within minutes. This caps live real-time and
  even stresses repeated capture-then-process.
- **Neural Engine throughput vs required fps:** the ANE may not sustain the fps
  the kinematics want; this is why fps vs resolution is an experiment.
- **Detection-at-bounce regression from quantization:** a quantized model that
  loses the ball on the blurred bounce frame defeats the whole pipeline, since
  that frame is where the call matters most.
- **Silent backend fallback:** Core ML may quietly run on GPU/CPU instead of the
  ANE; verify placement.
- **YOLO26 fresh-release rough edges** in tooling (see decisions).

## 8. Success gate (works-on-court)

On-device, on a real court:

- A recorded `SessionClip` is processed within acceptable time and thermals.
- The on-device `LineCall` verdicts (in / out / tooCloseToCall) match the
  off-device Phase B3 pipeline on the same clip (same detector lineage), within
  the B2 detection-at-bounce tolerance.
- Sustained operation does not thermally shut down capture: the existing
  `ThermalPolicy` pause path engages gracefully rather than crashing or
  hard-stopping.
- No fabricated accuracy number is shown; the uncertainty band and
  tooCloseToCall behavior carry over unchanged from B1/B3.

Passing unit tests is necessary but not sufficient; this gate is met on a real
clip recorded and processed on the phone.

## 9. Out of scope / deferred

- **True frame-by-frame live real-time** (the thermally-gated stretch; revisit
  only if the thermal experiment shows headroom).
- **The formal eval harness and tap-test ground truth** (Phase B5).
- **Auto-calibration** (Phase C) and **`PlayerDetector` / kitchen faults**
  (Phase D) and everything after.
- **Any change to `CourtModel`, the calibration layer, `Tracker`,
  `BounceDetector`, `LineJudge`, `RefereeCore`, or the `ClipProcessor` wiring.**
  B4 changes only the detector implementation behind the `BallDetector` protocol.
- **Second-phone / multi-camera** (Phase H).
- **Training or retraining the detector** (that is B2; B4 only exports and
  quantizes what B2 produced).
