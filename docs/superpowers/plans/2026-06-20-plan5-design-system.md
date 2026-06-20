# Plan 5 — Design System foundation ("Instrument · Daylight")

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. This document is fully self-contained — every task shows the exact Swift to write, the exact build command, the expected output, a `#Preview`, and a commit. There is no "TBD" and nothing to design at execution time; implement the code shown verbatim.

**Goal:** Build the reusable SwiftUI design-system kit — color tokens, type roles, instrument atoms, and a zone-colored court overlay — that every later screen (Plans 6/7/8) imports by name. After this plan, no downstream screen invents ad-hoc styling: it composes named components at the exact handoff tokens.

**Architecture:** Three new files under `PickleVision/PickleVision/DesignSystem/` (`Theme.swift` for `PVColor`/`PVFont`, `Components.swift` for the atoms, `CourtOverlay.swift` for the reusable overlay) plus a refactor of the existing `PickleVision/PickleVision/CourtOverlayView.swift` into a thin compatibility wrapper that delegates to the new `CourtOverlay`. Xcode 16 synchronized groups auto-include any new `.swift` file under the `PickleVision/PickleVision/` tree — **no `.pbxproj` edits are needed**. This is a pure SwiftUI kit: there is **no unit-test work**; each task is verified by a clean 0-warning build plus a SwiftUI `#Preview` that renders the component.

**Tech Stack:** Swift 5 / SwiftUI. App target `PickleVision`, project at `PickleVision/PickleVision.xcodeproj`. iOS deployment target 26.5 (all modern SwiftUI APIs available, incl. `Color(red:green:blue:)`, `#Preview`, `Gradient`, `.fontDesign(.monospaced)`). Core package `PickleVisionCore` (already built) provides `CourtModel`, `CourtProfile`, `AspectFillMapper`, `Homography`. Target device: iPhone 16 Pro. On-device only.

---

## Global Constraints

Every task inherits these. Token values are copied **verbatim** from `docs/design/handoff-instrument-daylight.md` §"Design Tokens" — treat them as the spec.

**Color — exact hex (handoff §Color):**
- Overlay / accent (**optic yellow**) `#e6f53a` — everything the app draws: computed court lines, corner handles, keypoints, loupe ring, HUD highlights, brand reticle, primary buttons / active chips (with ink text), toggles.
- In-bounds blue: `#4d9bff` (call/text), `#2f63c2` (swatch), `rgba(61,134,245,0.06–0.16)` (surface fill tint).
- Out-of-bounds green `#46c46a` — the OUT call; out-of-bounds apron.
- Caution amber `#f4b53a` (also `#e08a16`).
- Error / record red `#e5402a` — REC dot, destructive Delete.
- Ink (text on light + on accent) `#14181b`.
- Paper (light bg) `#f4f5f3`. White cards `#ffffff`, hairline `#e8ebe9` / `#e2e6e6`.
- Light muted text `#5e6a70`, `#7a848a`, `#8a949a`, `#9aa3a8`.
- Feed (dark video) gradient `linear-gradient(176deg,#13343a,#0e2228,#0a1418)`.
- Dark panel / chrome: panel `#0c1216` / `#101920` / `#17242b`; rail bg `#101920`; borders `#1e2a31` / `#25333a` / `#2a3a42`; pills `rgba(8,14,17,0.82)`.
- Light text on dark: `#eaf6f9` (near-white), `#dbe8ff` (readout), `#bcd0d8`, `#9fb4bd`, `#9bc3ff`, `#5f8595` (mono labels).

**Type (handoff §Typography):** SF Pro Display (display/titles, bold/heavy, tracking `-0.01em`), SF Pro Text (UI/body), SF Mono (data/labels, uppercase, letter-spacing 0.1–0.18em). Sizes: hero 44, section H2 28, screen title 20–28, body 13–14, data/labels 9–11 (mono). Keep overlay text ≥ ~11 pt. SF Pro / SF Mono are the shipping fonts (custom faces are optional polish, not in this plan).

**Spacing / radius (handoff §Spacing):** card radius 14–18; pill/chip radius 9–18; button radius 11–16; panel padding 14–24; gaps 6–12; card shadow (light) `0 1px 3px rgba(0,0,0,0.08)`.

**Structural rules:** Court overlay is **vector only** — `Path`/`Shape`/`Canvas`, never raster. Icons = **SF Symbols**. Overlay is never blue/green for lines (it must contrast the real blue/green court) — lines are optic-yellow; only the zone *fills* are blue (in-bounds) / green (apron). On-device only; iPhone 16 Pro. Components stay generic enough to serve honesty/never-block/orientation needs of later plans.

**Build (run after every task — require `** BUILD SUCCEEDED **` + 0 warnings):**
```
xcodebuild -project "PickleVision/PickleVision.xcodeproj" -scheme PickleVision -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```
Run it from the repo root `/Users/avosarkissian/Documents/VS Code/Pickle Vision`. To confirm zero warnings, pipe through a count:
```
xcodebuild -project "PickleVision/PickleVision.xcodeproj" -scheme PickleVision -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "warning:|BUILD (SUCCEEDED|FAILED)"
```
Expected output of the grep: exactly `** BUILD SUCCEEDED **` and **no** `warning:` lines.

