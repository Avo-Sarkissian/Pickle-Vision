# Handoff: Pickle Vision — Phase 0–1 UI (Foundation + Court Calibration)

## Overview
Pickle Vision turns a tripod-mounted iPhone into an automated pickleball referee. This handoff covers the **Phase 0–1** interface: the app shell, the camera/live screen, and the full **court-calibration flow** (mount → frame → detect → fine-tune → verify → save), plus settings, history, drift-guard, and edge-case states. The headline downstream feature (IN/OUT line calls) is Phase 2+, represented here only as clearly-labelled placeholders.

The design direction is **"Instrument · Daylight"**: light, high-contrast menus for outdoor readability + dark, full-bleed camera screens with an **optic-yellow** computed overlay that contrasts the real (blue/green) court surface.

## About the Design Files
The file in this bundle (`Pickle Vision - Instrument Daylight.dc.html`) is a **design reference created in HTML** — a single scrollable board of labelled phone frames showing intended look, layout, and states. **It is not production code to copy.**

This project already has a **native Swift / SwiftUI codebase** (the `PickleVision` app target + the `PickleVisionCore` Swift package). The task is to **recreate these designs as SwiftUI views in that existing codebase**, using its established patterns and binding to the APIs that already exist (`CameraService`, `CalibrationStore`, `CourtModel`, `CourtProfile`, `CustomDimensions`). Do **not** ship HTML, and do **not** invent new data models — match what the repo already exposes.

Target device: **iPhone 16 Pro**. On-device only — **no login, accounts, cloud, or backend.**

## Fidelity
**High-fidelity.** Final colors, type, spacing, and copy. Recreate pixel-faithfully in SwiftUI (SF Pro / SF Mono are the intended shipping fonts — see Typography). Treat the HTML's exact hex values, weights, and copy as the spec.

---

## Orientation rules (structural, not stylistic)
- **Portrait:** Home, Settings, History (menus). Operable one-handed.
- **Landscape:** Camera/live, all Calibration steps, and (future) live-game. The phone is tripod-mounted in landscape behind the baseline.
- **Camera screens are full-bleed video** with overlays layered on top. **Overlays must never cover the court playing area** — status/readouts hug the corners; calibration controls sit in a **side rail beside** the frame, never stacked over it.

---

## Design Tokens

### Color — semantic system
The core idea: **the app's overlay must contrast the real court, so it is never blue or green.**

| Token | Hex | Meaning / usage |
|---|---|---|
| **Overlay / accent (optic yellow)** | `#e6f53a` | Everything the app draws: computed court lines, corner handles, keypoints, loupe ring, HUD highlights, brand reticle, primary buttons/active chips (with ink text), toggles. |
| **In-bounds blue** | `#4d9bff` (call/text), `#2f63c2` (swatch), `rgba(61,134,245,0.06–0.16)` (surface fill tint) | The **IN** call; in-bounds court-surface fills; "fit quality good" indicator. |
| **Out-of-bounds green** | `#46c46a` | The **OUT** call; out-of-bounds apron. |
| **Caution amber** | `#f4b53a` (also `#e08a16`) | Thermal/cooling, kitchen (NVZ) fault, "fair", far-sideline lower-accuracy cue, incomplete checks. |
| **Error / record red** | `#e5402a` | REC dot, destructive Delete. |
| **Ink (text on light + on accent)** | `#14181b` | Primary text on light menus; text/dots on yellow fills. |
| **Paper (light bg)** | `#f4f5f3` | Portrait-menu background. White cards `#ffffff`, hairline `#e8ebe9` / `#e2e6e6`. |
| **Light muted text** | `#5e6a70`, `#7a848a`, `#8a949a`, `#9aa3a8` | Secondary text on light. |
| **Feed (dark video)** | gradient `linear-gradient(176deg,#13343a,#0e2228,#0a1418)` | Stands in for the live camera feed (replace with `AVCaptureVideoPreviewLayer`). |
| **Dark panel / chrome** | panel `#0c1216` / `#101920` / `#17242b`; rail bg `#101920`; borders `#1e2a31` / `#25333a` / `#2a3a42` | Instrument panels, control rail, status pills (pills `rgba(8,14,17,0.82)`). |
| **Light text on dark** | `#eaf6f9` (near-white), `#dbe8ff` (readout), `#bcd0d8`, `#9fb4bd`, `#9bc3ff`, `#5f8595` (mono labels) | Text/labels on dark screens. |

