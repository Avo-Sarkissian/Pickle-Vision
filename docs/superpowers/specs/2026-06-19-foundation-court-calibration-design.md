# Pickle Vision — Spec 1: Foundation + Court Calibration

- **Date:** 2026-06-19
- **Status:** Approved design — pending implementation plan
- **Milestone:** Phase 0–1 of the Pickle Vision roadmap

---

## 1. Product vision (context)

Pickle Vision turns a single mounted iPhone into an automated referee for a pickleball court. The headline feature is calling balls **in vs. out**. Later features include ball speed, swing/volley classification, non-volley-zone ("kitchen") fault detection, player joint tracking, scorekeeping, and per-player stats. The app must adapt to both **regulation pickleball courts** and improvised layouts — notably playing on a tennis court using only the two front service boxes (no doubles alleys).

The product is decomposed into phases, each with its own spec → plan → build cycle:

- **Phase 0–1 · Foundation + Court Calibration** ← *this spec*
- Phase 2 · Ball tracking + IN/OUT calls
- Phase 3 · Players + joint tracking
- Phase 4 · Kitchen (NVZ) faults
- Phase 5 · Ball speed + swing/volley classification
- Phase 6 · Scorekeeping + player stats + session history

## 2. Scope

**In scope:** the app skeleton, the camera capture pipeline, the guided mounting/setup experience, and the court calibration system that produces a reusable image↔court coordinate map (`CourtModel`). This is the foundation every downstream phase consumes through one clean interface.

**Out of scope (later phases):** ball detection, in/out calls, player/pose tracking, kitchen faults, speed, shot classification, scoring, stats.

### Goals

- Capture a stable, high-frame-rate feed suitable for later ball tracking.
- Guide the user to a mounting position that yields accurate calls.
- Produce an accurate, persistent image↔court coordinate map for both supported court layouts.
- Detect when the phone has moved and protect downstream calls from a stale map.

### Non-goals

- No ball, player, or event detection.
- No refereeing output (that begins Phase 2).
- Auto-detect need not cover every conceivable court — manual tap is the guaranteed path.

## 3. Hardware & setup assumptions

- Single **iPhone 16 Pro**. The coordinate layer is built device-agnostic so a second phone can be added later, but a second device is not built now.
- **Main (1x) lens**, ~1080p120 processing target (4K vs. 1080p tuned against thermals on-device). It is the only lens that shoots 120fps, which is what makes the ball's bounce catchable.
- **0.5x ultra-wide** is a space-constrained fallback only. Using it triggers a one-time lens-distortion calibration, because its barrel distortion corrupts the homography otherwise.
- Mount: **tall tripod (~6.5–7 ft)** behind a baseline, slightly off the corner; a fence/pole clamp is an alternative where a well-placed fence exists.
- **No LiDAR for court mapping** — its ~5 m range is far short of the ~13 m court. Calibration is pure monocular vision.
- **Honest accuracy framing:** a single elevated camera is most accurate on the near baseline and weakest on the far sidelines (contact-point error grows as `ball_radius ÷ tan(camera angle)`). This phase delivers an accurate *static* court map; the calls it later enables are advisory near the line, not Hawk-Eye.

## 4. Architecture

Native Swift / SwiftUI, on-device, layered so each piece has one responsibility and later phases plug into the same coordinate map.

```
┌──────────────────────────────────────────────────────────┐
│  UI (SwiftUI)   SetupView · CalibrationView · OverlayView  │
├──────────────────────────────────────────────────────────┤
│  Coordination   SetupCoordinator · CalibrationController   │
├──────────────────────────────────────────────────────────┤
│  CV / Calibration                                          │
│    CameraService  · CourtAutoDetector · HomographySolver   │
│    StabilityCheck · ManualAdjust      · LensCalibration    │
├──────────────────────────────────────────────────────────┤
│  Domain         CourtModel · CourtProfile · CalibrationStore│
└──────────────────────────────────────────────────────────┘
```

### Components (responsibility · interface · depends on)

**Capture**
- **`CameraService`** — owns the `AVCaptureSession`; configures the Main lens at the target format; monitors thermal `systemPressure` and steps down frame rate before the OS forces a shutdown. *Out:* a stream of frames (`CMSampleBuffer`) + camera intrinsics. *Deps:* AVFoundation.

**Guided setup**
- **`StabilityCheck`** — confirms the phone is steady via frame-to-frame registration. *Out:* a stable/shaky signal. Reused at runtime by the drift guard.
- **`SetupCoordinator`** — runs the live "good position?" checks (whole court visible, steady, decent angle) and drives the coaching UI. *Deps:* `CourtAutoDetector`, `StabilityCheck`.

**Calibration (auto leads, manual catches)**
- **`CourtAutoDetector`** — detects court keypoints against known templates (pickleball / tennis); returns candidate points + confidence. *Deps:* Vision / Core ML.
- **`ManualAdjust`** — draggable point handles over the live feed, with a magnifier loupe for precise placement; also the path when auto-detect fails.
- **`CourtProfile`** — defines each supported layout's expected points, real-world dimensions, in-bounds rule, net line, and (placeholder) NVZ line.
- **`LensCalibration`** — optional undistortion params, only when the 0.5x fallback is used.
- **`HomographySolver`** — turns confirmed points + the profile's real-world dimensions into the image↔court mapping (both directions) plus an estimated camera pose and accuracy.

**Domain**
- **`CourtModel`** — the calibrated result every later phase consumes (see §5).
- **`CalibrationStore`** — saves/restores a `CourtModel` per venue, so the user only re-calibrates when the phone moves.

**Verification**
- **`CourtOverlayView`** — draws the mapped court back onto the live feed, plus a tap-to-read-coordinate sanity test.