**Commit (after every task):**
```
git add -A && git commit -m "<task message>" && git push origin main
```

---

## File Structure

```
PickleVision/PickleVision/
├── DesignSystem/
│   ├── Theme.swift          # NEW — enum PVColor (Color tokens) + enum PVFont (SF Pro/SF Mono roles)
│   ├── Components.swift      # NEW — InstrumentPill, StatusReadout, PrimaryButton, SecondaryButton,
│   │                         #       SegmentedChips, PVCard, DashedPlaceholder
│   └── CourtOverlay.swift    # NEW — reusable CourtOverlay (zone-colored, from CourtModel + AspectFillMapper)
└── CourtOverlayView.swift    # MODIFIED — thin wrapper delegating to CourtOverlay (keeps the calibration call-site compiling)
```

Pinned public names produced by this plan (consumed verbatim by Plans 6/7/8):
- `PVColor`: `paper, ink, inBounds, outBounds, optic, amber, recordRed, panel, rail, hairline, onDark, onDarkDim, mutedLight` + `feedGradient`.
- `PVFont`: `display(_:)`, `ui(_:weight:)`, `mono(_:)`.
- Components: `InstrumentPill`, `StatusReadout`, `PrimaryButton`, `SecondaryButton`, `SegmentedChips`, `PVCard`, `DashedPlaceholder`.
- `CourtOverlay`.

---

## Task 5.1 — Color tokens (`PVColor`)

**Files:** create `PickleVision/PickleVision/DesignSystem/Theme.swift`.

**Interfaces:**
- Consumes: SwiftUI `Color`, `LinearGradient`.
- Produces:
  ```swift
  enum PVColor {
      static let paper: Color
      static let ink: Color
      static let inBounds: Color
      static let outBounds: Color
      static let optic: Color
      static let amber: Color
      static let recordRed: Color
      static let panel: Color
      static let rail: Color
      static let hairline: Color
      static let onDark: Color
      static let onDarkDim: Color
      static let mutedLight: Color
      static let feedGradient: LinearGradient
      // helpers
      static func hex(_ value: UInt32, opacity: Double = 1) -> Color
      static let inBoundsFill: Color   // rgba(61,134,245,0.14)
      static let outBoundsFill: Color  // green apron fill
      static let pillFill: Color       // rgba(8,14,17,0.82)
      static let cardBorder: Color     // dark panel border #25333a
      static let inSwatch: Color       // #2f63c2
  }
  ```

**Steps:**

- [ ] **5.1.1** Create the file `PickleVision/PickleVision/DesignSystem/Theme.swift` and write the `PVColor` enum exactly as below. The `hex` helper decodes a 24-bit RGB integer; alpha tints use `opacity:`. Every value is from the handoff token table.
  ```swift
  import SwiftUI

  /// Semantic color tokens for "Instrument · Daylight".
  /// Exact hex values from docs/design/handoff-instrument-daylight.md §Design Tokens.
  enum PVColor {
      /// 24-bit RGB hex → Color (e.g. 0xe6f53a). `opacity` applies an alpha tint.
      static func hex(_ value: UInt32, opacity: Double = 1) -> Color {
          Color(
              red: Double((value >> 16) & 0xff) / 255,
              green: Double((value >> 8) & 0xff) / 255,
              blue: Double(value & 0xff) / 255,
              opacity: opacity
          )
      }

      // Light · menus
      static let paper = hex(0xf4f5f3)        // light bg
      static let ink = hex(0x14181b)          // primary text / text on yellow
      static let hairline = hex(0xe8ebe9)     // card hairline
      static let mutedLight = hex(0x5e6a70)   // secondary text on light

      // Semantic
      static let inBounds = hex(0x4d9bff)     // IN call / in-bounds blue
      static let inSwatch = hex(0x2f63c2)     // blue swatch
      static let outBounds = hex(0x46c46a)    // OUT call / apron green
      static let optic = hex(0xe6f53a)        // computed/active accent (optic yellow)
      static let amber = hex(0xf4b53a)        // caution (thermal / drift / NVZ)
      static let recordRed = hex(0xe5402a)    // REC dot / destructive

      // Dark · video overlay
      static let panel = hex(0x0c1216)        // instrument panel
      static let rail = hex(0x101920)         // control rail bg
      static let cardBorder = hex(0x25333a)   // dark panel border
      static let pillFill = Color(red: 8/255, green: 14/255, blue: 17/255, opacity: 0.82) // rgba(8,14,17,0.82)
      static let onDark = hex(0xeaf6f9)       // near-white text on dark
      static let onDarkDim = hex(0x9fb4bd)    // dim text on dark
      static let monoLabel = hex(0x5f8595)    // mono labels on dark

      // Court zone fills (low-alpha — rgba(61,134,245,0.06–0.16))
      static let inBoundsFill = Color(red: 61/255, green: 134/255, blue: 245/255, opacity: 0.14)
      static let outBoundsFill = Color(red: 70/255, green: 196/255, blue: 106/255, opacity: 0.10)

      /// Live-video stand-in: linear-gradient(176deg,#13343a,#0e2228,#0a1418).
      /// 176° CSS ≈ near-vertical top→bottom; map to SwiftUI top→bottom points.
      static let feedGradient = LinearGradient(
          gradient: Gradient(colors: [hex(0x13343a), hex(0x0e2228), hex(0x0a1418)]),
          startPoint: .top,
          endPoint: .bottom
      )
  }
  ```

