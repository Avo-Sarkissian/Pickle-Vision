# Pickle Vision — UI Design Spec: Direction B "Instrument · Daylight"

- **Date:** 2026-06-19
- **Status:** Approved design north star — guides all UI plans from Plan 3 polish onward
- **Source:** Design exploration "Direction B — Instrument · Daylight" (9-board layout: design system, Home/Settings/History, Camera/Live, Calibration flow, edge cases, drift guard)
- **Applies to:** every screen of the app; supersedes ad-hoc UI choices in Plans 2–3

---

**Canonical design reference (in-repo):** `docs/design/handoff-instrument-daylight.md` (full token table + per-screen data bindings, high-fidelity) and the 10 board renders in `docs/design/screenshots/`. This spec is the engineering layer over that handoff — invariants, open decisions, repo corrections, and the build backlog.

## 1. Principle

**Precise like an instrument. Legible in full sun.** This is an outdoor, one-handed, on-device tool that makes line calls. Two surfaces with opposite needs:

- **Menus go light** — near-white "paper" so they're readable outdoors at arm's length.
- **Camera screens go dark, full-bleed video** — high-contrast cyan instrument overlays that **hug the edges and never cover the playing area.**

On-device only — **no login, no cloud, no account.** Every readout binds to something real in the repo; we do not render data we cannot compute.

## 2. Non-negotiable engineering invariants

These are product-credibility rules, not styling. Plans must honor them.

1. **Honest confidence — never fabricate accuracy.** This tool calls balls in/out. Any numeric accuracy shown (tap-test "OUT · 1.4 in", "Confidence by zone ±2/±3/±6 in", auto-detect "94%") MUST be computed from real signal (homography reprojection residual, modeled error from mount geometry, or detector score). If it isn't computed yet, **omit it** — do not ship decorative precision. A wrong "±2 in" destroys trust faster than showing nothing.
2. **Never hard-block on a CV failure.** Auto-detect leads, manual catches. The position-check gate ("Phone steady / Whole court visible / Raise mount") is **advisory** — the user can always proceed manually past `Continue`, and low auto-detect confidence always falls back to manual corner drag. Manual tap is the guaranteed path (per Foundation spec §Non-goals).
3. **Readouts bind to real symbols.** Format/fps/thermal ← `CameraService` (`selectedFormatDescription`, `measuredFPS`, `thermal`). Saved courts ← `StoredCalibration` (venue, layout, corners, save date — nothing more is persisted). Map math ← `CourtModel`.
4. **On-device only.** No network, no account UI, ever. Footer reads `ON-DEVICE · NO ACCOUNT`.

## 3. Orientation model (per-screen)

The phone is browsed in the hand (portrait) and **mounted landscape** behind the baseline for play. Therefore orientation is **per-screen**, not app-global:

- **Portrait:** Home, Settings, History (menus).
- **Landscape (forced):** Camera/Live, Calibration (incl. permission-denied + drift states).

Implemented via a `UIApplicationDelegate.supportedInterfaceOrientationsFor` driven by a per-screen `AppOrientation.mask`, set in each screen's `.lockOrientation(_:)`. Info.plist must keep Portrait + Landscape (both) enabled; the runtime mask narrows per screen. (Replaces the brief app-global landscape lock from 5f2400e.)

## 4. Palette

**Exact tokens — canonical source is `docs/design/handoff-instrument-daylight.md`** (full table there). The instrument accent is **optic-yellow** (never blue/green, so the overlay always contrasts the real court). Key values:

**Light · menus**
- `paper` — light bg `#f4f5f3` (cards `#ffffff`, hairline `#e8ebe9`)
- `ink` — primary text / text on yellow `#14181b`
- `in` — in-bounds blue `#4d9bff` (call/text), swatch `#2f63c2`
- `out` — out-of-bounds green `#46c46a`
- primary action — **optic-yellow `#e6f53a`** (ink text on it); destructive red `#e5402a` (Delete)
- muted text `#5e6a70` / `#7a848a` / `#8a949a`

