# Plan 7 — Camera / Live restyle + permission state (landscape, dark)

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Execute one task at a time, in order; each task ends with a **clean 0-warning build + commit + push to `main`**. You have ZERO prior context beyond this document — every fact you need (exact copy, tokens, API signatures, file paths, commands) is inlined below.

---

## Goal

Restyle the existing `CameraScreen` (the live preview screen) into the Direction B "Instrument · Daylight" look: a **full-bleed camera feed** with **edge-pinned instrument chrome** that **never covers the court playing area**, non-blocking **Phase-2 / Phase-6 dashed placeholders**, and a restyled **permission-denied dark state**. All live readouts bind to the **real `CameraService` API** — no fabricated numbers. Landscape is forced; the existing session-reuse behaviour (do **not** stop the session on disappear) is preserved.

This plan covers **only** the Camera/Live screen + the permission-denied state. The **drift guard** (amber `CALLS PAUSED` banner + "Mount moved — re-aligning" modal) is a **separate later plan (Plan 4) — do NOT build it here.**

## Architecture

`CameraScreen.swift` is a single SwiftUI `View` driven by a `@StateObject CameraService`. It branches on `camera.permission` (`.authorized` → preview + HUD; `.denied` → permission state; `.unknown` → spinner). This plan rewrites the `.authorized` HUD into edge-pinned clusters built from **Plan 5 design-system atoms**, rewrites the `.denied` branch into a dark Direction-B state, and lays a faint decorative court overlay behind the chrome. No new data models; no engine logic; views only.

**Layout model for the HUD (landscape):** a `ZStack` over the full-bleed `CameraPreviewView`. Chrome is pinned to the four edges with `VStack { topRow; Spacer(); bottomRow }`, each row an `HStack` with `Spacer()`s so clusters hug the left/center/right edges. The center of the screen (the court trapezoid) is left clear — placeholders sit in the **top-center** and **corners only**, matching `docs/design/screenshots/04-camera-live.png`.

## Tech Stack

- Swift 5 / SwiftUI, target **iPhone 16 Pro**, on-device only (no network/account).
- App target `PickleVision` (files auto-include via synchronized groups — **no `.pbxproj` edits**, just create/modify `.swift` files under `PickleVision/PickleVision/`).
- Binds to `CameraService` (`PickleVision/PickleVision/CameraService.swift`) and `PickleVisionCore`.
- Consumes the **Plan 5 design system** in `PickleVision/PickleVision/DesignSystem/` (see Dependency below).

## Dependency on Plan 5 (READ THIS FIRST)

This plan **consumes** the Plan 5 design system by name. Plan 5 builds `PickleVision/PickleVision/DesignSystem/Theme.swift` (`PVColor`, `PVFont`) + `.../Components.swift` (`InstrumentPill`, `StatusReadout`, `PrimaryButton`, `SecondaryButton`, `DashedPlaceholder`) + a reusable `CourtOverlay`. **Do NOT redefine any of these.**

**Before starting Task 7.1, verify Plan 5 has landed** and read the exact initializers:

```bash
cd "/Users/avosarkissian/Documents/VS Code/Pickle Vision"
ls PickleVision/PickleVision/DesignSystem/
grep -nE "struct (InstrumentPill|StatusReadout|PrimaryButton|SecondaryButton|DashedPlaceholder|CourtOverlay)" PickleVision/PickleVision/DesignSystem/*.swift PickleVision/PickleVision/*.swift
grep -nE "enum PVColor|static (let|var) (optic|amber|recordRed|panel|rail|onDark|feedGradient|ink)" PickleVision/PickleVision/DesignSystem/Theme.swift
```

> **If `DesignSystem/` does not exist, STOP — Plan 5 is a hard prerequisite and must be implemented first.** Every task below assumes these atoms exist.
>
> **The exact initializer signatures for the Plan 5 atoms are authoritative as written in `DesignSystem/Components.swift` — read them and adapt the call-sites in this plan to match.** The call-sites below use the most likely shape (`InstrumentPill(text:)`, `InstrumentPill(text:tint:)`, `DashedPlaceholder(text:)`, `PrimaryButton(title:systemImage:action:)`, `CourtOverlay()`); if Plan 5 named a parameter differently (e.g. `_ text:` positional, or `label:` / `tint:` / `accent:`), use Plan 5's actual names — the **structure and the verbatim copy/token below are the contract**, the parameter labels follow Plan 5.