- [ ] **5.1.2** Add a swatch-sheet `#Preview` at the bottom of the same file so the build renders every token. Use a small private helper view (kept `fileprivate` so it never leaks into the app namespace).
  ```swift
  #Preview("PVColor swatches") {
      ScrollView {
          VStack(alignment: .leading, spacing: 8) {
              swatch("paper", PVColor.paper)
              swatch("ink", PVColor.ink)
              swatch("inBounds", PVColor.inBounds)
              swatch("inSwatch", PVColor.inSwatch)
              swatch("outBounds", PVColor.outBounds)
              swatch("optic", PVColor.optic)
              swatch("amber", PVColor.amber)
              swatch("recordRed", PVColor.recordRed)
              swatch("panel", PVColor.panel)
              swatch("rail", PVColor.rail)
              swatch("hairline", PVColor.hairline)
              swatch("onDark", PVColor.onDark)
              swatch("onDarkDim", PVColor.onDarkDim)
              swatch("mutedLight", PVColor.mutedLight)
              swatch("inBoundsFill", PVColor.inBoundsFill)
              swatch("outBoundsFill", PVColor.outBoundsFill)
              RoundedRectangle(cornerRadius: 8)
                  .fill(PVColor.feedGradient)
                  .frame(height: 60)
                  .overlay(Text("feedGradient").foregroundStyle(PVColor.onDark).font(.caption))
          }
          .padding()
      }
  }

  @ViewBuilder private func swatch(_ name: String, _ color: Color) -> some View {
      HStack(spacing: 12) {
          RoundedRectangle(cornerRadius: 6).fill(color).frame(width: 56, height: 28)
              .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.gray.opacity(0.3)))
          Text(name).font(.system(.caption, design: .monospaced))
      }
  }
  ```

- [ ] **5.1.3** Build and confirm clean:
  ```
  xcodebuild -project "PickleVision/PickleVision.xcodeproj" -scheme PickleVision -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "warning:|BUILD (SUCCEEDED|FAILED)"
  ```
  Expected: `** BUILD SUCCEEDED **`, no `warning:` lines.

- [ ] **5.1.4** Commit:
  ```
  git add -A && git commit -m "feat(ds): PVColor semantic color tokens at exact handoff hex (Plan 5 T1)" && git push origin main
  ```

---

## Task 5.2 — Typography (`PVFont`)

**Files:** modify `PickleVision/PickleVision/DesignSystem/Theme.swift` (append the `PVFont` enum after `PVColor`).

**Interfaces:**
- Consumes: SwiftUI `Font`.
- Produces:
  ```swift
  enum PVFont {
      static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font
      static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font
      static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font
      // named roles (handoff scale)
      static let hero: Font          // 44 display
      static let h2: Font            // 28 display
      static let screenTitle: Font   // 22 display
      static let body: Font          // 14 ui
      static let bodySmall: Font     // 13 ui
      static let dataLabel: Font     // 10 mono
      static let dataValue: Font     // 13 mono
      // tracking constants for callers (.tracking / .kerning)
      static let displayTracking: CGFloat   // -0.5  (~ -0.01em on a 44pt hero)
      static let labelTracking: CGFloat     //  1.4  (~ 0.14em uppercase mono label)
  }
  ```

**Steps:**

- [ ] **5.2.1** Append the `PVFont` enum to `Theme.swift`. `display`/`ui` use SF Pro (system font; `.default` design renders SF Pro Text, the large weights render SF Pro Display automatically). `mono` uses `.monospaced` design (SF Mono). Tracking is applied by callers via `.tracking(PVFont.displayTracking)` / `.tracking(PVFont.labelTracking)` so the `Font` values stay composable.
  ```swift
  import CoreGraphics

  /// Type roles for "Instrument · Daylight".
  /// SF Pro Display/Text (system, .default design) + SF Mono (.monospaced design).
  /// Sizes from docs/design/handoff-instrument-daylight.md §Typography.
  enum PVFont {
      /// SF Pro Display — titles / hero / scoreboard (bold-heavy, tight tracking).
      static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
          .system(size: size, weight: weight, design: .default)
      }
      /// SF Pro Text — UI / body.
      static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
          .system(size: size, weight: weight, design: .default)
      }
      /// SF Mono — data readouts / labels.
      static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
          .system(size: size, weight: weight, design: .monospaced)
      }

      // Named roles (handoff size scale: hero 44 / H2 28 / screen-title 20–28 / body 13–14 / data-label 9–11)
      static let hero = display(44, weight: .heavy)
      static let h2 = display(28, weight: .bold)
      static let screenTitle = display(22, weight: .bold)
      static let body = ui(14, weight: .regular)
      static let bodySmall = ui(13, weight: .regular)
      static let dataLabel = mono(10, weight: .medium)
      static let dataValue = mono(13, weight: .regular)

      /// Tracking for display titles (handoff: -0.01em → ~-0.5pt at hero size).
      static let displayTracking: CGFloat = -0.5
      /// Letter-spacing for uppercase mono labels (handoff: 0.1–0.18em → ~1.4pt at 10pt).
      static let labelTracking: CGFloat = 1.4
  }
  ```

