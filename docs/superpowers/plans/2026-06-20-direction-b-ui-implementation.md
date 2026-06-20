# Direction B "Instrument · Daylight" — UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Plan each sub-plan (5–8) to full bite-sized detail via the plan flow when you pick it up** — this document is the queued roadmap + per-task contract; expand each task's exact SwiftUI against the matching screenshot at execution time.

**Goal:** Implement the full Direction B "Instrument · Daylight" UI over the existing functional skeleton — design system, menus, restyled camera, and the 4-step calibration wizard — pixel-faithful to the handoff and bound to the existing repo APIs.

**Architecture:** Five sequenced plans. **Plan 5** builds a reusable SwiftUI design system (tokens + type + instrument atoms) that every screen consumes. **Plans 6–8** rebuild the screens on top of it (menus, camera/live, calibration wizard). The two already-queued engine plans (**3.5 auto-detect**, **4 drift guard**) then fill the wizard's auto-detect step and add the runtime drift overlay. Testable logic lives in `PickleVisionCore` (TDD); SwiftUI views are verified by clean build + on-device visual diff against `docs/design/screenshots/`.

**Tech Stack:** Swift 5 / SwiftUI, `PickleVisionCore` Swift package, AVFoundation, Xcode MCP (`xcode`, tab `windowtab1`) + `xcodebuild`, `swift test`.

## Global Constraints

Copied verbatim from `docs/superpowers/specs/2026-06-19-ui-design-direction-b-instrument-daylight.md` + `docs/design/handoff-instrument-daylight.md`. Every task implicitly includes these.