### Typography
Three families, with **SF Pro / SF Mono as the shipping fallback** (the HTML loads Saira/Manrope/IBM Plex Mono from Google Fonts; in the native app prefer SF unless the custom fonts are bundled):

| Role | HTML font | **Native (use this)** |
|---|---|---|
| Display / titles / scoreboard | Saira / Saira Condensed (700–800) | **SF Pro Display**, bold/heavy, tight tracking (`-0.01em`) |
| UI / body | Manrope (400–800) | **SF Pro Text** |
| Data / readouts / labels | IBM Plex Mono (400–600) | **SF Mono** |

Common sizes (pt ≈ px in the mock): hero title 44; section H2 28; screen title 20–28; body 13–14; data/labels 9–11 (mono, letter-spacing 0.1–0.18em, uppercase for labels). On 1080-tall landscape screens keep overlay text ≥ ~11px equivalent and readable at arm's length.

### Spacing / radius / shadow
- Device frames: portrait screen 322×698 (radius 42), landscape screen 720×332 (radius 36). These are mock proportions — in SwiftUI just fill the real screen safe-area.
- Card radius 14–18; pill/chip radius 9–18; button radius 11–16.
- Panel padding 14–24; gaps 6–12.
- Card shadow (light): `0 1px 3px rgba(0,0,0,0.08)`. Primary-button glow allowed but subtle.

---

## Screens / Views

> Frames appear left-to-right in the HTML board, grouped by section (01 Menus, 02 Camera, 03 Calibration, edge cases, Phase-2 numbers, 04 Atoms, 05 photo test).

### 1. Home (portrait, light) — populated + empty state
- **Purpose:** Start a session; reload a saved court; reach settings.
- **Layout:** Header row (brand reticle + "PICKLE VISION" wordmark, settings gear). Hero title "Ready to ref." (Saira/SF Pro Display, 44). Subtitle. Primary yellow button **"Start a session →"** (ink text). "SAVED COURTS" mono label + count. List of saved-court cards. Footer chip "ON-DEVICE · NO ACCOUNT" (yellow dot).
- **Saved-court card:** mini court thumbnail (dark tile, blue in-bounds fill + yellow outline) · venue name · `"<layout> · <W×L> ft · <relative date>"` · a **↻ reload** affordance.
- **Data:** from `CalibrationStore` — only `venueName`, `layout`, dimensions, and `savedAt` are persisted (no confidence is stored). Show only those.
- **Empty state (first launch):** title "First court.", button **"Set up your first court →"**, and a dashed placeholder card "No saved courts yet / Calibrated courts live here — set one up and it's one tap to reload next time."

### 2. Settings (portrait, light)
- **Purpose:** Pick capture profile; manage saved courts.
- **Capture profile** (single-select list; bind to `CameraFormatSelector` policy):
  - **Auto** — "Adapts to light, steps down on heat" — *selected (✓)*
  - **4K · 120 fps** — pill **RECOMMENDED** (yellow) — most spatial detail
  - **1080p · 240 fps** — "fast, flat shots"
  - **1080p · 120 fps** — pill **DEFAULT** (grey) — current `CameraService` target
  - **Battery saver** — unselected radio
  - Helper note: "4K·120 gives the most spatial detail for line calls; the app starts at 1080p·120 and steps fps down under heat. Final defaults land in Phase 2."
  - (iPhone 16 Pro reality: main lens does 4K up to 120 and 1080p up to 240; **there is no 4K240**. `ThermalPolicy` overrides everything.)
- **Manage saved courts:** rows with venue + layout + red **Delete**.
- Footer: "Pickle Vision · v0.1 · iPhone 16 Pro".

### 3. History (portrait, light) — future-phase placeholder
- Title "Sessions" + "PHASE 6" pill. Ghosted (0.55 opacity) sample rows (venue · date · score · duration) and a dashed "Per-player stats · kitchen faults · speed — arrive with later phases." Structure only; no real data yet.

### 4. Camera / Live (landscape, dark)
- **Purpose:** Live preview; enter calibration; (future) calls/score/replay.
- **Layout:** full-bleed feed; faint yellow court overlay centered (court area kept clear). Edge-pinned chrome:
  - **Top-left cluster:** REC pill (red dot + `REC 12:04`), format pill `1080p · 120fps` (← `CameraService.selectedFormatDescription`), fps pill `118 fps` (← `measuredFPS`).
  - **Top-right:** thermal pill `COOLING · 90fps` (amber) — shown when `CameraService.thermal.shouldWarn`; text from `thermal.message`.
  - **Top-center (placeholder, dashed):** "IN / OUT CALLS · PHASE 2".
  - **Bottom-left (placeholder, dashed):** score `6 / 3 · SCORE · PHASE 6`.
  - **Bottom-right:** dashed "SLO-MO REPLAY" placeholder + solid **Calibrate** button (yellow outline + reticle icon).
  - All placeholders are non-blocking and must not cover the court.