- [ ] **5.2.2** Add a type-specimen `#Preview` to `Theme.swift`:
  ```swift
  #Preview("PVFont specimen") {
      VStack(alignment: .leading, spacing: 14) {
          Text("Ready to ref.").font(PVFont.hero).tracking(PVFont.displayTracking)
          Text("Section H2").font(PVFont.h2).tracking(PVFont.displayTracking)
          Text("Screen title").font(PVFont.screenTitle)
          Text("Body 14 — the quick brown fox").font(PVFont.body)
          Text("Body small 13").font(PVFont.bodySmall)
          Text("CAPTURE PROFILE")
              .font(PVFont.dataLabel).tracking(PVFont.labelTracking)
              .foregroundStyle(PVColor.mutedLight)
          Text("1080p · 120fps").font(PVFont.dataValue)
      }
      .padding()
  }
  ```

- [ ] **5.2.3** Build + confirm clean (same command as 5.1.3). Expected: `** BUILD SUCCEEDED **`, no warnings.

- [ ] **5.2.4** Commit:
  ```
  git add -A && git commit -m "feat(ds): PVFont SF Pro/SF Mono type roles at handoff size scale (Plan 5 T2)" && git push origin main
  ```

---

## Task 5.3 — Instrument atoms (`InstrumentPill`, `StatusReadout`, `PrimaryButton`, `SecondaryButton`, `SegmentedChips`, `PVCard`, `DashedPlaceholder`)

**Files:** create `PickleVision/PickleVision/DesignSystem/Components.swift`.

**Interfaces:**
- Consumes: `PVColor`, `PVFont` (Task 5.1/5.2).
- Produces (exact public-within-module shapes):
  ```swift
  struct InstrumentPill: View {                    // dark status pill (rgba(8,14,17,0.82))
      init(systemImage: String? = nil, _ text: String, tint: Color = PVColor.onDark)
  }
  struct StatusReadout: View {                      // mono label-over-value (REC \n 12:04)
      init(label: String, value: String, dotColor: Color? = nil)
  }
  struct PrimaryButton: View {                      // optic-yellow + ink text
      init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void)
  }
  struct SecondaryButton: View {                    // outlined dark/neutral
      init(_ title: String, action: @escaping () -> Void)
  }
  struct SegmentedChip: Identifiable { let id; let title; let trailing: String? }
  struct SegmentedChips: View {                     // single-select chip column; active = optic-yellow + ink
      init(_ chips: [SegmentedChip], selection: Binding<SegmentedChip.ID>)
  }
  struct PVCard<Content: View>: View {              // light or dark surface
      init(style: PVCard.Style = .light, @ViewBuilder content: () -> Content)  // .light / .dark
  }
  struct DashedPlaceholder: View {                  // dashed Phase-tag placeholder
      init(_ text: String, tag: String? = nil)
  }
  ```

**Steps:**

- [ ] **5.3.1** Create `PickleVision/PickleVision/DesignSystem/Components.swift` with `InstrumentPill` and `StatusReadout`. `InstrumentPill` is the dark capsule used for `1080p · 120fps`, `COOLING · 90fps`, etc.; `StatusReadout` is the mono two-line readout (label tiny + value) with an optional leading dot (e.g. red REC dot).
  ```swift
  import SwiftUI

  /// Dark status pill — chrome on the camera/calibration screens.
  /// Fill rgba(8,14,17,0.82), hairline border, mono text.
  struct InstrumentPill: View {
      let systemImage: String?
      let text: String
      let tint: Color

      init(systemImage: String? = nil, _ text: String, tint: Color = PVColor.onDark) {
          self.systemImage = systemImage
          self.text = text
          self.tint = tint
      }

      var body: some View {
          HStack(spacing: 6) {
              if let systemImage { Image(systemName: systemImage).font(.system(size: 10, weight: .semibold)) }
              Text(text).font(PVFont.mono(11, weight: .medium)).tracking(0.6)
          }
          .foregroundStyle(tint)
          .padding(.horizontal, 12)
          .padding(.vertical, 7)
          .background(
              Capsule().fill(PVColor.pillFill)
                  .overlay(Capsule().strokeBorder(PVColor.cardBorder.opacity(0.8), lineWidth: 1))
          )
      }
  }

  /// Mono two-line readout (e.g. "REC" over "12:04") with an optional leading dot.
  struct StatusReadout: View {
      let label: String
      let value: String
      let dotColor: Color?

      init(label: String, value: String, dotColor: Color? = nil) {
          self.label = label
          self.value = value
          self.dotColor = dotColor
      }

      var body: some View {
          HStack(spacing: 8) {
              if let dotColor { Circle().fill(dotColor).frame(width: 7, height: 7) }
              VStack(alignment: .leading, spacing: 1) {
                  Text(label).font(PVFont.mono(10, weight: .semibold)).tracking(0.8)
                  Text(value).font(PVFont.mono(11, weight: .regular))
              }
          }
          .foregroundStyle(PVColor.onDark)
          .padding(.horizontal, 12)
          .padding(.vertical, 7)
          .background(
              RoundedRectangle(cornerRadius: 9).fill(PVColor.pillFill)
                  .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(PVColor.cardBorder.opacity(0.8), lineWidth: 1))
          )
      }
  }
  ```