---

## Global Constraints (every task inherits these — verbatim values)

- **Readouts bind to real `CameraService` symbols only.** Never fabricate live numbers. The exact `@Published` API (from `PickleVision/PickleVision/CameraService.swift`):
  - `permission: CameraService.PermissionState` — `enum PermissionState { case unknown, authorized, denied }`
  - `isRunning: Bool`
  - `selectedFormatDescription: String` — e.g. `"1080p · 120fps"` (already formatted as `"<height>p · <fps>fps"`)
  - `measuredFPS: Int`
  - `thermal: ThermalRecommendation` — `struct ThermalRecommendation { let shouldWarn: Bool; let frameRateCap: Double?; let message: String? }`
  - `latestImage: CGImage?`
  - `imageSize: CGSize`
  - `session: AVCaptureSession`
  - `start()`, `stop()`
- **Never hard-block.** Placeholders are **non-interactive** (`.allowsHitTesting(false)` where appropriate) and never gate anything. Only the live `Calibrate` button and `Open Settings` button are interactive.
- **Honesty rule.** Placeholders are clearly **Phase-tagged** ("PHASE 2", "PHASE 6") and show **no fake live numbers**. The `6 / 3` score and `IN / OUT CALLS` text are static placeholder strings inside dashed boxes, visibly labelled as future phases — not bound to any live source.
- **Exact handoff tokens + copy.** Source of truth: `docs/design/handoff-instrument-daylight.md` §"Screens/Views" 4 (Camera/Live) and the render `docs/design/screenshots/04-camera-live.png`.
  - **REC pill:** red dot (`PVColor.recordRed` `#e5402a`) + text `REC 12:04`.
  - **Format pill:** text from `camera.selectedFormatDescription`.
  - **fps pill:** text `"\(camera.measuredFPS) fps"`.
  - **Thermal pill (top-right, amber `PVColor.amber` `#f4b53a`):** shown **only** when `camera.thermal.shouldWarn`; text from `camera.thermal.message` (the screenshot shows `COOLING · 90fps`).
  - **Top-center placeholder:** `IN / OUT CALLS · PHASE 2`.
  - **Bottom-left placeholder:** `6 / 3 · SCORE · PHASE 6`.
  - **Bottom-right placeholder:** `SLO-MO REPLAY`.
  - **Calibrate button:** solid, optic-yellow outline + reticle SF Symbol (`scope`), label `Calibrate`.
  - **Permission-denied:** camera glyph (SF Symbol), title `Camera access is off`, body `Pickle Vision needs the camera to see the court. Everything stays on this device.`, primary button `Open Settings` → `UIApplication.openSettingsURLString`.
- **Tokens:** optic-yellow `#e6f53a`, amber `#f4b53a`, record-red `#e5402a`, panel `#0c1216`/`#101920`/`#17242b`, pill bg `rgba(8,14,17,0.82)`, text-on-dark `#eaf6f9`/`#dbe8ff`, feed gradient `linear-gradient(176deg,#13343a,#0e2228,#0a1418)`. Use the **named `PVColor` tokens**, never raw hex literals in this plan's code.
- **SF Pro / SF Mono fonts** (via `PVFont`). **SF Symbols** for icons (`scope`, camera glyph). **iPhone 16 Pro**, on-device only. **Overlays never cover the playing area.**
- **Landscape forced** via the existing `.lockOrientation(.landscape)` (do not remove). **Do NOT stop the session on disappear** — keep the existing `.onAppear { camera.start() }` and the no-`stop()` behaviour so pushing `CalibrationScreen` reuses the live session.
- **Process:** views only (no unit tests). Each task = clean **0-warning** build + commit + push. Build command (require `BUILD SUCCEEDED` + **0 warnings**):

  ```bash
  cd "/Users/avosarkissian/Documents/VS Code/Pickle Vision" && \
  xcodebuild -project "PickleVision/PickleVision.xcodeproj" -scheme PickleVision \
    -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
  ```

  After build, the USER does the on-device visual gate against `docs/design/screenshots/04-camera-live.png` (live) / the permission frame at the right edge of that screenshot.

