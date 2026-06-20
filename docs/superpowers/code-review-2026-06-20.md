# Mass-Scale Parallel Code Review — 2026-06-20

**Scope:** whole codebase (PickleVision app + PickleVisionCore), hunting for bugs / correctness / runtime issues.
**Method:** 8 parallel subagent reviewers fanned out across subsystems (geometry, state machines, persistence, camera, calibration UI, navigation, design/overlays, plus a whole-repo cross-cutting sweep). **Every** finding was then adversarially verified against the real code by a second agent (50 agents total, ~2M tokens, ~10 min). In parallel, the orchestrator did live verification in Xcode: `BuildProject`, `swift test`, `RenderPreview` of key screens, and `ExecuteSnippet` fuzzing of the geometry core.

## Baseline (verified live)

- **App builds:** SUCCEEDED, 0 errors. **1 warning** (see E1 — the "0 warnings" claim regressed).
- **PickleVisionCore tests:** 77/77 pass (`swift test`).
- **Core geometry fuzzed (ExecuteSnippet):** production overlay points map on-screen; round-trip exact; degenerate/collinear corners safely return `nil` (no crash); in/out-bounds correct; zero-size view → finite output (no NaN). Core math is robust.

## Results

| | Critical | Important | Minor |
|---|---|---|---|
| Confirmed (after dedupe) | 0 | 9 | 10 |
| Plus environment findings | — | 1 | 2 |
| Refuted (false positives ruled out) | 4 | 9 | 6 |

Raw: 42 findings → 23 confirmed / 19 refuted. Three reviewers independently found the same `CalibrationStore` filename-collision bug (I1) — strong signal it's real.

---

## Environment / tooling findings (orchestrator)

- **E1 — `DriftGuardOverlay.swift:191` build warning (Minor):** `PreviewInterfaceOrientation is ignored in a #Preview macro` — regressed the "0 warnings" status. Fix: use the macro's `traits:` argument, e.g. `#Preview(traits: .landscapeLeft)`.
- **E2 — App layer has ZERO automated tests (Important):** the Xcode scheme's test plan runs **4 tests, all auto-generated stubs** (`example()`, `testExample()`, `testLaunch()`, `testLaunchPerformance()`). The 77 real tests live only in `PickleVisionCore` and run via `swift test`, **not** in the scheme. So camera, navigation, the calibration UI, and the persistence stores have no automated coverage, and "run tests" in Xcode is misleadingly green.
- **E3 — SwiftUI `#Preview` fixtures use pixel-space corners while production stores normalized [0,1] (Minor):** `CourtOverlay`, `SavedCourtCard`, and `HomeView` previews feed pixel corners (e.g. `(360,200)`), so the overlay maps off-screen and the previews render **empty courts**. Production stores normalized corners and renders correctly (proven via ExecuteSnippet), but the previews can't be trusted for visual QA of the overlay — the app's core asset. Fix: normalize the preview fixtures (divide by image size).

---

## Confirmed — Important

**I1 — `CalibrationStore` venue-name → filename collision = silent data loss + wrong-court deletion.** `url(forVenue:)` maps every non-`[letter/number/space/-/_]` char to `_`, so distinct names collapse to one file (`Court #1`, `Court @1`, `Court_1` → `Court_1.json`; any all-punctuation name → `venue.json`). `save()` `.atomic`-writes to that name with no collision check → saving the second court silently destroys the first; `delete(venueName:)` can remove the wrong court. *(Found independently by 3 reviewers.)* Fix: give `StoredCalibration` a stable `id: UUID`, use it as the filename, keep `venueName` as display-only.

**I2 — Fit-quality metric is mathematically meaningless (honesty concern).** `FitQuality.computeResidual` builds the homography from the same 4 corners it then reprojects. A 4-point DLT is exactly determined, so the residual is always ~1e-16 for *any* non-degenerate quad. Result: Verify always shows **"FIT QUALITY: Good · 4/4"** (even for a wildly mis-placed quad), labeled "From corner-fit residual" — a positive indicator carrying zero information. The intermediate bar buckets are dead code. Fix: remove the bar in v1, or compute a metric that actually varies (quad convexity / interior-angle deviation, aspect-ratio vs. known court ratio, self-intersection / min-edge checks).