- **Canonical references:** tokens/layout/copy = `docs/design/handoff-instrument-daylight.md`; visuals = `docs/design/screenshots/01..10`. Treat the handoff's exact hex/weights/copy as the spec.
- **Never hard-block on a CV result.** Position checks are guidance; `Continue` is always enabled; "Calibrate manually" is always available; auto-detect failure drops to manual drag. Manual tap is the guaranteed path.
- **Honesty rule.** Never show a computed accuracy number we can't produce. v1 shows IN/OUT, court coords, "N/4 corners set", and a single qualitative **fit-quality from the homography reprojection residual**. Per-zone ±in and detect % are Phase 2 — omit from v1 UI.
- **Bind to existing types — do not invent data models.** `CameraService`, `CalibrationStore`/`StoredCalibration`, `CourtModel`, `CourtProfile`, `CustomDimensions(widthFeet,lengthFeet,nonVolleyZoneFeet)`, `CameraFormatSelector`, `ThermalPolicy`/`ThermalRecommendation(shouldWarn,frameRateCap,message)`, `DriftDetector`/`DriftState`. (Handoff's "StabilityCheck" does not exist — use `DriftDetector`.)
- **Per-screen orientation:** menus portrait, camera + all calibration steps landscape (already wired via `OrientationSupport.lockOrientation`).
- **On-device only** — no login/account/cloud. **Target: iPhone 16 Pro.** No 4K·240 (main lens: 4K≤120, 1080p≤240); `ThermalPolicy` overrides the cap.
- **Fonts:** ship **SF Pro Display / SF Pro Text / SF Mono** (custom faces optional, off critical path).
- **Court overlay is vector** — `Path`/`Shape`/`Canvas`, never raster. Icons = SF Symbols.
- **Process:** logic = TDD; views = clean build (0 warnings) + visual check. **Commit + push to `main` after each task.**

## Verification model (per task)

- **`PickleVisionCore` logic task** → write failing XCTest → `swift test --package-path PickleVisionCore` (fails) → implement → test passes → commit.
- **App view task** → write/modify view → **BuildProject** (tab `windowtab1`) or `xcodebuild -project PickleVision/PickleVision.xcodeproj -scheme PickleVision -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO` → **0 errors, 0 warnings** (confirm via GetBuildLog) → note the matching `docs/design/screenshots/NN-*.png` for the USER's on-device visual gate → commit.
- Each plan ends with a whole-branch review + a USER device-visual pass before the next plan starts.

---

## Decomposition (queue order)

| Plan | Scope | Depends on | New core logic (TDD) |
|---|---|---|---|
| **5 · Design System** | tokens, type, instrument atoms, CourtOverlay Shape | — | none (pure SwiftUI kit) |
| **6 · Menus** | Home (+empty), Settings, History, express re-cal nav | 5 | `CaptureProfile` pref + persistence |
| **7 · Camera/Live** | full-bleed restyle, edge chrome, placeholders, permission state | 5 | none |
| **8 · Calibration wizard** | 4-step flow, fit-quality, custom dims, 0.5× fallback, auto-detect UI shell | 5 | `FitQuality`, `CalibrationFlow` state machine |
| **3.5 · Auto-detect engine** *(already queued)* | real court detection → fills Plan 8 Step 2 | 8 | court keypoint/line detection |
| **4 · Drift guard** *(already queued)* | `DriftDetector` runtime wiring + drift overlay UI | 5, 7 | drift runtime trigger |

Plans 5→8 are the UI build; 3.5 and 4 complete two screens whose engines don't exist yet. **5 must land first** (everything imports it). 6 and 7 are independent of each other (parallelizable). 8 is the largest and should follow 5.

---

## Plan 5 — Design System foundation

**Goal:** A reusable SwiftUI kit (color/type tokens + instrument atoms + the court-overlay shape) so every later screen is assembled from named components at the exact handoff tokens — no ad-hoc styling downstream.

**File Structure:**
- Create `PickleVision/PickleVision/DesignSystem/Theme.swift` — `enum PVColor` (semantic `Color` tokens at exact hexes) + `enum PVFont` (SF Pro/SF Mono text styles + sizes).
- Create `PickleVision/PickleVision/DesignSystem/Components.swift` — `InstrumentPill`, `StatusReadout`, `ChipToggle`/`SegmentedChips`, `PVCard`, `PrimaryButton`, `SecondaryButton`, `DashedPlaceholder`.
- Modify `PickleVision/PickleVision/CourtOverlayView.swift` → extract a reusable `CourtOverlayShape`/view drawing zones (blue in-bounds fill, green apron, optic-yellow lines) usable on both the live screen and calibration.
- (No new tests — pure view kit; verified by build + a SwiftUI `#Preview` per component.)

**Tasks (each: build clean 0 warnings + commit):**
- **5.1 Color tokens** — `PVColor` with every token from handoff §Design Tokens (paper `#f4f5f3`, ink `#14181b`, in `#4d9bff`, out `#46c46a`, optic `#e6f53a`, amber `#f4b53a`, red `#e5402a`, feed gradient, panel/rail/border set, dark text set). Deliverable: named `Color`s resolve; a preview swatch sheet builds.
- **5.2 Typography** — `PVFont` roles (`.display`, `.title`, `.body`, `.data`/mono) using SF Pro Display/Text + SF Mono, with the handoff size scale (44/28/20–28/13–14/9–11) and mono letter-spacing. Deliverable: a type-specimen preview builds.
- **5.3 Instrument atoms** — `InstrumentPill` (dark pill `rgba(8,14,17,0.82)`), `StatusReadout` (mono), `PrimaryButton` (optic-yellow + ink), `SecondaryButton`, `ChipToggle`/`SegmentedChips` (active = optic-yellow), `PVCard` (light + dark variants), `DashedPlaceholder` (Phase-tag placeholder). Deliverable: a gallery preview of all atoms at handoff radii/padding.
- **5.4 CourtOverlay refactor** — generalize `CourtOverlayView` into a zone-colored overlay (blue in-bounds fill, green apron, optic-yellow lines + NVZ/net), driven by a `CourtModel` + `AspectFillMapper`; keep the existing calibration call-site working. Deliverable: existing calibration overlay renders via the refactor; build green.

**Gate:** build 0 warnings; previews render each component; whole-plan review.

---

## Plan 6 — Menus: Home + Settings + History (portrait, light)

**Goal:** The three light menu screens, bound to `CalibrationStore`, with a persisted capture-profile setting and express re-calibrate nav.

**File Structure:**
- Create `PickleVisionCore/.../CaptureProfile.swift` — `enum CaptureProfile { case auto, uhd120, fhd240, fhd120, batterySaver }` mapping to `CameraFormatSelector(targetHeight:maxFrameRate:)` params + `var isRecommended/isDefault`. **TDD.**
- Create `PickleVision/PickleVision/Settings/CaptureProfileStore.swift` — `UserDefaults`-backed persistence of the selected `CaptureProfile`.
- Rewrite `PickleVision/PickleVision/HomeView.swift` — "Ready to ref." populated + "First court." empty state; saved-courts list; settings gear; footer.
- Create `PickleVision/PickleVision/SavedCourtCard.swift` — mini court thumbnail (uses 5.4 overlay) + venue · `<layout> · W×L ft · <relative date>` + ↻ reload.
- Create `PickleVision/PickleVision/Settings/SettingsView.swift` — capture-profile single-select (5.3 chips/rows) + manage-saved-courts (Delete) + footer.
- Create `PickleVision/PickleVision/History/HistoryView.swift` — "Sessions" + PHASE 6 placeholder (ghosted rows, dashed future note).
- Modify nav: gear → Settings; `Start a session` / `Set up your first court` → camera; saved-court ↻ → calibration **Step 3 (Fine-tune)** preloaded with that `StoredCalibration` (express re-cal).

**Tasks:**
- **6.1** `CaptureProfile` enum + `CameraFormatSelector` mapping — **TDD** (`CaptureProfileTests`: each case → expected targetHeight/maxFrameRate; `.fhd240` exists, **no uhd240**; recommended=`.uhd120`, default=`.fhd120`). Commit.
- **6.2** `CaptureProfileStore` (UserDefaults get/set, default `.auto`) — **TDD** with an injected `UserDefaults(suiteName:)`. Commit.
- **6.3** `SavedCourtCard` view (load list via `CalibrationStore`; thumbnail from corners). Build + screenshot `01-home`. Commit.
- **6.4** `HomeView` populated state (header, hero, primary button, saved list, footer). Build + `01-home`. Commit.
- **6.5** `HomeView` empty state ("First court." / "No saved courts yet"). Build + `02-home-empty`. Commit.
- **6.6** `SettingsView` (profile select bound to store + manage/delete courts). Build + `03-settings`. Commit.
- **6.7** `HistoryView` placeholder. Build (no dedicated screenshot — structure-only). Commit.
- **6.8** Wire nav (gear → Settings, express re-cal ↻ → Fine-tune) + feed selected profile into `CameraService` start. Build + manual nav check. Commit.

**Gate:** build 0 warnings; `swift test` green; whole-plan review; USER device pass on Home/Settings.

---

## Plan 7 — Camera / Live restyle + permission (landscape, dark)

**Goal:** Restyle the existing `CameraScreen` to the full-bleed instrument look with edge-pinned chrome and non-blocking Phase-2/6 placeholders; restyle the permission-denied state.

**File Structure:**
- Modify `PickleVision/PickleVision/CameraScreen.swift` — full-bleed `CameraPreviewView`; top-left REC + format (`selectedFormatDescription`) + fps (`measuredFPS`) pills; top-right thermal pill (when `thermal.shouldWarn`, text `thermal.message`); top-center dashed "IN/OUT CALLS · PHASE 2"; bottom-left dashed "6/3 · SCORE · PHASE 6"; bottom-right dashed "SLO-MO REPLAY" + solid Calibrate; faint centered court overlay (5.4). All chrome uses 5.3 atoms and never covers the court.
- Modify the permission-denied subview → Direction-B dark state (camera glyph, copy, `Open Settings`).

**Tasks:**
- **7.1** Edge-pinned HUD cluster (REC/format/fps/thermal pills via 5.3, bound to `CameraService`). Build + `04-camera-live`. Commit.
- **7.2** Non-blocking placeholders (IN/OUT, score, slo-mo) as `DashedPlaceholder`s + styled Calibrate. Build + `04-camera-live`. Commit.
- **7.3** Faint live court overlay (5.4) centered, never under chrome. Build + `04-camera-live`. Commit.
- **7.4** Permission-denied dark restyle. Build + (permission state). Commit.

**Gate:** build 0 warnings; whole-plan review; USER device pass (live screen + revoke-permission path).

---

## Plan 8 — Calibration wizard (landscape, dark)

**Goal:** Restructure the single-screen calibrator into the 4-step `Position → Detect → Fine-tune → Verify` flow with a never-blocking state machine, fit-quality from the homography residual, custom-dimensions entry, and the 0.5× fallback — auto-detect engine stubbed (Plan 3.5 fills it), manual-first throughout.

**File Structure:**
- Create `PickleVisionCore/.../FitQuality.swift` — compute reprojection residual from the 4 image corners vs the recomputed homography, bucket to `.good/.fair` + a 0–4 segment score. **TDD.**
- Create `PickleVisionCore/.../CalibrationFlow.swift` — a pure state machine: `Step (.position/.detect/.finetune/.verify)`, advisory `SetupChecks(steady,framed,angle)` that **never gates** transitions, `AutoDetectState (.idle/.finding/.found/.failed)`, transitions, and the draft (corners, layout, custom dims, overlay toggle, tap point). **TDD.**
- Create `PickleVision/PickleVision/Calibration/CalibrationWizardView.swift` — host: frozen `latestImage` canvas + 204px right rail; switches step views.
- Create step views: `PositionStepView`, `AutoDetectStepView` (idle/finding/found/failed), `FineTuneStepView` (reuse `CalibrationView` drag+loupe, restyled), `VerifyStepView` (tap-test + venue field + fit-quality + Save).
- Create `CustomDimensionsSheet` (Width/Length/Kitchen → `CustomDimensions`) and `UltraWideFallbackCard` (0.5× switch).
- Modify `CalibrationScreen.swift` → host the wizard (keep `freeze()`/session reuse); retire the single-screen layout.

**Tasks:**
- **8.1** `FitQuality` from residual — **TDD** (perfect corners → `.good`/4; skewed → lower bucket). Commit.
- **8.2** `CalibrationFlow` state machine — **TDD** (checks never gate `Continue`; auto-detect `failed` → manual path reachable; step order). Commit.
- **8.3** `CalibrationWizardView` shell (canvas + rail + step switch). Build. Commit.
- **8.4** Step 1 `PositionStepView` (guidance HUD, `Continue anyway` always enabled, `Calibrate manually`, "Won't fit? 0.5×"). Build + `06-calibrate-position`. Commit.
- **8.5** Step 2 `AutoDetectStepView` — idle/found(no %)/finding/failed states + layout chips; engine **stub** returns `.failed`→manual or a confirm path. Build + `07-calibrate-autodetect`, `10-autodetect-failed`. Commit.
- **8.6** Step 3 `FineTuneStepView` — restyle existing drag+loupe; rail LAYOUT chips, overlay toggle, "4/4 corners set", Re-freeze/Save. Build + `08-calibrate-finetune-loupe`. Commit.
- **8.7** Step 4 `VerifyStepView` — tap-test (`courtPoint(forImage:)`+`isInBounds`, IN/OUT + coords, **no ±in**), venue field, **fit-quality** (8.1), Back/Save → `CalibrationStore.save`. Build + `09-calibrate-taptest-save`. Commit.
- **8.8** `CustomDimensionsSheet` + `UltraWideFallbackCard`. Build. Commit.
- **8.9** Swap `CalibrationScreen` to host the wizard; preserve express-re-cal entry (lands on Step 3). Build + full nav check. Commit.

**Gate:** build 0 warnings; `swift test` green; whole-plan review; USER device pass on the full flow.

---

## Completes-the-UI (already queued, unchanged)

- **Plan 3.5 — Auto-detect engine.** Real court detection (line/keypoint) → replaces the 8.5 stub: populates corners, drives `.finding/.found/.failed`. Honesty rule: v1 shows "Court found" (no %).
- **Plan 4 — Drift guard.** Wire `DriftDetector` to runtime motion/feature drift; add the landscape **drift-guard overlay** (amber CALLS PAUSED banner + "Mount moved — re-aligning" modal, Re-tap court / Dismiss) on the live screen. Screenshot `05-drift-guard`.

---

## Self-review — handoff coverage map

| Handoff screen / state | Screenshot | Plan · task |
|---|---|---|
| Design tokens / type / atoms | (system) | 5.1–5.3 |
| Court overlay (zones) | (system) | 5.4 |
| Home populated | 01 | 6.4 |
| Home empty / first launch | 02 | 6.5 |
| Settings (profile + manage) | 03 | 6.1–6.2, 6.6 |
| History (Phase 6) | (in 02 strip) | 6.7 |
| Camera / Live | 04 | 7.1–7.3 |
| Permission denied | (camera frame) | 7.4 |
| Calibration Step 1 position | 06 | 8.4 |
| Calibration Step 2 auto-detect (+finding) | 07 | 8.5 |
| Auto-detect failed | 10 | 8.5 |
| Fine-tune + loupe | 08 | 8.6 |
| Tap-test + save + fit-quality | 09 | 8.1, 8.7 |
| Custom dims / 0.5× fallback | (edge cases) | 8.8 |
| Drift guard | 05 | Plan 4 |
| Phase-2 numbers (±in, %, distance) | (aspirational) | **omitted from v1 by design** |

**Gaps:** none for v1 scope. Phase-2 numeric layer is intentionally excluded (honesty rule).

## Open decision carried forward

**IN/OUT verdict badge color** (handoff: IN=blue/OUT=green). Non-blocking — it's a Phase-2 element (no IN/OUT calls ship in Plans 5–8). Resolve before Phase 2; see spec §4.