---

## File Structure

- **Modify** `PickleVision/PickleVision/CameraScreen.swift` — the only file this plan changes. Rewrite the `.authorized` HUD into edge-pinned clusters (REC/format/fps/thermal pills, placeholders, Calibrate) over a full-bleed feed with a faint court overlay; rewrite the `.denied` branch into the Direction-B dark permission state; restyle the `.unknown` spinner onto the dark feed background.
- **Consume (do not modify):** `DesignSystem/Theme.swift`, `DesignSystem/Components.swift` (Plan 5), `CameraService.swift`, `CameraPreviewView.swift`, `OrientationSupport.swift`, `CalibrationScreen.swift`.

**The current `CameraScreen.swift` (baseline you are replacing):** it already has the `switch camera.permission` branch, `.lockOrientation(.landscape)`, `.onAppear { camera.start() }` with no `stop()` on disappear, a `hud` with a `NavigationLink { CalibrationScreen(camera: camera) }`, a `permissionDenied` subview, and a private `pill(_:warning:)` helper. You will replace `hud`, `permissionDenied`, and remove the ad-hoc `pill(_:warning:)` helper (superseded by `InstrumentPill`).

**`CalibrationScreen` initializer (confirmed):** `CalibrationScreen(camera: CameraService)` — pass the same `camera` instance so the session is reused. Keep the `NavigationLink { CalibrationScreen(camera: camera) }` destination.

---

## Tasks

### Task 7.1 — Edge-pinned instrument HUD (REC / format / fps / thermal pills)

Replace the ad-hoc `hud` top cluster with edge-pinned Plan-5 `InstrumentPill`s bound to `CameraService`. Top-left cluster = REC + format + fps; top-right = thermal (conditional). Remove the old `pill(_:warning:)` helper.

**Files**
- Modify `PickleVision/PickleVision/CameraScreen.swift`

**Interfaces consumed (exact)**
- `CameraService.selectedFormatDescription: String`, `.measuredFPS: Int`, `.thermal: ThermalRecommendation` (`shouldWarn: Bool`, `message: String?`).
- Plan 5: `InstrumentPill(text:)` (neutral dark pill), `InstrumentPill(text:tint:)` (tinted variant for thermal amber), `PVColor.recordRed`, `PVColor.amber`. *(If Plan 5 exposes the record dot differently — e.g. a dedicated `RECPill` or an `InstrumentPill(text:dotColor:)` — use that; otherwise compose the REC pill as a small `Circle().fill(PVColor.recordRed)` + text inside `InstrumentPill` per the call-site below.)*

**Steps**

1. Read the exact Plan 5 atom signatures (run the Dependency grep above). Note the actual `InstrumentPill` init label(s) and whether a REC/dot variant exists.

2. In `CameraScreen.swift`, replace the entire `private var hud` with a `ZStack`-friendly structure. Add a top-row builder. The top-left cluster:

   ```swift
   // Top-left instrument cluster — REC + live format + live fps.
   private var topLeftCluster: some View {
       HStack(spacing: 8) {
           // REC pill: record-red dot + static timer placeholder copy.
           InstrumentPill {
               HStack(spacing: 6) {
                   Circle().fill(PVColor.recordRed).frame(width: 7, height: 7)
                   Text("REC 12:04").font(PVFont.data)
               }
           }
           InstrumentPill(text: camera.selectedFormatDescription)   // ← live
           InstrumentPill(text: "\(camera.measuredFPS) fps")        // ← live
       }
   }
   ```

   > If Plan 5's `InstrumentPill` has **no** trailing-closure / `@ViewBuilder` content init, build the REC pill from the text init instead: `InstrumentPill(text: "REC 12:04")` and overlay the dot, OR use the Plan-5 `StatusReadout`/dot variant. Match Plan 5's real API — keep the **dot color `PVColor.recordRed` + copy `REC 12:04`** intact.

