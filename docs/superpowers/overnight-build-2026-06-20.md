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

`PHASE 2 — Plans 5 & 6 COMPLETE; building Plan 7 (Camera/Live)`, then Plan 8 (calibration wizard), then engine plans 3.5/4. Each task: implementer subagent → reviewer subagent → fix loop → commit+push, build 0 warnings. Done: **Plan 5 Design System** (PVColor, PVFont, 7 instrument atoms, zone-colored CourtOverlay) + **Plan 6 Menus** (CaptureProfile + store, Home populated + empty, SavedCourtCard, Settings w/ profile-select + manage-courts, History placeholder, nav fully wired incl. express re-cal). 13 tasks, all build clean, on `main`.

## Live progress log

- 2026-06-20 ~02:0x — Run initialized. Mac kept awake (caffeinate ~11h). Mission + contract recorded. Starting Phase 0 (plan expansion).

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

## Build/test state at hand-off

- (final build result + test counts will be recorded here)