- **Permission-denied state** (separate frame): camera glyph, "Camera access is off", "Pickle Vision needs the camera to see the court. Everything stays on this device.", **Open Settings** button → `UIApplication.openSettingsURLString`. (Mirrors existing `CameraScreen.swift`.)
- **Drift guard** (runtime state, separate frame): when the mount shifts, the saved map and live court diverge → amber **CALLS PAUSED** banner + centered modal "Mount moved — re-aligning" (spinner), buttons **Re-tap court** / **Dismiss**. The ghost overlay shows the saved court vs the drifted live court. Never judge against a stale map.

### 5. Calibration sub-flow (landscape, dark) — the core of Phase 1
Frozen `CameraService.latestImage` is the working surface; a **204px control rail** sits on the right (frame ~516px on the left). Steps:

- **Step 1 — Position & frame (guidance, NEVER blocks):** dashed framing guide + corner ticks; faint partial court. Right HUD "POSITION CHECK" with items **Phone steady ✓**, **Whole court visible ✓**, **Raise mount ~1 ft !** (amber). Note "A higher angle sharpens near-line calls — but any angle still works."
  - **Critical:** **Continue is ALWAYS enabled.** Primary **Continue anyway** + secondary **Calibrate manually** (skips auto-detect) + caption "2 / 3 — go anyway". Bottom-right "Won't fit? Use 0.5× →".
- **Step 2 — Auto-detect & confirm (v1):** detected keypoints (yellow dots, white ring) + court outline. Pill **"Court found"** — **no percentage in v1.** Layout chips **Pickleball** (active, yellow) / Tennis box / Custom. Copy "Confirm the layout, or drag any corner." Button **Fine-tune →**.
  - **In-progress state:** scan band + spinner "Finding the court…" + **Calibrate manually instead**.
  - **Hard-fail state:** "Couldn't find the court / Faded paint or odd lighting can hide the lines. Drag the four corners yourself — it's the guaranteed path." Buttons **Drag the corners** (→ manual) / **Try auto again**.
- **Step 3 — Fine-tune (manual catch):** 4 draggable corner handles in `[nearLeft, nearRight, farRight, farLeft]` order (active handle enlarged with a halo + a label e.g. "farLeft"); a **magnifier loupe** showing the line under the fingertip with a center reticle. Rail: **LAYOUT** chips (Pickleball 20×44 / Tennis box 27×42 / Custom set ft), **Court overlay** toggle (on), "4 / 4 corners set", buttons **Re-freeze** / **Save**.
- **Step 4 — Tap-test & save (v1):** tap anywhere on the mapped court → readout shows court coords `x 0.2 · y 12.6 ft` + **`IN`/`OUT`** only (compute via `CourtModel.courtPoint(forImage:)` + `isInBounds`). **No "± inches" in v1.** Rail: venue-name text field (yellow caret), **FIT QUALITY** block (qualitative "Good" + a 4-segment bar, derived from corner-fit/reprojection residual) + "4/4 corners set" + note "From corner-fit residual. Per-zone ± inches arrive in Phase 2.", buttons **Back** / **Save court** → persists a `StoredCalibration`.

### 6. Calibration edge cases
- **0.5× ultra-wide fallback** card: "Court won't fit at 1× / Switch to the 0.5× ultra-wide. It needs a one-time lens-distortion calibration — its barrel curve would otherwise warp the map." Buttons **Switch to 0.5×** / **Keep 1×**.
- **Custom layout dimensions** card: three fields **Width / Length / Kitchen (NVZ)** in feet (defaults shown 18.0 / 40.0 / 7.0). These map 1:1 to `CustomDimensions(widthFeet, lengthFeet, nonVolleyZoneFeet)`. Button **Apply dimensions**.

