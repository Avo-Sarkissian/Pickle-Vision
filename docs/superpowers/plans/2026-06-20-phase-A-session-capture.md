# Phase A: Session + Capture - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make a saved court usable: tap it to open a live session with its calibrated overlay drawn on the feed, and record a clip bound to that court so later phases have real footage to process.

**Architecture:** Reuse the existing `CameraService` + `CameraScreen`. `CameraScreen` depends only on `CourtModel` (plus a display name); HomeView resolves the stored court to a `CourtModel` and passes it in, preserving the `CourtModel` boundary. Recording uses `AVCaptureMovieFileOutput` added to the existing session; finished clips are persisted as `SessionClip` records (JSON sidecar) via a `ClipStore` that mirrors `CalibrationStore`.

**Tech Stack:** SwiftUI, AVFoundation (`AVCaptureMovieFileOutput`), Combine, `PickleVisionCore` (Swift package), Swift Testing (app) + XCTest (core).

## Global Constraints

- No em-dashes in prose or comments. Hyphens only. (CONSIDERATIONS.md)
- `CourtModel` is the load-bearing boundary: `CameraScreen` must not import or reach into `CalibrationStore`/`StoredCalibration`; HomeView does the resolution. (CONSIDERATIONS.md)
- Personal tool, do not gold-plate: clip library is a minimal list, not a media manager.
- Honesty: the live overlay is the SAVED calibration map, not live-tracked. Label it as such; the REC indicator must reflect ACTUAL recording state, not a fake timer.
- Never hard-block: a session with no court still opens (decorative guide); recording failure shows a dismissable error, not a crash.
- Verification convention: core logic via `swift test`; views/camera via `BuildProject` (0 warnings) + `RenderPreview`; the real gate is on-device (records a playable clip on a real court).
- Image points are normalized [0,1] to the frame.

---

### Task A1: SessionClip model + ClipStore (core, TDD)

**Files:**
- Create: `PickleVisionCore/Sources/PickleVisionCore/SessionClip.swift`
- Create: `PickleVisionCore/Sources/PickleVisionCore/ClipStore.swift`
- Test: `PickleVisionCore/Tests/PickleVisionCoreTests/ClipStoreTests.swift`

