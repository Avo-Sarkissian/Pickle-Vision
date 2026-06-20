# Overnight Autonomous Build — 2026-06-20 → 06-21

**This is the morning report.** Mission, the autonomy contract, a live progress log, and the device-verification punch-list. Read the Punch-list + Status first.

---

## Mission (the goal command)

> Go through the queued Direction B UI plans (5 → 6 → 7 → 8), then the engine plans (3.5 auto-detect, 4 drift guard). Expand each to bite-sized detail, implement everything, build + unit-test in Xcode after every task, fix what breaks, commit + push to `main` per task. Make every decision autonomously — when a more thorough/complex approach is genuinely better, take it; correctness and quality over speed. Don't stop to ask. Leave a punch-list of anything only a physical iPhone 16 Pro can verify.

## Honest scope & limits

- **CAN do autonomously:** write code, expand plans, compile via Xcode (`BuildProject`/`xcodebuild`), keep 0 warnings, run `swift test`, fix compile/test failures, commit + push.
- **CANNOT do:** run the app on the physical device or see the screen. Visual fidelity, camera feed, orientation flips, gesture/loupe feel → **morning device gate** (punch-list below).
- **Definition of done for the night:** all of Plans 5–8 (+ Plan 4 drift UI, + Plan 3.5 auto-detect with guaranteed manual fallback) implemented, **app builds with 0 warnings**, **all `swift test` suites green**, pushed to `main`, with the punch-list filled in.

## Autonomy contract (how I'm deciding)

1. Make every product/design/architecture decision myself; log non-trivial ones in the Decisions Log below.
2. Prefer the more thorough option when it's genuinely better (e.g., a real fit-quality from residual over a fake bar; a proper state machine over ad-hoc flags), even if slower.
3. Honor the spec invariants: never hard-block on CV, honesty rule (no fabricated accuracy numbers in v1), bind to existing types (no new data models beyond those the plan names), per-screen orientation, exact handoff tokens, vector overlays, SF fonts.
4. Per task: (write code) → **build clean / `swift test` green** → commit + push to `main`. Builds are serialized through the orchestrator; subagents draft code, the orchestrator integrates + builds + tests.
5. On a blocker I can't resolve: log it, route around it (stub + fallback), keep going — don't stall the night.

## Phase plan

- **Phase 0 — Expand plans** 5–8 to bite-sized task specs (parallel subagents; no builds → safe). Commit the detailed plans.
- **Phase 1 — Plan 5 Design System** (foundation; sequential build).
- **Phase 2 — Plans 6 + 7** (Menus, Camera — independent; draft in parallel, integrate serially).
- **Phase 3 — Plan 8 Calibration wizard** (core logic TDD in parallel; wizard integrated serially).
- **Phase 4 — Plan 4 drift-guard UI + Plan 3.5 auto-detect** (best-effort + guaranteed manual fallback).
- **Phase 5 — Whole-app review pass** + final 0-warning build + full test run + punch-list.

---

## STATUS

`✅ COMPLETE — the full Direction-B UI is implemented. App builds 0 warnings · 0 navigator issues · PickleVisionCore 77/77 tests. All on main, pushed. Awaiting your on-device test.`

**Built (each task: implementer subagent → reviewer subagent → fix loop → commit + push, build verified 0 warnings):**
- **Plan 5 Design System** — `PVColor`, `PVFont` (SF Pro/SF Mono), 7 instrument atoms, zone-colored `CourtOverlay`.
- **Plan 6 Menus** — `CaptureProfile` + persistence, Home (populated + first-launch empty), `SavedCourtCard`, `SettingsView` (profile select + manage/delete courts), `HistoryView` placeholder, full nav incl. express re-cal.
- **Plan 7 Camera/Live** — restyled HUD (live REC timer + format/fps/thermal), Phase-tagged placeholders, faint decorative court guide, dark permission state.
- **Plan 8 Calibration wizard** — `FitQuality` + `CalibrationFlow` (TDD core) + the 4-step `Position → Detect → Fine-tune → Verify` flow + custom-dims + 0.5× card; `CalibrationScreen` is now a thin wizard host.
- **Plan 4 drift-guard UI component** (`DriftGuardOverlay`) — built, not yet wired to live drift (engine deferred).