**Dark · video overlay**
- `feed` — live-video stand-in gradient `linear-gradient(176deg,#13343a,#0e2228,#0a1418)` (real = `AVCaptureVideoPreviewLayer`)
- `panel` / chrome — `#0c1216` / `#101920` / `#17242b`; rail bg `#101920`; borders `#1e2a31` / `#25333a`; pills `rgba(8,14,17,0.82)`
- `overlay` — **optic-yellow `#e6f53a`** computed lines / handles / loupe ring / primary
- `warn` — amber `#f4b53a` (also `#e08a16`) thermal / drift / NVZ / incomplete checks
- court zones — in-bounds **blue** (fill `rgba(61,134,245,0.06–0.16)`), apron **green**; text on dark `#eaf6f9` / `#dbe8ff`

Semantic use: optic-yellow = computed/active, blue = in-bounds, green = apron/out, amber = caution, red = record/destructive. Color is never the only signal — always paired with text (IN/OUT, COOLING…).

**OPEN DECISION — IN/OUT verdict color (resolve before Phase 2).** Phase-2 call badges currently read IN=blue / OUT=green to match the spatial zones. Internally consistent, but inverts the strong cultural prior (green=in / red=out; Hawk-Eye shows OUT red) — a green "OUT" can misread at a glance. Lean: keep blue/green for the spatial court overlay, but give the verdict badge a judgment palette (OUT in amber or red). Not blocking now (Phase 2 element).

## 5. Type

- **SF Pro Display** — display / titles / scoreboard (bold/heavy, tight tracking ~-0.01em)
- **SF Pro Text** — UI / body
- **SF Mono** — data readouts / labels (uppercase labels, letter-spacing 0.1–0.18em)

**SF Pro / SF Mono are the shipping fonts** (handoff §Typography). The HTML board renders Saira / Manrope / IBM Plex Mono for flavor, but the native app ships SF unless we later choose to bundle the custom faces — so font bundling is **optional polish, not on the critical path**. Sizes (pt ≈ px in the mock): hero 44, section H2 28, screen title 20–28, body 13–14, data/labels 9–11 (mono). Keep overlay text ≥ ~11 pt, readable at arm's length.

## 6. Screens

### Home (portrait, light) — "Ready to ref."
Big display headline, mount hint ("Mount the phone behind the baseline, in landscape."), prominent **Start a session →** (cyan). **Saved courts** list from `CalibrationStore`: each row = venue · layout · dimensions · relative save date, with a re-calibrate affordance. Settings gear top-right. Footer `ON-DEVICE · NO ACCOUNT`.

### Settings (portrait, light)
**Capture profile** picker: Auto ("best format, steps down on heat") / 4K·120 (HEAT badge) / 1080p·240 (slo-mo) / 1080p·120 (default) / Battery saver — must map to selectable `CameraFormatSelector` formats + `ThermalPolicy`. **Manage saved courts** (Delete per court). Note: 1080p·240 was deprioritized in the capture-decisions doc vs 4K·120 — offer only if the format is actually vendable.

### History / Sessions (portrait, light) — **future (Phase 6)**
Shown as placeholder now: "Scores and stats record here once scoring ships." Tag `PHASE 6`.

### Camera / Live (landscape, dark)
Full-bleed video; status + future placeholders hug the corners, playing area stays clear. Top: `REC`, `1080p · 120fps`, `IN/OUT CALLS` (PHASE 2 placeholder), thermal pill (`COOLING · 90fps`, amber). Bottom: score `6·3` (PHASE 6 placeholder), `SLO-MO REPLAY` (placeholder), **Calibrate** action. Court drawn as cyan trapezoid. Permission-denied is a dark landscape state with "Camera access is off → Open Settings."

### Calibration (landscape, dark) — `Position → detect → fine-tune → verify`
Frozen `latestImage` is the canvas; the **control rail sits beside it** (right column) so fingers never cover the court. Steps:

1. **Position & frame** — POSITION CHECK card (Phone steady / Whole court visible / Raise mount ~1 ft), `Continue` gated at 3/3 **but always manually overridable**; "Won't fit? Use 0.5× →" escape.
2. **Auto-detect & confirm** — "Court detected NN%", layout selector (Pickleball / Tennis box / Custom), `Fine-tune →`. Low confidence → straight to manual.
3. **Fine-tune** — drag 4 corners (`NL·NR·FR·FL`) with magnifier loupe, FROZEN FRAME badge, Court-overlay toggle, `4/4 corners set`, Re-freeze, Save.
4. **Verify / Save court** — tap-test readout (`x · y ft`, IN/OUT, distance-from-line), **Confidence by zone** (near baseline / mid-net / far sidelines), VENUE NAME field, `Save court`.