### 7. "Phase 2 numbers" (aspirational, NOT shipped in v1)
Three cards, each tagged with the capability that unlocks it — keep these **out of the v1 UI**; they document the future numeric layer:
- **Auto-detect confidence** `94%` — `PHASE 2 · KEYPOINT MODEL`.
- **Per-zone accuracy** `±2 / ±3 / ±6 in` (near/mid/far) — `PHASE 2 · MEASURED ON COURT`.
- **Distance from the line** `OUT · 1.4 in` — `PHASE 2 · BALL TRACKING`.

### 8. Atoms / reference
- **Status readouts:** REC, `1080p · 120fps`, `118 fps`, `COOLING · 90fps`.
- **Court layouts (`CourtProfile`):** Regulation pickleball 20×44 NVZ 7 · Tennis front-box 27×42 NVZ 7 · Custom (user ft).
- **Call vocabulary (Phase 2+):** **IN** (blue `#4d9bff`) · **OUT** (green `#46c46a`) · **KITCHEN** (amber, "NVZ fault").
- **Section 05 "Try on your court":** a drop-an-image frame used only to sanity-check overlay legibility against a real photo — not an app screen.

---

## Interactions & Behavior
- **Never hard-block on a CV result.** Position checks are guidance; Continue is always tappable; "Calibrate manually" always available; auto-detect failure drops to manual drag. Manual tap is the guaranteed calibration path.
- **Honesty rule (important):** never show a computed accuracy number we can't actually produce yet. v1 shows IN/OUT, court coordinates, "N/4 corners set", and a single qualitative fit-quality derived from the corner-fit residual. Per-zone ± inches and detect % are **Phase 2** and must be labelled as such if shown at all.
- **Drift guard** runs the whole session (reuse `StabilityCheck`): on mount shift → pause calls → auto-realign → fall back to re-tap. Calls resume only once the map re-locks.
- **Express re-calibrate:** tapping a saved court's **↻** jumps straight to **Step 3 (Fine-tune)** for that court (skip Position + Detect).
- **Thermal:** when `thermal.shouldWarn`, show the amber cooling pill; `ThermalPolicy` already steps fps down.
- Loupe follows the dragged corner and magnifies the line beneath the finger (offset so the finger doesn't occlude it). Hit targets ≥ 44pt.

## State Management
Bind to existing types — don't duplicate them:
- **`CameraService` (`ObservableObject`)** `@Published`: `permission` (`.unknown/.authorized/.denied`), `isRunning`, `selectedFormatDescription` (e.g. "1080p · 120fps"), `measuredFPS`, `thermal` (`ThermalRecommendation`: `shouldWarn`, `frameRateCap`, `message`), `latestImage` (`CGImage?` frozen frame), `imageSize`.
- **Calibration draft state (view-model):** four image-space corners (drag), selected `CourtLayout`, optional `CustomDimensions`, overlay-visible toggle, current tap-test point, computed `CourtModel?`, qualitative fit quality (from homography residual), and a coarse setup-check state (steady / framed / angle) that informs guidance **but never gates**.
- **Persistence:** `CalibrationStore.save(StoredCalibration)` / `load` / `courtModel(from:)`. `StoredCalibration` = `venueName, layout, imageCorners[4], customDimensions?, savedAt`. Homography is recomputed on load (not stored).
- **Capture profile** selection is a thin policy on top of `CameraFormatSelector(targetHeight:maxFrameRate:)`.

## Assets
- No raster art is required. The court overlay is **vector** (straight lines/polygons) — draw it in SwiftUI with `Path`/`Shape`/`Canvas`, not images.
- The "live feed" gradient and the Section-05 drop-image slot are mock stand-ins; the real feed is `AVCaptureVideoPreviewLayer` over `CameraService.session`.
- Icons (gear, chevrons, camera, reticle) → use **SF Symbols** in the native app.

## Files
- `Pickle Vision - Instrument Daylight.dc.html` — the design board (open in a browser to view all frames; scrolls horizontally).
- `support.js`, `image-slot.js` — runtime helpers so the HTML opens standalone. **Not part of the app** — ignore for implementation.

## Repo references (ground truth — read these, match their APIs)
- Spec: `docs/superpowers/specs/2026-06-19-foundation-court-calibration-design.md`
- Capture decision: `docs/decisions/2026-06-19-capture-resolution-and-processing.md`
- Existing views: `PickleVision/PickleVision/HomeView.swift`, `CameraScreen.swift`, `CameraService.swift`
- Core: `PickleVisionCore/Sources/PickleVisionCore/` — `CourtModel`, `CourtProfile`, `CalibrationStore`, `CameraFormatSelector`, `Homography`, `ThermalPolicy`, `DriftDetector`.