- [ ] **5.3.2** Append `PrimaryButton` and `SecondaryButton`. Primary is the optic-yellow pill with ink text + subtle glow (Home "Start a session →", calibration "Save court"). Secondary is the neutral outlined button ("Calibrate manually", "Re-freeze", "Back").
  ```swift
  /// Optic-yellow primary action with ink text (Home "Start a session →", "Save court").
  struct PrimaryButton: View {
      let title: String
      let systemImage: String?
      let action: () -> Void

      init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
          self.title = title
          self.systemImage = systemImage
          self.action = action
      }

      var body: some View {
          Button(action: action) {
              HStack(spacing: 8) {
                  if let systemImage { Image(systemName: systemImage) }
                  Text(title).font(PVFont.ui(16, weight: .semibold))
              }
              .foregroundStyle(PVColor.ink)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 16)
              .background(RoundedRectangle(cornerRadius: 14).fill(PVColor.optic))
              .shadow(color: PVColor.optic.opacity(0.35), radius: 12, y: 2)
          }
          .buttonStyle(.plain)
      }
  }

  /// Neutral outlined secondary action ("Calibrate manually", "Re-freeze", "Back").
  struct SecondaryButton: View {
      let title: String
      let action: () -> Void

      init(_ title: String, action: @escaping () -> Void) {
          self.title = title
          self.action = action
      }

      var body: some View {
          Button(action: action) {
              Text(title).font(PVFont.ui(15, weight: .medium))
                  .foregroundStyle(PVColor.onDark)
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 14)
                  .background(
                      RoundedRectangle(cornerRadius: 14).fill(PVColor.rail)
                          .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(PVColor.cardBorder, lineWidth: 1))
                  )
          }
          .buttonStyle(.plain)
      }
  }
  ```

- [ ] **5.3.3** Append `SegmentedChip` + `SegmentedChips`. This is the single-select layout column from the Fine-tune rail (Pickleball `20×44` active / Tennis box `27×42` / Custom). Active row = optic-yellow fill + ink text; inactive = dark rail row with dim text. Optional trailing detail (e.g. `20×44`) sits right-aligned.
  ```swift
  /// One option in a SegmentedChips column.
  struct SegmentedChip: Identifiable {
      let id: String
      let title: String
      let trailing: String?

      init(id: String, title: String, trailing: String? = nil) {
          self.id = id
          self.title = title
          self.trailing = trailing
      }
  }

  /// Single-select vertical chip column. Active = optic-yellow + ink (handoff active-chip rule).
  struct SegmentedChips: View {
      let chips: [SegmentedChip]
      @Binding var selection: SegmentedChip.ID

      init(_ chips: [SegmentedChip], selection: Binding<SegmentedChip.ID>) {
          self.chips = chips
          self._selection = selection
      }

      var body: some View {
          VStack(spacing: 8) {
              ForEach(chips) { chip in
                  let active = chip.id == selection
                  Button { selection = chip.id } label: {
                      HStack {
                          Text(chip.title)
                              .font(PVFont.ui(14, weight: active ? .semibold : .regular))
                          Spacer(minLength: 8)
                          if let trailing = chip.trailing {
                              Text(trailing)
                                  .font(PVFont.mono(10, weight: .medium))
                                  .opacity(active ? 0.7 : 0.6)
                          }
                      }
                      .foregroundStyle(active ? PVColor.ink : PVColor.onDarkDim)
                      .padding(.horizontal, 14)
                      .padding(.vertical, 11)
                      .background(
                          RoundedRectangle(cornerRadius: 11)
                              .fill(active ? PVColor.optic : PVColor.rail)
                              .overlay(
                                  RoundedRectangle(cornerRadius: 11)
                                      .strokeBorder(active ? Color.clear : PVColor.cardBorder, lineWidth: 1)
                              )
                      )
                  }
                  .buttonStyle(.plain)
              }
          }
      }
  }
  ```