**Interfaces:**
- Consumes: nothing (new leaf types).
- Produces:
  - `struct SessionClip: Codable, Equatable, Identifiable { var id: UUID; var courtID: UUID; var fileName: String; var fps: Double; var frameWidth: Double; var frameHeight: Double; var recordedAt: Date }` with `var frameSize: CGSize { CGSize(width: frameWidth, height: frameHeight) }`.
  - `final class ClipStore { init(directory: URL); func save(_ clip: SessionClip) throws; func loadAll() -> [SessionClip]; func delete(id: UUID) throws; func fileURL(for clip: SessionClip) -> URL; func clips(forCourt courtID: UUID) -> [SessionClip] }`
  - Sidecar JSON per clip at `<directory>/<id>.json`; the video file lives next to it at `fileName` (relative to `directory`).

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class ClipStoreTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("pv-clips-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func clip(court: UUID, at t: TimeInterval) -> SessionClip {
        SessionClip(id: UUID(), courtID: court, fileName: "\(UUID().uuidString).mov",
                    fps: 120, frameWidth: 1920, frameHeight: 1080,
                    recordedAt: Date(timeIntervalSince1970: t))
    }

    func test_save_load_round_trips_newest_first() throws {
        let store = ClipStore(directory: dir)
        let court = UUID()
        try store.save(clip(court: court, at: 1_000))
        try store.save(clip(court: court, at: 9_000))
        let all = store.loadAll()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first?.recordedAt, Date(timeIntervalSince1970: 9_000))
    }

    func test_clips_for_court_filters_by_id() throws {
        let store = ClipStore(directory: dir)
        let a = UUID(); let b = UUID()
        try store.save(clip(court: a, at: 1))
        try store.save(clip(court: b, at: 2))
        XCTAssertEqual(store.clips(forCourt: a).count, 1)
    }

    func test_delete_removes_record() throws {
        let store = ClipStore(directory: dir)
        let c = clip(court: UUID(), at: 1)
        try store.save(c)
        try store.delete(id: c.id)
        XCTAssertTrue(store.loadAll().isEmpty)
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `swift test --package-path PickleVisionCore --filter ClipStoreTests`
Expected: FAIL (types not defined).

- [ ] **Step 3: Implement `SessionClip.swift`**

```swift
import Foundation
import CoreGraphics

/// A recorded session clip, bound to the court it was shot on. The video file
/// lives beside this record; later phases process the file plus the court's
/// CourtModel. Frame size is stored as scalars so the record is portable.
public struct SessionClip: Codable, Equatable, Identifiable {
    public var id: UUID
    public var courtID: UUID
    public var fileName: String
    public var fps: Double
    public var frameWidth: Double
    public var frameHeight: Double
    public var recordedAt: Date

    public init(id: UUID = UUID(), courtID: UUID, fileName: String, fps: Double,
                frameWidth: Double, frameHeight: Double, recordedAt: Date) {
        self.id = id; self.courtID = courtID; self.fileName = fileName
        self.fps = fps; self.frameWidth = frameWidth; self.frameHeight = frameHeight
        self.recordedAt = recordedAt
    }

    public var frameSize: CGSize { CGSize(width: frameWidth, height: frameHeight) }
}
```

- [ ] **Step 4: Implement `ClipStore.swift`**

```swift
import Foundation

/// Persists SessionClip sidecar records (one <id>.json per clip) in a directory.
/// The video file is stored alongside at `fileName`. Mirrors CalibrationStore.
public final class ClipStore {
    private let directory: URL
    private let fm = FileManager.default

    public init(directory: URL) { self.directory = directory }

    private func recordURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    public func fileURL(for clip: SessionClip) -> URL {
        directory.appendingPathComponent(clip.fileName)
    }

    public func save(_ clip: SessionClip) throws {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(clip)
        try data.write(to: recordURL(for: clip.id), options: .atomic)
    }

    public func loadAll() -> [SessionClip] {
        guard let entries = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        let decoder = JSONDecoder()
        return entries
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(SessionClip.self, from: Data(contentsOf: $0)) }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    public func clips(forCourt courtID: UUID) -> [SessionClip] {
        loadAll().filter { $0.courtID == courtID }
    }

    public func delete(id: UUID) throws {
        let rec = recordURL(for: id)
        if let clip = try? JSONDecoder().decode(SessionClip.self, from: Data(contentsOf: rec)) {
            try? fm.removeItem(at: fileURL(for: clip))   // remove the video too
        }
        if fm.fileExists(atPath: rec.path) { try fm.removeItem(at: rec) }
    }
}
```

- [ ] **Step 5: Run tests, confirm pass**

Run: `swift test --package-path PickleVisionCore --filter ClipStoreTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add PickleVisionCore/Sources/PickleVisionCore/SessionClip.swift PickleVisionCore/Sources/PickleVisionCore/ClipStore.swift PickleVisionCore/Tests/PickleVisionCoreTests/ClipStoreTests.swift
git commit -m "feat(core): SessionClip + ClipStore (clip records bound to a court)"
```

---

### Task A2: CameraScreen draws a passed-in CourtModel; wire the session route

**Files:**
- Modify: `PickleVision/PickleVision/CameraScreen.swift`
- Modify: `PickleVision/PickleVision/HomeView.swift`
- Modify: `PickleVision/PickleVision/SavedCourtCard.swift`

**Interfaces:**
- Consumes: `CourtModel` (core), `CalibrationStore.courtModel(from:)` (HomeView only).
- Produces: `CameraScreen(profile:court:courtName:)` where `court: CourtModel? = nil`, `courtName: String? = nil`; `HomeView.NavRoute.session(id: UUID)`; `SavedCourtCard(calibration:onStart:onReload:)`.

- [ ] **Step 1: Add params to `CameraScreen`**

Add stored properties and init params:

```swift
private let profile: CaptureProfile
private let court: CourtModel?
private let courtName: String?

init(profile: CaptureProfile = .auto, court: CourtModel? = nil, courtName: String? = nil) {
    self.profile = profile
    self.court = court
    self.courtName = courtName
}
```

- [ ] **Step 2: Draw the calibrated overlay when a court is present**

In the `.authorized` branch, replace the unconditional `DecorativeCourtGuide()` with:

```swift
if let court {
    CourtOverlay(model: court, imageSize: camera.imageSize)
        .ignoresSafeArea()
        .allowsHitTesting(false)
} else {
    DecorativeCourtGuide()
        .opacity(0.28)
        .padding(.horizontal, 80).padding(.vertical, 40)
        .allowsHitTesting(false)
        .ignoresSafeArea()
}
```

- [ ] **Step 3: Add a court-name pill + honesty note**

In `topRow` (or as an overlay), when `courtName != nil`, show an `InstrumentPill(courtName!, tint: PVColor.optic)` and a small caption `Text("Saved map - re-tap with Calibrate if the camera moved")` using `PVFont.mono(9)` / `PVColor.onDarkDim`. Keep it out of the IN/OUT placeholder area.

- [ ] **Step 4: Add the `.session` route in HomeView**

In `NavRoute` add `case session(id: UUID)`. In `navigationDestination`:

```swift
case .session(let id):
    if let cal = store.load(id: id), let model = CalibrationStore.courtModel(from: cal) {
        CameraScreen(profile: profileStore.profile, court: model, courtName: cal.venueName)
    } else {
        CameraScreen(profile: profileStore.profile)   // court unreadable: generic session
    }
```

- [ ] **Step 5: Make the saved-court card start a session; "Start a session" uses the most recent court**

In `SavedCourtCard`, add `var onStart: () -> Void` and wrap the venue/metadata area (not the reload button) in a `Button(action: onStart)` with `.buttonStyle(.plain)` and `.contentShape(Rectangle())`. In HomeView `populatedContent`:

```swift
ForEach(courts) { cal in
    SavedCourtCard(calibration: cal,
                   onStart:  { path.append(.session(id: cal.id)) },
                   onReload: { path.append(.recalibrate(id: cal.id)) })
}
```

Change the populated "Start a session" button to `if let first = courts.first { path.append(.session(id: first.id)) }` (courts is newest-first).

- [ ] **Step 6: Build + render to verify**

Run: `BuildProject` (expect success, 0 warnings).
Run: `RenderPreview` on `CameraScreen.swift` after adding a `#Preview` that constructs a `CourtModel` from normalized corners (see CourtOverlay preview) and passes it as `court:`. Confirm the court overlay draws on the feed-gradient stand-in.

- [ ] **Step 7: Commit**

```bash
git add PickleVision/PickleVision/CameraScreen.swift PickleVision/PickleVision/HomeView.swift PickleVision/PickleVision/SavedCourtCard.swift
git commit -m "feat(session): tap a saved court to open a live session with its overlay"
```

---

### Task A3: Recording in CameraService

**Files:**
- Modify: `PickleVision/PickleVision/CameraService.swift`

**Interfaces:**
- Consumes: `ClipStore`, `SessionClip` (core), the active `courtID`.
- Produces on `CameraService`: `@Published private(set) var isRecording: Bool`; `func startRecording(courtID: UUID)`; `func stopRecording()`; a `@Published var lastSavedClip: SessionClip?` the UI can observe.

- [ ] **Step 1: Add a movie output to the session**

Add `private let movieOutput = AVCaptureMovieFileOutput()`. In `configureSession()`, after adding `videoOutput`, add:

```swift
if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }
```

Pitfall to flag in a comment: `AVCaptureMovieFileOutput` and a high-fps `AVCaptureVideoDataOutput` can coexist, but sustained 4K/120 recording is large and hot. For personal use this is acceptable; revisit if thermals bite (see CONSIDERATIONS.md).

- [ ] **Step 2: Add recording state + start/stop**

```swift
@Published private(set) var isRecording = false
@Published var lastSavedClip: SessionClip?
private var recordingCourtID: UUID?
private let clipStore = ClipStore(directory: URL.documentsDirectory.appendingPathComponent("clips"))

func startRecording(courtID: UUID) {
    sessionQueue.async { [weak self] in
        guard let self, !self.movieOutput.isRecording else { return }
        self.recordingCourtID = courtID
        let name = "\(UUID().uuidString).mov"
        let url = URL.documentsDirectory.appendingPathComponent("clips").appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        self.movieOutput.startRecording(to: url, recordingDelegate: self)
        self.publishOnMain { self.isRecording = true }
    }
}

func stopRecording() {
    sessionQueue.async { [weak self] in
        guard let self, self.movieOutput.isRecording else { return }
        self.movieOutput.stopRecording()
    }
}
```

- [ ] **Step 3: Implement the recording delegate, persist a SessionClip on finish**

```swift
extension CameraService: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        let courtID = recordingCourtID ?? UUID()
        let size = imageSize
        let fps = Double(chosenMaxRate)
        publishOnMain { self.isRecording = false }
        guard error == nil else { return }   // dismissable failure: just leave isRecording false
        let clip = SessionClip(courtID: courtID, fileName: outputFileURL.lastPathComponent,
                               fps: fps, frameWidth: size.width, frameHeight: size.height,
                               recordedAt: Date())
        try? clipStore.save(clip)
        publishOnMain { self.lastSavedClip = clip }
    }
}
```

Note: `chosenMaxRate` is already tracked in `configureSession`. `imageSize` defaults to 1920x1080 and is 16:9-correct; if exact recorded dimensions matter later, read them from the finished asset in B-phase processing.

- [ ] **Step 4: Build to verify**

Run: `BuildProject` (expect success, 0 warnings). Confirm `Info.plist` has `NSMicrophoneUsageDescription` only if you enable audio; default `AVCaptureMovieFileOutput` may capture audio if an audio input is added - we add none, so video-only, no mic permission needed. Verify no audio input is added.

- [ ] **Step 5: Commit**

```bash
git add PickleVision/PickleVision/CameraService.swift
git commit -m "feat(camera): record session clips bound to the active court"
```

---

### Task A4: Record button + REC indicator wired to real state

**Files:**
- Modify: `PickleVision/PickleVision/CameraScreen.swift`

**Interfaces:**
- Consumes: `camera.isRecording`, `camera.startRecording(courtID:)`, `camera.stopRecording()`, and the court id (pass the `StoredCalibration.id` through, or thread a `courtID: UUID?` into `CameraScreen`).

- [ ] **Step 1: Thread the court id into CameraScreen**

Add `private let courtID: UUID?` and an init param `courtID: UUID? = nil`. In HomeView `.session` route, pass `courtID: cal.id`.

- [ ] **Step 2: Add a record toggle in `bottomRow`**

```swift
Button {
    if camera.isRecording { camera.stopRecording() }
    else if let courtID { camera.startRecording(courtID: courtID) }
} label: {
    Image(systemName: camera.isRecording ? "stop.circle.fill" : "record.circle")
        .font(PVFont.display(34))
        .foregroundStyle(camera.isRecording ? PVColor.recordRed : PVColor.onDark)
}
.disabled(courtID == nil)   // generic court-less session cannot record a bound clip
.accessibilityLabel(camera.isRecording ? "Stop recording" : "Start recording")
```

- [ ] **Step 3: Make the REC pill honest**

Replace the appear-time elapsed timer so it only counts while `camera.isRecording`. When not recording, show `REC --:--` (idle). When recording, drive the `TimelineView` from a recording-start `Date` set in `.onChange(of: camera.isRecording)`.

- [ ] **Step 4: Build + render to verify**

Run: `BuildProject` (0 warnings). `RenderPreview` the session preview to confirm the record button and idle REC state render.

- [ ] **Step 5: Commit**

```bash
git add PickleVision/PickleVision/CameraScreen.swift
git commit -m "feat(session): record button + honest REC indicator"
```

---

### Task A5: Minimal clip list (reuse HistoryView)

**Files:**
- Modify: `PickleVision/PickleVision/History/HistoryView.swift`
- Modify: `PickleVision/PickleVision/HomeView.swift` (add a route/entry to reach it)

**Interfaces:**
- Consumes: `ClipStore.loadAll()`, `SessionClip`.

- [ ] **Step 1: List saved clips**

Replace the History placeholder with a list of `ClipStore().loadAll()` rows showing court name (resolve via `CalibrationStore.load(id: clip.courtID)`), date, and fps; a Delete action calling `ClipStore.delete(id:)`. Keep it minimal (no playback yet; B3 adds the review overlay).

- [ ] **Step 2: Reach it from Home**

Add a small "Clips" affordance (e.g. in the header next to the gear, or a row under SAVED COURTS) that pushes the history/clips screen. Keep it unobtrusive.

- [ ] **Step 3: Build + render**

Run: `BuildProject` (0 warnings). `RenderPreview` HistoryView with a seeded temp `ClipStore`.

- [ ] **Step 4: Commit**

```bash
git add PickleVision/PickleVision/History/HistoryView.swift PickleVision/PickleVision/HomeView.swift
git commit -m "feat(clips): minimal saved-clip list with delete"
```

---

## Self-review notes

- Spec coverage: session wiring (A2), live calibrated overlay (A2), recording bound to court (A1/A3/A4), clip retrieval for later phases (A1/A5). Covered.
- `CourtModel` boundary: `CameraScreen` consumes `CourtModel`, never `CalibrationStore`; resolution stays in HomeView. Held.
- Verification: core (ClipStore) is TDD; views/camera are build + RenderPreview; the real gate is recording a playable clip on a real court (on-device).
- Deferred to Phase B and beyond: any processing of the recorded clip, ball detection, in/out. A only captures.

## On-device acceptance (the real "done")

On the iPhone 16 Pro, mounted in landscape on a calibrated court: tap a saved court, confirm the overlay sits on the real lines, record a 10-20s clip, stop, and confirm it appears in the clip list and plays back. Note overlay drift if the mount was bumped (expected; Calibrate re-taps).