**Key boundary:** everything downstream (ball, players, kitchen, stats) depends *only* on `CourtModel`. The entire CV/calibration layer sits behind that interface and can be improved or swapped without touching the rest.

## 5. Court model & profiles

`CourtModel` is the single interface later phases depend on:

- `imageToCourt` / `courtToImage` homography (both directions)
- real-world line geometry (sidelines, baselines, net line, NVZ lines, centerline)
- in-bounds polygon (which boundary counts as "in")
- net line; NVZ/kitchen line(s) — including a **virtual** kitchen line for the tennis-front-box layout, which has no painted NVZ
- estimated camera pose and a calibration-confidence/accuracy estimate

`CourtProfile` defines the expected keypoints, real-world dimensions, and in-bounds rule per layout:

- **Regulation pickleball** — 20 × 44 ft, 7 ft non-volley zone.
- **Tennis front-box** — the service boxes on each side of the net (the "front" half of each side, no doubles alleys, no back court) form the in-bounds region; net at the real tennis net; a virtual NVZ line since there is no painted kitchen.
- **Custom** — user taps an arbitrary in-bounds quad + net line + optional virtual NVZ, and confirms real-world dimensions for scale.

## 6. Calibration flow

Phone mounted in landscape, behind a baseline.

1. **Position & frame.** Live coaching on steadiness, elevation, and full-court framing. "Continue" unlocks only when all checks are ✓. If the court physically can't fit at 1x, the app offers the 0.5x fallback (triggering lens-distortion calibration).
2. **Auto-detect & confirm.** The app detects the court and drops the keypoints; the user confirms the layout (pickleball / tennis front-box / custom). Low confidence drops silently to step 3.
3. **Fine-tune (manual catch).** Drag any point; a magnifier loupe shows the line under the fingertip. This is also the full fallback when auto-detect can't read faded paint.
4. **Verify & save.** The calibrated court is drawn back over the feed; tapping anywhere reads its real court coordinate as a sanity check. Saving persists the `CourtModel` per venue.

**Drift guard (runtime, always-on).** `StabilityCheck` runs for the whole session. If the mount shifts (wind, a bump), the saved calibration and the live court diverge, so the app **immediately pauses downstream calls** rather than judging against a stale map. It then attempts **auto-realign** (re-detect and re-fit the homography); if that fails, it asks the user to re-tap. Calls resume only once the map is locked again. This reuses `StabilityCheck` + `CourtAutoDetector` — no new machinery.

## 7. Data flow

```
CameraService ──frames──▶ SetupCoordinator ──(position OK)──▶ Calibration
                                                  │
                        CourtAutoDetector ∥ ManualAdjust ──points──▶ HomographySolver
                                                                          │
                                                                     CourtModel ──▶ CalibrationStore (persist)
                                                                          │
                                                                     CourtOverlayView (verify)
                                                                          │
        ◀───── Drift guard: StabilityCheck monitors; on drift, pause + re-enter Calibration ─────
```

## 8. Error handling

Guiding rule: **never block on a CV failure — always fall back to manual, and never call against an unreliable map.**

- **No camera permission / camera unavailable** → explain and deep-link to Settings.
- **Auto-detect fails or low confidence** → silently drop to manual tap with a hint. Auto is a convenience, never a gate.
- **Poor lighting / glare / faded paint** → flagged in setup coaching; manual still works.
- **Court won't fit / camera too low** → "Continue" stays locked with coaching; offer the 0.5x fallback if it can't fit at 1x.
- **Phone moved mid-session** → the drift guard (pause → auto-realign → manual fallback).
- **Calibration not accurate enough** → if reprojection/tap-test error exceeds tolerance, warn that calls will be unreliable and surface a plain-language confidence (good / fair / poor).
- **Thermal pressure** → `CameraService` steps down frame rate with a warning before the OS intervenes.
- **Saved calibration won't load / venue looks different** → prompt a fresh calibration rather than trusting stale data.

## 9. Testing & acceptance

- **Unit tests (logic, no device):** `HomographySolver` against synthetic point sets (round-trip image→court→image within epsilon); `CourtProfile` geometry; `CalibrationStore` save/load round-trip; drift-guard trigger logic on a simulated shifted frame.
- **Recorded-clip fixtures:** a few reference videos from the mount, used as regression fixtures so auto-detect and homography can be iterated off-court.
- **Accuracy check (the real metric):** the tap-test — tap known physical points (a corner, the centerline) and confirm the reported court coordinate lands within a few inches; surface the reprojection error as the confidence number.
- **On-device acceptance (definition of done):** a real session on an actual court with the iPhone 16 Pro mounted — the app guides the user to a good position, produces a court overlay that visibly tracks the real lines, passes the tap-test within tolerance, persists the calibration, and the drift guard correctly pauses and recovers when the phone is bumped. A CV/hardware feature is "done" only when it works on the real court.

## 10. Open questions / future hooks

To resolve in the implementation plan, not blocking this design:

- **Auto-detect model source:** adapt an existing open-source court-keypoint model (e.g. a TennisCourtDetector-style heatmap net) vs. train a small Create ML model vs. bootstrap with Vision rectangle/contour detection. The strong auto-assist bias favors a keypoint model, with the Vision approach as an interim.
- **OpenCV vs. pure Swift/Accelerate:** a manual 4-point homography is a simple linear solve (pure Swift is fine); RANSAC for noisy auto-detected points and 0.5x undistortion may favor OpenCV. Decide in the plan.
- **Processing resolution / frame rate:** 4K120 vs. 1080p120 — settle empirically against thermals on-device.
- **Second-phone support:** keep `CourtModel` and the coordinate layer device-agnostic so a second device (one behind each baseline) can be added later without rework.