- [ ] **5.3.4** Append `PVCard` (a styled surface container with `.light` and `.dark` variants). Light = white `#ffffff` with hairline + soft shadow (Settings/Home cards); dark = panel `#0c1216` with dark border (calibration rail blocks). It wraps arbitrary content.
  ```swift
  /// Styled surface container. .light = white card on paper; .dark = instrument panel.
  struct PVCard<Content: View>: View {
      enum Style { case light, dark }
      let style: Style
      let content: Content

      init(style: Style = .light, @ViewBuilder content: () -> Content) {
          self.style = style
          self.content = content()
      }

      var body: some View {
          content
              .padding(16)
              .background(
                  RoundedRectangle(cornerRadius: 16)
                      .fill(style == .light ? Color.white : PVColor.panel)
                      .overlay(
                          RoundedRectangle(cornerRadius: 16)
                              .strokeBorder(style == .light ? PVColor.hairline : PVColor.cardBorder, lineWidth: 1)
                      )
                      .shadow(color: style == .light ? Color.black.opacity(0.08) : .clear, radius: 3, y: 1)
              )
      }
  }
  ```

- [ ] **5.3.5** Append `DashedPlaceholder` (the dashed, ghosted "future" affordance: camera "IN / OUT CALLS · PHASE 2", Home empty "No saved courts yet"). Optional `tag` renders an uppercase mono phase tag under the text.
  ```swift
  /// Dashed, ghosted placeholder for not-yet-shipped affordances (Phase-2/6 tags, empty states).
  struct DashedPlaceholder: View {
      let text: String
      let tag: String?

      init(_ text: String, tag: String? = nil) {
          self.text = text
          self.tag = tag
      }

      var body: some View {
          VStack(spacing: 4) {
              Text(text)
                  .font(PVFont.mono(11, weight: .medium)).tracking(0.6)
                  .multilineTextAlignment(.center)
              if let tag {
                  Text(tag)
                      .font(PVFont.mono(9, weight: .semibold)).tracking(1.2)
                      .opacity(0.7)
              }
          }
          .foregroundStyle(PVColor.onDarkDim)
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .background(
              RoundedRectangle(cornerRadius: 12)
                  .strokeBorder(
                      PVColor.onDarkDim.opacity(0.5),
                      style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                  )
          )
      }
  }
  ```

- [ ] **5.3.6** Add a gallery `#Preview` at the bottom of `Components.swift` rendering every atom over a dark instrument background (so the dark-styled atoms read correctly), with a small light strip for the light `PVCard`.
  ```swift
  #Preview("Atom gallery") {
      ZStack {
          PVColor.feedGradient.ignoresSafeArea()
          ScrollView {
              VStack(spacing: 16) {
                  HStack(spacing: 10) {
                      StatusReadout(label: "REC", value: "12:04", dotColor: PVColor.recordRed)
                      InstrumentPill("1080p · 120fps")
                      InstrumentPill("118 fps")
                      InstrumentPill(systemImage: "thermometer.medium", "COOLING · 90fps", tint: PVColor.amber)
                  }
                  PrimaryButton("Save court", systemImage: "checkmark") {}
                  SecondaryButton("Calibrate manually") {}
                  SegmentedChips(
                      [SegmentedChip(id: "pb", title: "Pickleball", trailing: "20×44"),
                       SegmentedChip(id: "tn", title: "Tennis box", trailing: "27×42"),
                       SegmentedChip(id: "cu", title: "Custom", trailing: "set ft")],
                      selection: .constant("pb")
                  )
                  DashedPlaceholder("IN / OUT CALLS", tag: "PHASE 2")
                  PVCard(style: .light) {
                      VStack(alignment: .leading, spacing: 4) {
                          Text("Riverside · Court 3").font(PVFont.ui(15, weight: .semibold)).foregroundStyle(PVColor.ink)
                          Text("Pickleball · 20×44 ft · 2d ago").font(PVFont.bodySmall).foregroundStyle(PVColor.mutedLight)
                      }
                  }
                  PVCard(style: .dark) {
                      Text("FROZEN FRAME").font(PVFont.dataLabel).tracking(PVFont.labelTracking).foregroundStyle(PVColor.optic)
                  }
              }
              .padding()
          }
      }
  }
  ```

- [ ] **5.3.7** Build + confirm clean (same command as 5.1.3). Expected: `** BUILD SUCCEEDED **`, no warnings.

- [ ] **5.3.8** Commit:
  ```
  git add -A && git commit -m "feat(ds): instrument atoms — pills, buttons, chips, card, placeholder (Plan 5 T3)" && git push origin main
  ```

---

## Task 5.4 — Reusable zone-colored `CourtOverlay` + refactor `CourtOverlayView`

**Files:**
- create `PickleVision/PickleVision/DesignSystem/CourtOverlay.swift`,
- modify `PickleVision/PickleVision/CourtOverlayView.swift` (reduce to a thin wrapper).