**I3 — Court overlay is OFF when a normal user first reaches Fine-tune/Verify.** `CalibrationFlow.overlayVisible` is set only in `init` and `forExpressReCal`; no runtime transition (`calibrateManually`, `advance`, `dropToManual`, …) turns it on. The standard flow starts at `.position` (`overlayVisible == false`) and walks to `.fineTune` without ever flipping it, but the wizard only draws the overlay when `overlayVisible` is true. So manual calibration arrives at Fine-tune with **no overlay** (the user must hunt for the toggle) while express re-cal shows it — inconsistent, and it undercuts the core "drag the overlay onto the lines" interaction. Fix: make `overlayVisible` computed from the step (default on for fineTune/verify), or set it true in every transition landing on those steps.

**I4 — Custom layout with `nil` dimensions silently becomes regulation 20×44×7.** `CourtProfile.make(layout: .custom, custom: nil)` substitutes regulation dimensions. `StoredCalibration.customDimensions` is optional and nothing enforces that `.custom` carries dimensions, so a `.custom` record saved/loaded without dimensions rebuilds as a 20×44 court that looks valid but is wrong. Fix: enforce the invariant — require dimensions when `layout == .custom` on save; treat a `.custom` record with `nil` dims as corrupt on load (dismissable error + re-calibrate).

**I5 — Thermal "shutdown" does NOT pause capture.** `ThermalPolicy` returns `frameRateCap: 0` for `.shutdown` ("0 = pause") and the UI shows "Phone too hot — capture paused." But `applyThermalCap` treats `0` as "no cap" (`if let cap, cap > 0 { … } else { target = chosenMaxRate }`), so at the hottest state it **re-applies full frame rate** while telling the user it paused. Fix: special-case `cap == 0` to stop the session (and restart on recovery).

**I6 — Capture session is never stopped.** `CameraService.stop()` has zero callers; there's no `scenePhase`/background handling and no `AVCaptureSession` interruption observers. Once the camera opens, the back camera + frame pipeline run indefinitely — through backgrounding and navigation back to Home — draining battery and generating the heat the thermal policy is meant to fight. Fix: observe `scenePhase`, `stop()` on `.background/.inactive`, restart on `.active`; add interruption observers.

**I7 — Corner drag teleports the nearest corner on the first move.** In `CalibrationView`, the `DragGesture(minimumDistance: 0)` is on the whole canvas and the first `.onChanged` both resolves the dragged corner from `startLocation` and writes `corners[i] = location`. A touch landing *near* (within 44pt) but not *on* a handle snaps that corner to the finger instead of nudging from its current position — bad for precise calibration. Fix: capture a grab offset on first change (`delta = handle - startLocation`), or attach the gesture per-handle.

**I8 — Renaming a court during re-calibrate orphans the old file → duplicate court.** Re-cal preloads the name into an editable field; `save()` writes to a filename derived from the *current* name. Edit the name and the old-named file remains → two courts where the user edited one. Fix: pass the original name in and delete/rename the old file on save (atomic rename), or lock the name on the re-cal path.

**I9 — `fhd240` ("1080p · 240 fps") profile is silently hard-capped to 120 fps.** `configureSession()` does `let rate = min(best.maxFrameRate, 120)`, so the selector picks a 240fps format but the device is configured at 120 — the Settings row advertises a rate the engine never applies. Fix: cap from the selected profile (`min(best.maxFrameRate, selector.maxFrameRate)`), or remove/relabel `fhd240` if 240 is intentionally unsupported in v1.

---

## Confirmed — Minor