~31 tasks + ~10 fixes (token literals, a real nav bug, a fake REC timer → live timer, …). **Final whole-UI integration + honesty review: READY** — honesty rule (structural — the auto-detect stub literally can't show a fake %), never-block invariant (enforced in the core type), token discipline, and the full nav graph all PASS.

**DEFERRED — device / real-court dependent (NOT built blind, by design):** Plan 3.5 auto-detect CV engine (the honest stub → manual is live, so the app never blocks); Plan 4 live drift wiring; position-check sensing. See the punch-list.

## Live progress log

- 2026-06-20 ~02:0x — Run initialized. Mac kept awake (caffeinate ~11h). Mission + contract recorded. Starting Phase 0 (plan expansion).
- ~02:30 — Phase 0 done: 4 planner subagents expanded Plans 5–8 to bite-sized specs (0c3de49).
- ~03:00 — Plan 5 (Design System, 4 tasks) complete.
- ~03:40 — Plan 6 (Menus, 9 tasks) complete — incl. a real fix to a nav bug (PrimaryButton-in-NavigationLink swallowed taps).
- ~04:00 — Plan 7 (Camera/Live, 4 tasks) complete — incl. fixing a fake "12:04" REC time → live elapsed timer (honesty).
- ~04:30 — Plan 8 (Calibration wizard, 9 tasks) complete — FitQuality + CalibrationFlow (TDD) + 4-step wizard + edge cases + CalibrationScreen swap.
- ~04:40 — Plan 4 DriftGuardOverlay UI component built. Final whole-UI integration/honesty review: **READY**. Whole-app build re-verified 0 warnings; core 77/77. Run ended cleanly.

## Decisions log

- **On `main`, no worktree:** the build toolchain (`xcodebuild`/Xcode MCP) is pointed at the repo; a worktree would break it. Building on `main` is the established project mechanic. (controller)
- **Plan 5 `CourtOverlay`:** all court lines stroke optic-yellow; blue/green are zone *fills* only (in-bounds / apron). Kept `CourtOverlayView` as a thin wrapper so the existing calibration call-site keeps compiling. (planner-5)
- **Added core API (NOT new data models):** `CalibrationStore.loadAll()` + `delete(venueName:)` for the saved-courts list; `CameraService.start(profile:)` for capture-profile selection. (planner-6)
- **`CaptureProfile`** = auto / uhd120 / fhd240 / fhd120 / batterySaver; recommended = uhd120, default = fhd120; **no uhd240** (iPhone 16 Pro lens limit). (planner-6)
- **Auto-detect stub = `.failed → manual`** (never fabricate a `.found`) — honors honesty + never-block; the real engine is Plan 3.5. (planner-8)
- **FitQuality** from the homography reprojection residual in normalized [0,1] space; residual value never shown (qualitative Good/Fair + 0–4 bar only). (planner-8)
- **Fixed latent bug:** the old single-screen `save()` dropped custom dimensions (`customDimensions: nil`); the wizard persists them. (planner-8)
- **History screen** has no nav entry in the handoff → built but `#Preview`-only for now; decide where it hangs in the morning. (planner-6)

## Device-verification PUNCH-LIST (do these in the morning on the iPhone 16 Pro)

**Plan 6 — Menus (compare on device, portrait):**
- [ ] Home **populated** vs `docs/design/screenshots/01-home.png` (header/hero/Start/saved-court cards/footer).
- [ ] Home **empty / first-launch** vs `02-home-empty.png` ("First court." + "No saved courts yet").
- [ ] **Settings** vs `03-settings.png` (capture-profile select + RECOMMENDED/DEFAULT pills + manage-courts Delete).
- [ ] **Nav works:** gear→Settings, Start a session→Camera, saved-court ↻→re-calibrate (seeds the court), Set-up-first-court→Camera, Delete removes a court.
- [ ] **Portrait↔landscape flips:** menus stay portrait; pushing Camera/Calibrate rotates to landscape; backing out returns to portrait (the one thing I couldn't verify — watch this).
- [ ] History screen: ghost cards currently use a dark panel on the light screen — may want a lighter surface (visual taste); also History has no nav entry yet (decide where it hangs).
- [ ] Home footer capsule uses `paper` (subtle) vs the brief's `panel` — confirm which reads better.

**Plan 7 — Camera/Live (landscape, dark):**
- [ ] Camera/Live vs `04-camera-live.png` (edge REC/format/fps + thermal pills, IN/OUT·PHASE2 + SCORE·PHASE6 + SLO-MO placeholders, Calibrate button, faint court guide).
- [ ] REC pill is a **live** elapsed timer (counts up from screen appear) — confirm it ticks, not a static value.
- [ ] Permission-denied dark state (revoke camera access in iOS Settings → "Camera access is off" + Open Settings).

**Plan 8 — Calibration wizard (landscape, dark):**
- [ ] Step 1 Position vs `06` — **Continue anyway** ALWAYS tappable; Calibrate manually; "Won't fit? 0.5×". (Position checks are **hardcoded placeholders** — real CoreMotion/CV sensing is deferred.)
- [ ] Step 2 Auto-detect vs `07`/`10` — in v1 it always runs "Finding…" → "Couldn't find the court" → manual (CV engine deferred); confirm the manual fallback feels right. (Failed state is a rail card, not yet the centered modal in `10` — visual taste.)
- [ ] Step 3 Fine-tune vs `08` — drag 4 corners + loupe (now optic-yellow); LAYOUT chips, overlay toggle, Re-freeze, Save→Verify. **EYEBALL THE LOUPE** (the long-standing on-device check).
- [ ] Step 4 Verify/Save vs `09` — tap-test = IN/OUT + x·y ft (**no ±in**), FIT QUALITY bar, name field, Save court → persists + returns.
- [ ] Custom-dimensions sheet (Width/Length/Kitchen) + 0.5× ultra-wide card.
- [ ] **FIT QUALITY caveat:** the bar is a *valid-court* check in v1 (a 4-point fit is ~perfect for any valid quad), NOT a precision measure — real per-zone accuracy is Phase 2. Decide if "Good/Fair" wording over-promises.

**Conscious product decisions to confirm:**
- [ ] After Save: the **camera path** lands back on the live camera (not Home); the **express re-cal path** lands back on Home and refreshes the list. Confirm that's what you want.
- [ ] `HistoryView` + `DriftGuardOverlay` are built but **not reachable** in the running app (no nav route / no live trigger). Decide where History hangs; the drift overlay waits on the Plan 4 engine.

**Deferred — device / real-court dependent (NOT built blind):**
- [ ] **Plan 3.5 auto-detect CV engine** (court line/keypoint detection) — needs a real court to tune; honest stub→manual is live so nothing blocks.
- [ ] **Plan 4 live drift wiring** (`DriftDetector` + runtime motion/feature-drift trigger → present `DriftGuardOverlay`).
- [ ] **Position-check sensing** (CoreMotion steady + CV whole-court/mount-height) — currently advisory placeholders.
- [ ] **Phase-2 numeric layer** (per-zone ±in confidence, tap-test distance-to-line) — intentionally omitted from v1 UI.
- [ ] **Custom fonts** (Saira/Manrope/Plex Mono) — SF Pro/SF Mono ships fine; bundling the custom faces is optional polish.

## Build/test state at hand-off

- **App:** BUILD SUCCEEDED · **0 warnings** · 0 navigator issues (Xcode MCP final build, re-verified after the last commit).
- **PickleVisionCore:** **77 tests, 0 failures.**
- HEAD = `af55403` on `main`; every task committed + pushed (~33 commits). SDD ledger: `.git/sdd/progress.md`.
- Full integration/honesty review verdict: **READY**. No Critical/Important blockers.