**Interfaces:**
- Consumes: `PickleVisionCore.CourtModel`, `PickleVisionCore.AspectFillMapper`, `PVColor`. `CourtModel` exposes `profile.inBoundsPolygon: [CGPoint]`, `profile.netLine: [CGPoint]` (2 pts), `profile.nvzLines: [[CGPoint]]`, and `imagePoint(forCourt:) -> CGPoint?`. `AspectFillMapper(viewSize:contentSize:)` with `view(fromImageNormalized:) -> CGPoint`.
- Produces:
  ```swift
  struct CourtOverlay: View {
      init(model: CourtModel, imageSize: CGSize,
           lineWidth: CGFloat = 2.5, opacity: Double = 1.0, showFills: Bool = true)
  }
  // CourtOverlayView remains, unchanged init: CourtOverlayView(model:imageSize:), now delegates to CourtOverlay.
  ```
  Rendering (handoff zones): in-bounds polygon filled `PVColor.inBoundsFill` (blue, low alpha); the apron — the region between the in-bounds polygon and the view edges — filled `PVColor.outBoundsFill` (green); all lines (outline, NVZ, net) stroked `PVColor.optic`. `opacity` lets the live screen render a *faint* overlay (handoff: "faint yellow court overlay"); calibration uses full opacity. `showFills` lets the live screen draw lines-only if desired. `.allowsHitTesting(false)`.

**Steps:**

- [ ] **5.4.1** Create `PickleVision/PickleVision/DesignSystem/CourtOverlay.swift`. It maps each court point to a view point through the model's inverse homography + the `AspectFillMapper`, then draws: green apron (whole view minus in-bounds hole, even-odd fill), blue in-bounds fill, optic-yellow outline, optic-yellow NVZ lines, and a slightly thicker optic-yellow net line.
  ```swift
  import SwiftUI
  import PickleVisionCore

  /// Reusable zone-colored court overlay.
  /// In-bounds = blue fill (low alpha); apron = green fill; all lines = optic-yellow
  /// (per handoff: the overlay never draws blue/green LINES so it contrasts the real court).
  /// Vector only — Path/Shape, never raster.
  struct CourtOverlay: View {
      let model: CourtModel
      let imageSize: CGSize
      var lineWidth: CGFloat = 2.5
      var opacity: Double = 1.0
      var showFills: Bool = true

      var body: some View {
          GeometryReader { geo in
              let mapper = AspectFillMapper(viewSize: geo.size, contentSize: imageSize)
              let inBounds = inBoundsViewPath(mapper)
              ZStack {
                  if showFills, let inBounds {
                      // Green apron = whole view with the in-bounds polygon punched out (even-odd).
                      apronPath(viewSize: geo.size, inBounds: inBounds)
                          .fill(PVColor.outBoundsFill, style: FillStyle(eoFill: true))
                      // Blue in-bounds fill.
                      inBounds.fill(PVColor.inBoundsFill)
                  }
                  // Optic-yellow outline.
                  if let inBounds {
                      inBounds.stroke(PVColor.optic, lineWidth: lineWidth)
                  }
                  // NVZ (kitchen) lines.
                  ForEach(model.profile.nvzLines.indices, id: \.self) { i in
                      segment(model.profile.nvzLines[i][0], model.profile.nvzLines[i][1], mapper)
                          .stroke(PVColor.optic, lineWidth: max(1, lineWidth - 1))
                  }
                  // Net line (slightly heavier).
                  segment(model.profile.netLine[0], model.profile.netLine[1], mapper)
                      .stroke(PVColor.optic, lineWidth: lineWidth + 0.5)
              }
              .opacity(opacity)
          }
          .allowsHitTesting(false)
      }

      private func toView(_ court: CGPoint, _ mapper: AspectFillMapper) -> CGPoint? {
          guard let n = model.imagePoint(forCourt: court) else { return nil }
          return mapper.view(fromImageNormalized: n)
      }

      private func segment(_ a: CGPoint, _ b: CGPoint, _ mapper: AspectFillMapper) -> Path {
          var p = Path()
          if let va = toView(a, mapper), let vb = toView(b, mapper) {
              p.move(to: va); p.addLine(to: vb)
          }
          return p
      }

      /// Closed in-bounds polygon in view space, or nil if any corner fails to map.
      private func inBoundsViewPath(_ mapper: AspectFillMapper) -> Path? {
          let poly = model.profile.inBoundsPolygon.compactMap { toView($0, mapper) }
          guard poly.count == model.profile.inBoundsPolygon.count, poly.count >= 3 else { return nil }
          var p = Path()
          p.move(to: poly[0]); poly.dropFirst().forEach { p.addLine(to: $0) }; p.closeSubpath()
          return p
      }

      /// View rectangle plus the in-bounds polygon, for an even-odd "hole" fill.
      private func apronPath(viewSize: CGSize, inBounds: Path) -> Path {
          var p = Path(CGRect(origin: .zero, size: viewSize))
          p.addPath(inBounds)
          return p
      }
  }
  ```