3. The top-right thermal pill (conditional — honesty + the spec's `shouldWarn` gate):

   ```swift
   // Top-right — amber thermal pill, only when the policy says to warn.
   @ViewBuilder private var thermalCluster: some View {
       if camera.thermal.shouldWarn, let msg = camera.thermal.message {
           InstrumentPill(text: msg, tint: PVColor.amber)   // e.g. "COOLING · 90fps"
       }
   }
   ```

4. Compose the top row, hugging both edges, leaving the center clear (the center placeholder lands in Task 7.2):

   ```swift
   private var topRow: some View {
       HStack(alignment: .top) {
           topLeftCluster
           Spacer(minLength: 12)
           thermalCluster
       }
   }
   ```

5. Update `body`'s `.authorized` case to lay `topRow` over the feed (full bottom row added in 7.2). For this task, a minimal pinned layout:

   ```swift
   case .authorized:
       CameraPreviewView(session: camera.session)
           .ignoresSafeArea()
       VStack {
           topRow
           Spacer()
       }
       .padding(16)
       .ignoresSafeArea(.container, edges: .horizontal)   // hug the long landscape edges
   ```

   Keep the existing `NavigationLink { CalibrationScreen(camera: camera) }` for now (it moves into the bottom row in 7.2) so the build stays green.

6. **Delete** the old `private func pill(_:warning:)` helper — it is superseded by `InstrumentPill`.

7. Build (require **BUILD SUCCEEDED, 0 warnings**):

   ```bash
   cd "/Users/avosarkissian/Documents/VS Code/Pickle Vision" && \
   xcodebuild -project "PickleVision/PickleVision.xcodeproj" -scheme PickleVision \
     -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -25
   ```

   **Expected output:** ends with `** BUILD SUCCEEDED **` and no `warning:` lines. If any `warning:` appears, fix it before committing (unused vars, deprecated APIs).

8. Commit + push:

   ```bash
   cd "/Users/avosarkissian/Documents/VS Code/Pickle Vision" && \
   git add PickleVision/PickleVision/CameraScreen.swift && \
   git commit -m "feat(app): camera HUD — edge-pinned REC/format/fps/thermal pills via design system (P7 T1)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" && \
   git push origin main
   ```

   **Visual gate:** compare top clusters to `docs/design/screenshots/04-camera-live.png` (REC + 1080p·120fps + fps top-left; amber COOLING·90fps top-right).

---

### Task 7.2 — Non-blocking placeholders + styled Calibrate button (bottom + top-center chrome)

Add the dashed Phase placeholders (top-center IN/OUT, bottom-left score, bottom-right slo-mo) and the solid optic-yellow Calibrate button, all edge-pinned and clear of the court.

**Files**
- Modify `PickleVision/PickleVision/CameraScreen.swift`

**Interfaces consumed (exact)**
- Plan 5: `DashedPlaceholder(text:)` (dashed optic-yellow-outlined box with Phase-tagged copy), `PrimaryButton(title:systemImage:action:)` **or** a `NavigationLink`-wrappable primary style. *(If Plan 5's `PrimaryButton` only takes an `action:` closure, wrap the navigation as below; if it offers a `label`/destination form, prefer that. Keep it a `NavigationLink` to `CalibrationScreen(camera:)`.)*
- `CalibrationScreen(camera: CameraService)`.

**Steps**

1. Add the top-center placeholder into `topRow` between the left cluster and the thermal cluster — it must sit **above** the court trapezoid (top edge), not over it:

   ```swift
   private var topRow: some View {
       HStack(alignment: .top) {
           topLeftCluster
           Spacer(minLength: 12)
           DashedPlaceholder(text: "IN / OUT CALLS · PHASE 2")   // non-interactive, Phase-tagged
               .allowsHitTesting(false)
           Spacer(minLength: 12)
           thermalCluster
       }
   }
   ```

2. Add the bottom row: score placeholder (bottom-left), slo-mo placeholder + Calibrate button (bottom-right). The Calibrate button is a `NavigationLink` so it pushes `CalibrationScreen`:

   ```swift
   private var bottomRow: some View {
       HStack(alignment: .bottom) {
           DashedPlaceholder(text: "6 / 3 · SCORE · PHASE 6")
               .allowsHitTesting(false)
           Spacer()
           HStack(spacing: 10) {
               DashedPlaceholder(text: "SLO-MO REPLAY")
                   .allowsHitTesting(false)
               NavigationLink {
                   CalibrationScreen(camera: camera)
               } label: {
                   Label("Calibrate", systemImage: "scope")
               }
               .buttonStyle(PrimaryButtonStyle())   // ← Plan 5 optic-yellow primary style
           }
       }
   }
   ```

   > Use **Plan 5's actual primary affordance.** If Plan 5 ships `PrimaryButton(title:systemImage:action:)` (a tappable view, not a style), build the Calibrate as a programmatic push instead: add `@State private var goCalibrate = false`, a hidden `NavigationLink(isActive:)`/`.navigationDestination(isPresented:)`, and `PrimaryButton(title: "Calibrate", systemImage: "scope") { goCalibrate = true }`. The **contract** is: solid optic-yellow button, reticle `scope` symbol, label `Calibrate`, pushes `CalibrationScreen(camera: camera)`.

3. Wire both rows into the `.authorized` case, pinning bottom chrome to the bottom edge and keeping the center clear:

   ```swift
   case .authorized:
       CameraPreviewView(session: camera.session)
           .ignoresSafeArea()
       VStack {
           topRow
           Spacer()
           bottomRow
       }
       .padding(16)
   ```

4. Remove the now-unused old `hud` body remnants (the old `NavigationLink` + `Spacer` stack) if any remain — there must be exactly one Calibrate affordance.

5. Build (**BUILD SUCCEEDED, 0 warnings**):

   ```bash
   cd "/Users/avosarkissian/Documents/VS Code/Pickle Vision" && \
   xcodebuild -project "PickleVision/PickleVision.xcodeproj" -scheme PickleVision \
     -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -25
   ```

   **Expected:** `** BUILD SUCCEEDED **`, no `warning:` lines.

6. Commit + push:

   ```bash
   cd "/Users/avosarkissian/Documents/VS Code/Pickle Vision" && \
   git add PickleVision/PickleVision/CameraScreen.swift && \
   git commit -m "feat(app): camera placeholders + Calibrate — dashed Phase-2/6 chrome, optic Calibrate button (P7 T2)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" && \
   git push origin main
   ```

   **Visual gate:** `docs/design/screenshots/04-camera-live.png` — top-center IN/OUT CALLS·PHASE 2, bottom-left 6/3·SCORE·PHASE 6, bottom-right SLO-MO REPLAY + yellow Calibrate.

---

### Task 7.3 — Faint centered court overlay (behind the chrome, never under it)

Lay a faint decorative court trapezoid centered on the feed, so the screen reads as the live referee instrument. It sits **behind** the chrome and is **non-interactive**.

**Files**
- Modify `PickleVision/PickleVision/CameraScreen.swift`

**Interfaces consumed (exact)**
- Plan 5: `CourtOverlay` — the reusable zone overlay. **Resolved ambiguity (see Conflicts):** on the live screen there is **no calibrated `CourtModel`** yet (calibration hasn't run), so do **not** fabricate a live map. Use Plan 5's **non-data-bound / preview form** of `CourtOverlay` (a faint static trapezoid guide) if it exists; otherwise pass a default/identity court guide. The overlay here is **decorative guidance, faint**, not a live calibrated map — consistent with the honesty rule. The screenshot shows exactly this: a faint optic-yellow trapezoid with NVZ + net lines, not tied to any saved court.

**Steps**

1. Check what `CourtOverlay` requires:

   ```bash
   cd "/Users/avosarkissian/Documents/VS Code/Pickle Vision" && \
   grep -nE "struct CourtOverlay|init\(|var body" PickleVision/PickleVision/DesignSystem/*.swift PickleVision/PickleVision/CourtOverlayView.swift
   ```

   - If `CourtOverlay()` (no args) renders a default faint trapezoid → use it directly.
   - If it **requires** a `CourtModel`/`imageSize` (data-bound only), build a faint static trapezoid inline using a `Path` with `PVColor.optic.opacity(...)` strokes (do **not** invent a `CourtModel`). Keep it `.allowsHitTesting(false)`.

2. Insert the overlay **between** the `CameraPreviewView` and the chrome `VStack` in the `.authorized` case, faint and centered, clear of the corners:

   ```swift
   case .authorized:
       CameraPreviewView(session: camera.session)
           .ignoresSafeArea()
       CourtOverlay()                          // ← Plan 5 faint static guide
           .opacity(0.7)
           .padding(.horizontal, 80)           // keep the trapezoid off the corner chrome
           .padding(.vertical, 40)
           .allowsHitTesting(false)
           .ignoresSafeArea()
       VStack {
           topRow
           Spacer()
           bottomRow
       }
       .padding(16)
   ```

   > Padding keeps the court area clear of the edge clusters per the invariant "overlays never cover the playing area" — chrome on the edges, court in the middle, neither overlapping. Tune the padding so the trapezoid matches the centered placement in `04-camera-live.png`.

3. Confirm the overlay is **behind** the chrome (the chrome `VStack` is last in the `ZStack` children, so it renders on top — correct).

4. Build (**BUILD SUCCEEDED, 0 warnings**):

   ```bash
   cd "/Users/avosarkissian/Documents/VS Code/Pickle Vision" && \
   xcodebuild -project "PickleVision/PickleVision.xcodeproj" -scheme PickleVision \
     -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -25
   ```

   **Expected:** `** BUILD SUCCEEDED **`, no `warning:` lines.

5. Commit + push:

   ```bash
   cd "/Users/avosarkissian/Documents/VS Code/Pickle Vision" && \
   git add PickleVision/PickleVision/CameraScreen.swift && \
   git commit -m "feat(app): camera court overlay — faint centered trapezoid guide, behind chrome (P7 T3)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" && \
   git push origin main
   ```

   **Visual gate:** `docs/design/screenshots/04-camera-live.png` — faint yellow trapezoid centered, court area clear of all pills/placeholders.

---

### Task 7.4 — Permission-denied dark state (Direction B) + dark `.unknown` spinner

Rewrite the `.denied` branch into the Direction-B dark state, and put the `.unknown` spinner on the dark feed background so all three permission states share the dark instrument look.

**Files**
- Modify `PickleVision/PickleVision/CameraScreen.swift`

**Interfaces consumed (exact)**
- `CameraService.permission` (`.denied`, `.unknown`).
- Plan 5: `PVColor` (`feedGradient`/`panel`, `onDark` text), `PVFont` (`.title`, `.body`), `PrimaryButton(title:action:)`.
- `UIApplication.openSettingsURLString`, `UIApplication.shared.open(_:)`.

**Steps**

1. Replace `private var permissionDenied` with the Direction-B dark state. Exact copy is mandatory:

   ```swift
   private var permissionDenied: some View {
       ZStack {
           PVColor.feedGradient.ignoresSafeArea()   // dark feed-stand-in background
           VStack(spacing: 16) {
               Image(systemName: "camera.metering.unknown")
                   .font(.system(size: 44, weight: .regular))
                   .foregroundStyle(PVColor.optic)
               Text("Camera access is off")
                   .font(PVFont.title)
                   .foregroundStyle(PVColor.onDark)
               Text("Pickle Vision needs the camera to see the court. Everything stays on this device.")
                   .font(PVFont.body)
                   .foregroundStyle(PVColor.onDark.opacity(0.7))
                   .multilineTextAlignment(.center)
                   .frame(maxWidth: 420)
               PrimaryButton(title: "Open Settings") {
                   if let url = URL(string: UIApplication.openSettingsURLString) {
                       UIApplication.shared.open(url)
                   }
               }
           }
           .padding(24)
       }
   }
   ```

   > Use Plan 5's real token names (e.g. if the near-white dark text token is `PVColor.onDark` vs `PVColor.textOnDark`, and the title/body font roles are `.title`/`.body` vs `.h2`/`.bodyText`) — match `DesignSystem/`. Keep the **glyph, the two strings verbatim, and the `Open Settings` → `openSettingsURLString`** behaviour exactly. The glyph SF Symbol may be `camera.metering.unknown` (current) or a plain `camera.fill`/`video.slash` — keep a camera glyph.

2. Update the `.unknown` case to the dark background instead of plain black:

   ```swift
   case .unknown:
       PVColor.feedGradient.ignoresSafeArea()
       ProgressView().tint(PVColor.optic)
   ```

3. Confirm `.lockOrientation(.landscape)`, `.onAppear { camera.start() }`, and the **absence of any `stop()` on disappear** are all still present and unchanged (session reuse invariant).

4. Build (**BUILD SUCCEEDED, 0 warnings**):

   ```bash
   cd "/Users/avosarkissian/Documents/VS Code/Pickle Vision" && \
   xcodebuild -project "PickleVision/PickleVision.xcodeproj" -scheme PickleVision \
     -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -25
   ```

   **Expected:** `** BUILD SUCCEEDED **`, no `warning:` lines.

5. Commit + push:

   ```bash
   cd "/Users/avosarkissian/Documents/VS Code/Pickle Vision" && \
   git add PickleVision/PickleVision/CameraScreen.swift && \
   git commit -m "feat(app): camera permission-denied dark state + dark loading spinner (P7 T4)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" && \
   git push origin main
   ```

   **Visual gate:** the permission frame at the right edge of `docs/design/screenshots/04-camera-live.png` (and the dark `Camera access is off` / `Open Settings` state). Revoke camera permission on device to view it.

---

## Self-review — handoff coverage map

Every Camera/Live element from `handoff-instrument-daylight.md` §"Screens/Views" 4 + `docs/design/screenshots/04-camera-live.png` maps to a task here:

| Handoff element (Camera/Live + permission) | Exact copy / token | Bound to | Task |
|---|---|---|---|
| Full-bleed feed | `CameraPreviewView(session:)`, `.ignoresSafeArea()` | `camera.session` | 7.1 (laid) |
| REC pill | `REC 12:04` + record-red dot | `PVColor.recordRed` (static timer copy) | 7.1 |
| Format pill | live `1080p · 120fps` | `camera.selectedFormatDescription` | 7.1 |
| fps pill | live `118 fps` form | `camera.measuredFPS` | 7.1 |
| Thermal pill (top-right, amber, conditional) | `COOLING · 90fps` | `camera.thermal.shouldWarn` + `.message`, `PVColor.amber` | 7.1 |
| Top-center placeholder (dashed, non-blocking) | `IN / OUT CALLS · PHASE 2` | static, `DashedPlaceholder` | 7.2 |
| Bottom-left placeholder (dashed) | `6 / 3 · SCORE · PHASE 6` | static, `DashedPlaceholder` | 7.2 |
| Bottom-right placeholder (dashed) | `SLO-MO REPLAY` | static, `DashedPlaceholder` | 7.2 |
| Calibrate button (solid, optic outline, reticle) | `Calibrate` + `scope` symbol | pushes `CalibrationScreen(camera:)` | 7.2 |
| Faint centered court overlay (clear of chrome) | optic-yellow trapezoid | `CourtOverlay` (faint static guide) | 7.3 |
| Permission-denied dark state | `Camera access is off` / `Pickle Vision needs the camera to see the court. Everything stays on this device.` / `Open Settings` | `UIApplication.openSettingsURLString` | 7.4 |
| Dark loading state | spinner on feed gradient | `permission == .unknown` | 7.4 |
| Landscape forced | `.lockOrientation(.landscape)` | unchanged | all (preserved) |
| Session reuse (no stop on disappear) | `.onAppear { camera.start() }`, no `stop()` | unchanged | all (preserved) |
| **Drift guard (CALLS PAUSED / Mount moved)** | — | — | **NOT in this plan (Plan 4)** |

**Out of scope by design (do not build here):** drift-guard banner/modal (Plan 4), any live IN/OUT calls or real score/replay (Phase 2 / Phase 6), the Phase-2 numeric layer (±in, %, distance). All chrome here is either a real `CameraService` readout or a clearly Phase-tagged static placeholder — honesty rule satisfied.
