# Decision: Capture resolution / frame rate + the processing architecture

- **Date:** 2026-06-19
- **Status:** Direction accepted; exact defaults to be **measured and finalized in Phase 2** (ball tracking)
- **Scope:** How the app captures video and how it processes it for IN/OUT calls. Affects accuracy, on-device feasibility, thermals, and battery.

---

## Why this matters

Calling a ball IN/OUT comes down to locating the **bounce point** precisely against the line. Two capture properties drive that, and they trade off:

- **Resolution (1080p vs 4K) = spatial precision** — pixels-on-ball, sharpness of the line, how finely we place the contact point. Feeds the monocular 3D reconstruction directly.
- **Frame rate (60/120/240) = temporal precision** — the bounce happens *between* frames; higher fps brackets the actual contact moment more tightly and (via shorter exposure) reduces motion blur.

For a fast pickleball drive (~12–15 m/s): the ball travels ~25 cm/frame at 60 fps, ~12 cm at 120, ~6 cm at 240.

## iPhone 16 Pro capability (corrected)

- **Main lens: 4K up to 120 fps** (4K120 is a real, supported recording mode this generation), **1080p up to 240 fps** (slo-mo). **There is no 4K240 mode** — so 4K-vs-fps is a genuine choice.
- Ultra-wide: 4K60 max (fallback lens only).

## Compute reality (the important clarification)

- **Physics prediction is essentially free** — fitting a trajectory and finding the ground-crossing is microseconds. Never the bottleneck.
- **Neural-net ball detection is the cost — but it runs on a downscaled frame** (~512×288), *not* the full 4K. So inference at 120 (even 240) Hz is well within the A18 Pro Neural Engine. The "~1 Gpx/s" figure for 4K120 is raw capture/scaling throughput, not what the detector processes.
- The **real limit of sustained 4K120 is memory bandwidth / power / heat**, not raw inference compute. (`ThermalPolicy`, already built, manages this by stepping fps down as the phone heats.)
- 4K's spatial advantage **only materializes with ROI refinement**: detect the ball on a downscaled frame, then refine its position using full-res pixels in a *small crop* around the bounce. Downscale-and-detect alone pays 4K's cost for ~1080p precision.

## Decisions

1. **Processing architecture — prefer buffer-and-analyze (decouple capture rate from processing rate).**
   Capture to a short rolling buffer; run heavy detection + 4K-ROI refinement on only the **~15–20 frames around each bounce** (≈20 inferences per bounce, not 120/sec continuously). Call lands ~1 s late with a replay — fine for a self-ref. This removes the thermal wall and unlocks full 4K precision where it counts. Continuous live-every-frame processing is a secondary mode to evaluate, not the default.

2. **Capture profile — configurable + adaptive.**
   - Profiles: **Auto / 4K120 / 1080p240 / 1080p120 / battery-saver.**
   - **Current default: 1080p120** (right balance for the foundation + live preview).
   - **Dynamic by light:** step fps/resolution *up* when exposure has headroom (bright), *down* when dim (keep frames adequately exposed). Same shape as the thermal step-down.
   - **`ThermalPolicy` overrides everything** (caps fps as the phone heats).

3. **4K120 vs 1080p240, optimal light — lean 4K120.**
   Rationale: 4K120 captures ~2× the information (~1.0 vs ~0.5 Gpx/s) and its spatial detail feeds the 3D reconstruction and the (fundamentally spatial) line call. The decisive asymmetry: **a physics model can fill temporal gaps between frames far more reliably than it can invent spatial resolution you didn't capture.** Lost pixels are gone; missing time is interpolable.
   - **Prefer 1080p240 instead when:** the shot is very fast/flat (temporally-dominated), light is good-but-marginal (240 needs more light; 4K120's 1/120 s exposure is more forgiving), or we're thermal/compute-limited.

## To measure in Phase 2 (don't finalize on theory)

On a real court, drop identical bounces and compare **call accuracy** across **4K120 vs 1080p240 vs 1080p120**, with and without **4K-ROI refinement**, and validate **buffered vs live** processing for thermals/endurance over a full game. Then lock the default profile and the adaptive thresholds.

## Current implementation state

- `CameraFormatSelector(targetHeight:maxFrameRate:)` is already parameterized → the profile switch is a thin policy on top.
- `CameraService` targets **1080p120**; `ThermalPolicy` steps fps down on heat.
- Adaptive light policy, the buffer-and-analyze pipeline, and 4K-ROI refinement are **Phase 2** work (they belong with the ball tracker, where the payoff is measurable).

## Honesty / open uncertainty

No hard A18 Pro benchmarks for the actual detector throughput yet — feasibility above is reasoned from how the pipeline works (downscale-detect, buffered analysis), to be **validated on-device in Phase 2**.