- [ ] **5.4.2** Add a `#Preview` to `CourtOverlay.swift` that builds a real `CourtModel` from a regulation-pickleball profile + an identity-ish homography (image corners = the four court corners scaled into a 1280×720 image), so the overlay renders without a camera. This exercises the full mapping path.
  ```swift
  #Preview("CourtOverlay") {
      // Build a CourtModel: map the 4 court corners to 4 image corners → homography.
      let profile = CourtProfile.make(layout: .regulationPickleball)
      let imageSize = CGSize(width: 1280, height: 720)
      let imgCorners = [
          CGPoint(x: 360, y: 200),   // nearLeft
          CGPoint(x: 920, y: 200),   // nearRight
          CGPoint(x: 1120, y: 620),  // farRight
          CGPoint(x: 160, y: 620),   // farLeft
      ]
      // CourtProfile.calibrationCorners order is [nearLeft, nearRight, farRight, farLeft].
      let model: CourtModel? = Homography(source: imgCorners, destination: profile.calibrationCorners)
          .map { CourtModel(profile: profile, homography: $0) }

      return ZStack {
          PVColor.feedGradient.ignoresSafeArea()
          if let model {
              CourtOverlay(model: model, imageSize: imageSize)
          } else {
              Text("homography failed").foregroundStyle(.red)
          }
      }
  }
  ```
  Note: `Homography(source:destination:)` maps source→destination, i.e. image→court, which is exactly what `CourtModel.homography` expects (`courtPoint(forImage:)` = `homography.project`). `imagePoint(forCourt:)` uses its inverse — verified against `CourtModel.swift`.

- [ ] **5.4.3** Refactor `PickleVision/PickleVision/CourtOverlayView.swift` to a thin wrapper that delegates to `CourtOverlay`, preserving the exact init the calibration call-site uses (`CourtOverlayView(model:imageSize:)` at `CalibrationScreen.swift:67`). Replace the entire file body with:
  ```swift
  import SwiftUI
  import PickleVisionCore

  /// Calibration-overlay compatibility wrapper.
  /// Delegates to the reusable zone-colored `CourtOverlay` (DesignSystem/CourtOverlay.swift).
  /// Kept so the existing CalibrationScreen call-site `CourtOverlayView(model:imageSize:)` compiles unchanged.
  struct CourtOverlayView: View {
      let model: CourtModel
      let imageSize: CGSize

      var body: some View {
          CourtOverlay(model: model, imageSize: imageSize)
      }
  }
  ```

- [ ] **5.4.4** Build + confirm clean (same command as 5.1.3). The existing calibration screen must still compile against `CourtOverlayView(model:imageSize:)`. Expected: `** BUILD SUCCEEDED **`, no warnings.

- [ ] **5.4.5** Commit:
  ```
  git add -A && git commit -m "feat(ds): reusable zone-colored CourtOverlay; CourtOverlayView delegates to it (Plan 5 T4)" && git push origin main
  ```

---

## Plan-level self-review checklist

Confirm every pinned public name is produced by a task above (each box is satisfied by the cited task):

- [ ] `PVColor.paper` — 5.1.1
- [ ] `PVColor.ink` — 5.1.1
- [ ] `PVColor.inBounds` — 5.1.1
- [ ] `PVColor.outBounds` — 5.1.1
- [ ] `PVColor.optic` — 5.1.1
- [ ] `PVColor.amber` — 5.1.1
- [ ] `PVColor.recordRed` — 5.1.1
- [ ] `PVColor.panel` — 5.1.1
- [ ] `PVColor.rail` — 5.1.1
- [ ] `PVColor.hairline` — 5.1.1
- [ ] `PVColor.onDark` — 5.1.1
- [ ] `PVColor.onDarkDim` — 5.1.1
- [ ] `PVColor.mutedLight` — 5.1.1
- [ ] `PVColor.feedGradient` (linear-gradient 176°, `#13343a→#0e2228→#0a1418`) — 5.1.1
- [ ] `PVFont.display(_:)` — 5.2.1
- [ ] `PVFont.ui(_:weight:)` — 5.2.1
- [ ] `PVFont.mono(_:)` — 5.2.1 (covers hero 44 / H2 28 / screen-title 22 / body 13–14 / data-label 9–11 via named roles)
- [ ] `InstrumentPill` — 5.3.1
- [ ] `StatusReadout` — 5.3.1
- [ ] `PrimaryButton` — 5.3.2
- [ ] `SecondaryButton` — 5.3.2
- [ ] `SegmentedChips` — 5.3.3
- [ ] `PVCard` — 5.3.4
- [ ] `DashedPlaceholder` — 5.3.5
- [ ] `CourtOverlay` (blue in-bounds fill + green apron + optic-yellow lines incl. NVZ + net, from `CourtModel` + `AspectFillMapper`) — 5.4.1
- [ ] Existing calibration call-site `CourtOverlayView(model:imageSize:)` still compiles — 5.4.3 / 5.4.4

Every component is verified by a clean **0-warning** build and a SwiftUI `#Preview` that renders it. No raster assets; SF Symbols for icons; exact handoff hex/type tokens throughout.