**Edge cases (never block):** "Court won't fit at 1× → switch to 0.5× ultra-wide" (needs a one-time lens-distortion calibration — barrel curve would warp the map); **Custom layout** real dimensions entry (Width / Length / Kitchen NVZ → Apply) feeding `CustomDimensions`.

### Drift guard (landscape, dark) — **future (Plan 4)**
Runtime: `CALLS PAUSED` pill + "Mount moved — re-aligning" card, "The court no longer lines up with the saved map. Pausing calls so a stale map can't make a bad one." Actions: **Re-tap court** / Dismiss.

## 7. Data-binding map (UI ← repo)

| UI element | Source of truth |
|---|---|
| Format / fps / thermal pills | `CameraService.selectedFormatDescription`, `.measuredFPS`, `.thermal` |
| Saved-court rows | `CalibrationStore` → `StoredCalibration` (venue, layout, corners, savedAt) |
| Layout selector / dimensions | `CourtLayout`, `CustomDimensions` |
| Court overlay + tap-test IN/OUT | `CourtModel.isInBounds`, `courtPoint(forImage:)` |
| Frozen canvas | `CameraService.latestImage` / `imageSize` |
| Tap-test "distance from line" | **NEW** core method needed (signed distance to nearest boundary) |
| Confidence by zone / detect % | **NEW** error model + detector score needed |

## 8. Implied implementation backlog (design promises that need real work)

- **Per-screen orientation controller** (this session) — replace app-global lock.
- **Fonts:** ship **SF Pro / SF Mono** (no work). Bundling Saira / Manrope / Plex Mono is optional polish, not required.
- **Fit-quality indicator (v1):** single qualitative "Good/Fair" + 4-seg bar from the homography reprojection residual — show in Fine-tune/Save now.
- **`CourtModel` signed distance-to-nearest-line (Phase 2)** — backs the tap-test "± in".
- **Per-zone ±in confidence (Phase 2)** — needs on-court measurement; omit until real (per §2.1).
- **Position-check sensing** — CoreMotion (steady) + CV/geometry (whole-court, mount height); advisory only.
- **Auto-detect (Plan 3.5)** with confidence % + manual fallback.
- **Express re-calibrate path** — Home re-cal icon jumps a saved court straight to Fine-tune (skip position/detect).
- **Make "verify" functional** — prompt tap on a known line, show residual.
- **Capture-profile parity** — confirm each Settings option maps to a real `CameraFormatSelector` format.

## 8a. Verified against the repo (2026-06-20)

The 2nd design pass's layout numbers were checked against `CourtProfile`/`CustomDimensions` and **match**: regulation pickleball **20×44 · NVZ 7**, tennis front-box **27×42 · NVZ 7**, custom = user `CustomDimensions(widthFeet, lengthFeet, nonVolleyZoneFeet)` (Custom card's Width / Length / Kitchen (NVZ)). The Home saved-court dims and the "Court layouts" atom are accurate, not decorative. The honest-confidence and never-hard-block fixes are fully reflected (numbers quarantined to a "Phase 2 · aspirational" row; Continue-anyway / Calibrate-manually / auto-detect-fail states all present).

**Handoff corrections (verified in code) — these override the handoff doc where they conflict:**
- **Drift guard uses `DriftDetector`** (`DriftState` + `evaluate(translation:rotationRadians:)`) — the handoff's "reuse `StabilityCheck`" names a type that **does not exist** in the repo.
- `ThermalRecommendation` confirmed: `shouldWarn` / `frameRateCap: Double?` / `message: String?`.
- **No 4K240 on iPhone 16 Pro** (main lens: 4K ≤120, 1080p ≤240). Settings must not offer 4K·240; `ThermalPolicy` overrides the effective cap.
- **Fit-quality is a v1 element, not deferred:** show a single qualitative "Good/Fair" + 4-segment bar derived from the **homography reprojection residual** (computable today) in Fine-tune/Save. Only per-zone ±in and detect % are Phase 2.

## 9. Phase tagging (what's real now vs later)

- **Now (Phase 0–1):** Home, Settings (capture profile + manage courts), Calibration flow (position/detect/fine-tune/verify), per-screen orientation. Confidence numbers only where computable.
- **Phase 2:** Live IN/OUT calls, slo-mo replay, tap-test accuracy that matters.
- **Plan 4:** Drift guard runtime.
- **Phase 6:** History/Sessions, score overlay, per-player stats.