- **M1 — `Homography.project` divides by `r.z` with no zero/finite guard** *(found by 2 reviewers)*. A tap on the vanishing line (reachable from the Verify tap-test, which lets you tap anywhere) yields `inf`/`nan` court coords → readout shows "x nan · y nan ft" and `isInBounds` silently reports OUT. Fix: guard `r.z` (return `CGPoint?`) and surface an "off court" state.
- **M2 — FitQuality `evaluate()` vs `barSegments()` thresholds disagree** (`.good` ≤ 1e-3 but 4 segments needs ≤ 1e-6) — a "Good" label can sit next to a 3/4 bar. Masked today by I2. Fix: single threshold ladder.
- **M3 — FIT QUALITY label color is hard-coded green** even when the result is "Fair" — a poor fit still reads reassuringly green. Fix: amber for `.fair`.
- **M4 — `CalibrationFlow` accepts corner arrays of any length** (init/`forExpressReCal`/`resolveAutoDetect(.found,…)`), so a corrupt/short record can show `.found` with no homography and feed the drag UI. Fix: validate count == 4 at the flow boundary (fall back to defaults).
- **M5 — `CalibrationStore.courtModel(from:)` doesn't validate `imageCorners.count == 4`** — a hand-edited/short file decodes fine then yields a silently `nil`, un-loadable court. Fix: validate at decode/save; offer re-calibrate on failure.
- **M6 — Custom dimensions accept any positive value (NVZ can exceed half the length)** *(found by 2 reviewers)*. e.g. length 40 / kitchen 30 → kitchen line at `y = -10`, drawn outside the court. Saves and round-trips. Fix: require `0 < nvz < length/2`, plus sane min/max caps.
- **M7 — Permission flow folds `.restricted` into `.denied` and never re-checks on return from Settings.** "Open Settings" is misleading for `.restricted` (MDM/parental), and after granting access + returning, the UI doesn't refresh. Fix: re-call `start()` on foreground; distinct `.restricted` message.
- **M8 — Full-res `CGImage` is created every 10th frame even when nobody reads `latestImage`.** On the live camera screen only calibration freeze consumes it, so this is continuous wasted `CIContext` work + large allocations (~12/sec at 120fps) feeding the thermal problem. Fix: gate snapshotting behind an active-freeze flag; downscale; clear when done.
- **M9 — Verify tap-test readout card + marker dot lack `allowsHitTesting(false)`**, so re-taps that land on the card/dot are swallowed (dead zones) right where the user naturally re-taps. Fix: add `.allowsHitTesting(false)`.
- **M10 — `SavedCourtCard` thumbnail rebuilds a `CalibrationStore` + solves the homography on every body render** (per card, per invalidation). Fix: make `courtModel(from:)` static and memoize the model once per calibration.

---

## Refuted (notable false positives ruled out by verification)

Adversarial verification killed 19 plausible-but-wrong findings, including: wrong-court deletion on name collision (the *overwrite* is real — I1 — but the *delete-wrong-court* variant needs an unreachable state); re-calibrate "loses saved corners" (express re-cal correctly lands on Fine-tune with corners); `SavedCourtCard` thumbnail aspect distortion (the `max(…,1)` floor makes `contentSize` (1,1) and it renders correctly); `OrientationSupport.mask` data race (main-thread only by platform guarantee); `CourtOverlay` NaN-flood (the in-bounds polygon == the defining correspondences, always finite); `start(profile:)` ignoring the profile (fresh `CameraService` per screen); DriftDetector flapping (binary by design). Full reasoning per item in the workflow output.

---

## Resolution — all 23 confirmed + 3 environment findings fixed (same session)

Implemented and verified across 5 committed batches on local `main` (push pending user OK).
Final state: **PickleVisionCore 91/91** (`swift test`), **app builds 0 warnings / 0 navigator issues**, **PickleVisionTests 5/5** on the iOS 26.5 simulator.

| Commit | Batch | Findings |
|---|---|---|
| `fc4093f` | calibration correctness | I2, I3, M1, M3, M4, M9, M2 |
| `252a606` | storage integrity | I1, I4, I8, M5 |
| `13d6355` | camera | I5, I6, I9, M7, M8, E1 |
| `5f763dd` | calibration UI + polish | I7, M6, M10, E3 |
| `b665be6` | app tests | E2 |

Product decisions taken (user-approved): **I2** reworked into a shape-based plausibility metric (not removed); **I9** the fps cap was lifted so the selected profile's rate applies; **E2** real app tests added to the existing `PickleVisionTests` target. The 19 refuted findings were left as-is (verified not-a-bug).

## Suggested fix order (historical — see Resolution above)

1. **Safety / correctness, low-risk, single clear fix:** I5 (thermal pause), I6 (stop session on background), I3 (overlay visible), I7 (drag grab-offset), M1 (project NaN guard), M4/M5 (corner-count validation), E1 (preview warning).
2. **Data integrity:** I1 (UUID-keyed storage), I8 (re-cal rename), I4 (custom-dims invariant), M6 (NVZ bounds).
3. **Product calls needed:** I2 (remove vs. rework fit-quality), I9 (support vs. remove 240fps), E2 (add an app-layer test target to the scheme).
4. **Polish:** M2, M3, M7, M8, M9, M10, E3.
