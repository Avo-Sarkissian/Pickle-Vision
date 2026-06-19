# Manual Court Calibration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A working manual court calibration: freeze a camera frame, drag the four court corners (with a magnifier loupe), pick the layout, see the court drawn back over the frame, tap-test a point to confirm accuracy, and save — producing a persistent `CourtModel` that later phases consume.

**Architecture:** Pure coordinate/calibration logic is TDD'd in `PickleVisionCore` (aspect-fill view↔image mapping, the calibration draft that builds a `CourtModel` from tapped corners, handle hit-testing). The SwiftUI calibration screens + overlay are built via the Xcode MCP and verified by compile + on-device. **The app standardizes on normalized image coordinates `[0,1]` everywhere** (resolution-independent, persists cleanly, and the homography's source space).

**Tech Stack:** Swift 5.9+ (app target Swift 5 mode), SwiftUI, AVFoundation, the existing `PickleVisionCore` package. No third-party dependencies.

This is **Plan 3 of 4+** for Phase 0–1. Plans 1–2 are complete on `main`. **Auto-detect is deliberately the *next* plan ("Plan 3.5")** — this manual core is the reliable foundation and also produces the ground-truth corners needed to bootstrap and validate auto-detect.

## Global Constraints

- **Normalized image coordinates `[0,1]`** for all calibration points and the homography's source space. `(0,0)` = top-left of the image, `(1,1)` = bottom-right.
- **Corner order everywhere: `[nearLeft, nearRight, farRight, farLeft]`** (matches `CourtProfile.calibrationCorners`).
- **Reuse existing `PickleVisionCore` types** unchanged: `Homography`, `CourtProfile`, `CourtLayout`, `CustomDimensions`, `CourtModel`, `CalibrationStore`, `CodablePoint`, `StoredCalibration`. (`StoredCalibration.imageCorners` now holds normalized corners — same type, no schema change.)
- App target: **Swift 5 mode**, no third-party deps. Device tasks verified by `xcodebuild` / Xcode MCP `BuildProject` (clean, zero warnings) + on-device.
- App source files live in `PickleVision/PickleVision/` (Xcode 16 synchronized group — new files auto-include).

---

## File Structure

```
PickleVisionCore/
  Sources/PickleVisionCore/
    AspectFillMapper.swift        # Task 1 — view <-> normalized-image mapping
    CalibrationDraft.swift        # Task 2 — corners -> CourtModel; handle hit-testing
  Tests/PickleVisionCoreTests/
    AspectFillMapperTests.swift   # Task 1
    CalibrationDraftTests.swift   # Task 2
PickleVision/PickleVision/
    CameraService.swift           # Task 3 — add frozen-frame snapshot (modify)
    CalibrationView.swift         # Task 4 — frozen frame + draggable corners + loupe
    CourtOverlayView.swift        # Task 5 — draw the calibrated court
    CalibrationScreen.swift       # Task 6 — layout picker + tap-test + save + flow
    CameraScreen.swift            # Task 6 — add "Calibrate" entry point (modify)
```

---

### Task 1: AspectFillMapper (TDD, PickleVisionCore)

Maps points between a preview **view** (which shows the camera with `.resizeAspectFill` — scaled to fill, overflow cropped) and **normalized image** coordinates. This is the fiddly, bug-prone part, so it is pure and fully tested.

**Files:**
- Create: `PickleVisionCore/Sources/PickleVisionCore/AspectFillMapper.swift`
- Test: `PickleVisionCore/Tests/PickleVisionCoreTests/AspectFillMapperTests.swift`

**Interfaces:**
- Produces `struct AspectFillMapper` with `init(viewSize: CGSize, contentSize: CGSize)`, `func imageNormalized(fromView p: CGPoint) -> CGPoint`, `func view(fromImageNormalized n: CGPoint) -> CGPoint`.

- [ ] **Step 1: Write the failing tests**

`AspectFillMapperTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class AspectFillMapperTests: XCTestCase {
    // Square 100x100 content shown in a 200x100 (wide) view → scale 2x, vertical overflow cropped.
    private let mapper = AspectFillMapper(viewSize: CGSize(width: 200, height: 100),
                                          contentSize: CGSize(width: 100, height: 100))

    func test_view_center_maps_to_image_center() {
        let n = mapper.imageNormalized(fromView: CGPoint(x: 100, y: 50))
        XCTAssertEqual(n.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(n.y, 0.5, accuracy: 1e-9)
    }

    func test_view_top_left_is_inside_cropped_image() {
        // Vertical content is cropped: view y=0 sits 25% down the image.
        let n = mapper.imageNormalized(fromView: CGPoint(x: 0, y: 0))
        XCTAssertEqual(n.x, 0.0, accuracy: 1e-9)
        XCTAssertEqual(n.y, 0.25, accuracy: 1e-9)
    }

    func test_round_trips() {
        for p in [CGPoint(x: 30, y: 20), CGPoint(x: 175, y: 80), CGPoint(x: 100, y: 50)] {
            let back = mapper.view(fromImageNormalized: mapper.imageNormalized(fromView: p))
            XCTAssertEqual(back.x, p.x, accuracy: 1e-6)
            XCTAssertEqual(back.y, p.y, accuracy: 1e-6)
        }
    }

    func test_tall_view_crops_horizontally() {
        // 100x100 content in a 100x200 (tall) view → scale 2x, horizontal overflow cropped.
        let m = AspectFillMapper(viewSize: CGSize(width: 100, height: 200),
                                 contentSize: CGSize(width: 100, height: 100))
        let n = m.imageNormalized(fromView: CGPoint(x: 0, y: 100)) // left edge, vertical center
        XCTAssertEqual(n.x, 0.25, accuracy: 1e-9)
        XCTAssertEqual(n.y, 0.5, accuracy: 1e-9)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path PickleVisionCore --filter AspectFillMapperTests`
Expected: FAIL — `cannot find 'AspectFillMapper' in scope`.

- [ ] **Step 3: Implement the mapper**

`AspectFillMapper.swift`:

```swift
import CoreGraphics

/// Maps points between a view that renders content with aspect-fill (scaled to
/// fill, overflow cropped) and normalized image coordinates in `[0,1]`,
/// where `(0,0)` is the image's top-left.
public struct AspectFillMapper {
    public let viewSize: CGSize
    public let contentSize: CGSize
    private let scale: CGFloat
    private let offset: CGPoint

    public init(viewSize: CGSize, contentSize: CGSize) {
        self.viewSize = viewSize
        self.contentSize = contentSize
        let s = max(viewSize.width / contentSize.width,
                    viewSize.height / contentSize.height)
        self.scale = s
        // Centered; offsets are <= 0 because the scaled content overflows.
        self.offset = CGPoint(x: (viewSize.width - contentSize.width * s) / 2,
                              y: (viewSize.height - contentSize.height * s) / 2)
    }

    /// View point → normalized image coordinate.
    public func imageNormalized(fromView p: CGPoint) -> CGPoint {
        let imgX = (p.x - offset.x) / scale
        let imgY = (p.y - offset.y) / scale
        return CGPoint(x: imgX / contentSize.width, y: imgY / contentSize.height)
    }

    /// Normalized image coordinate → view point.
    public func view(fromImageNormalized n: CGPoint) -> CGPoint {
        let imgX = n.x * contentSize.width
        let imgY = n.y * contentSize.height
        return CGPoint(x: imgX * scale + offset.x, y: imgY * scale + offset.y)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path PickleVisionCore --filter AspectFillMapperTests`
Expected: PASS — 4 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add PickleVisionCore
git commit -m "feat(core): add AspectFillMapper (view<->normalized-image mapping)"
```

---

### Task 2: CalibrationDraft + handle hit-testing (TDD, PickleVisionCore)

The in-progress calibration: the four corners (normalized), the layout, and the conversion to a `CourtModel`. Plus nearest-handle hit-testing for dragging.

**Files:**
- Create: `PickleVisionCore/Sources/PickleVisionCore/CalibrationDraft.swift`
- Test: `PickleVisionCore/Tests/PickleVisionCoreTests/CalibrationDraftTests.swift`

**Interfaces:**
- Consumes: `CourtProfile`, `CourtLayout`, `CustomDimensions`, `Homography`, `CourtModel`.
- Produces:
  - `struct CalibrationDraft` with `var corners: [CGPoint]` (normalized, order `[nearLeft,nearRight,farRight,farLeft]`), `var layout: CourtLayout`, `var customDimensions: CustomDimensions?`
  - `var isComplete: Bool` (exactly 4 corners)
  - `func courtModel() -> CourtModel?` (builds the normalized-image→court homography)
  - `func nearestCornerIndex(toView p: CGPoint, handles: [CGPoint], within radius: CGFloat) -> Int?`
  - `static func defaultCorners() -> [CGPoint]` (a sensible starting quad in normalized coords)

- [ ] **Step 1: Write the failing tests**

`CalibrationDraftTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class CalibrationDraftTests: XCTestCase {
    private func sampleCorners() -> [CGPoint] {
        // A trapezoid in normalized image space (near edge lower/wider).
        [CGPoint(x: 0.20, y: 0.90), CGPoint(x: 0.80, y: 0.90),
         CGPoint(x: 0.65, y: 0.30), CGPoint(x: 0.35, y: 0.30)]
    }

    func test_incomplete_until_four_corners() {
        var d = CalibrationDraft(layout: .regulationPickleball)
        XCTAssertFalse(d.isComplete)
        d.corners = sampleCorners()
        XCTAssertTrue(d.isComplete)
    }

    func test_builds_court_model_mapping_corner_to_origin() {
        let d = CalibrationDraft(corners: sampleCorners(), layout: .regulationPickleball)
        let model = try! XCTUnwrap(d.courtModel())
        // nearLeft normalized corner maps to court origin (0,0).
        let c = model.courtPoint(forImage: CGPoint(x: 0.20, y: 0.90))
        XCTAssertEqual(c.x, 0, accuracy: 1e-6)
        XCTAssertEqual(c.y, 0, accuracy: 1e-6)
        XCTAssertEqual(model.profile.layout, .regulationPickleball)
    }

    func test_nil_court_model_when_incomplete() {
        XCTAssertNil(CalibrationDraft(layout: .regulationPickleball).courtModel())
    }

    func test_nearest_corner_within_radius() {
        let handles = [CGPoint(x: 10, y: 10), CGPoint(x: 200, y: 10),
                       CGPoint(x: 200, y: 200), CGPoint(x: 10, y: 200)]
        let d = CalibrationDraft(layout: .regulationPickleball)
        XCTAssertEqual(d.nearestCornerIndex(toView: CGPoint(x: 14, y: 13), handles: handles, within: 30), 0)
        XCTAssertNil(d.nearestCornerIndex(toView: CGPoint(x: 100, y: 100), handles: handles, within: 30))
    }

    func test_default_corners_are_four_inside_unit_square() {
        let c = CalibrationDraft.defaultCorners()
        XCTAssertEqual(c.count, 4)
        XCTAssertTrue(c.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path PickleVisionCore --filter CalibrationDraftTests`
Expected: FAIL — `cannot find 'CalibrationDraft' in scope`.

- [ ] **Step 3: Implement the draft**

`CalibrationDraft.swift`:

```swift
import CoreGraphics
import Foundation

/// An in-progress manual calibration: the four court corners (normalized image
/// coords, order [nearLeft, nearRight, farRight, farLeft]) and the chosen layout.
public struct CalibrationDraft {
    public var corners: [CGPoint]
    public var layout: CourtLayout
    public var customDimensions: CustomDimensions?

    public init(corners: [CGPoint] = [], layout: CourtLayout, customDimensions: CustomDimensions? = nil) {
        self.corners = corners
        self.layout = layout
        self.customDimensions = customDimensions
    }

    public var isComplete: Bool { corners.count == 4 }

    /// Builds the calibrated `CourtModel` (normalized-image → court homography),
    /// or `nil` if the four corners aren't set or are degenerate.
    public func courtModel() -> CourtModel? {
        guard isComplete else { return nil }
        let profile = CourtProfile.make(layout: layout, custom: customDimensions)
        guard let h = Homography(source: corners, destination: profile.calibrationCorners) else {
            return nil
        }
        return CourtModel(profile: profile, homography: h)
    }

    /// Index of the handle nearest to `p` within `radius` (view-space points), or nil.
    public func nearestCornerIndex(toView p: CGPoint, handles: [CGPoint], within radius: CGFloat) -> Int? {
        var bestIndex: Int?
        var bestDist = radius
        for (i, h) in handles.enumerated() {
            let d = hypot(h.x - p.x, h.y - p.y)
            if d <= bestDist { bestDist = d; bestIndex = i }
        }
        return bestIndex
    }

    /// A starting quad (normalized) the user nudges onto the real lines.
    public static func defaultCorners() -> [CGPoint] {
        [CGPoint(x: 0.20, y: 0.85), CGPoint(x: 0.80, y: 0.85),
         CGPoint(x: 0.65, y: 0.35), CGPoint(x: 0.35, y: 0.35)]
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path PickleVisionCore --filter CalibrationDraftTests`
Expected: PASS — 5 tests, 0 failures.

- [ ] **Step 5: Run the full package suite and commit**

Run: `swift test --package-path PickleVisionCore`
Expected: all suites pass.

```bash
git add PickleVisionCore
git commit -m "feat(core): add CalibrationDraft (corners->CourtModel, handle hit-testing)"
```

---

### Task 3: CameraService — capture a frozen still frame (device)

Calibration happens on a *frozen* frame (far easier than a moving feed). Add a snapshot to `CameraService`.

**Files:**
- Modify: `PickleVision/PickleVision/CameraService.swift`

**Interfaces:**
- Produces on `CameraService`: `@Published private(set) var latestImage: CGImage?` (most recent frame, published on main, throttled to ~every few frames) and the image's pixel `contentSize` available via `@Published private(set) var imageSize: CGSize`.

- [ ] **Step 1: Add frame snapshotting**

In `captureOutput(_:didOutput:from:)`, in addition to the fps logic, convert the sample buffer to a `CGImage` occasionally (every ~10th frame is plenty for a freeze source) and publish it. Add near the other private vars:

```swift
    private var frameCounter = 0
    private let ciContext = CIContext()
```

And in the delegate method, after the fps block:

```swift
        frameCounter += 1
        if frameCounter % 10 == 0, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let ci = CIImage(cvPixelBuffer: pixelBuffer)
            let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                              height: CVPixelBufferGetHeight(pixelBuffer))
            if let cg = ciContext.createCGImage(ci, from: ci.extent) {
                publishOnMain {
                    self.latestImage = cg
                    self.imageSize = size
                }
            }
        }
```

Add the published properties near the others:

```swift
    @Published private(set) var latestImage: CGImage?
    @Published private(set) var imageSize: CGSize = CGSize(width: 1920, height: 1080)
```

- [ ] **Step 2: Build via the Xcode MCP (or xcodebuild) and confirm clean**

Build the `PickleVision` scheme. Expected: BUILD SUCCEEDED, zero warnings. (Note: `CIImage` orientation — the CGImage will be in the camera's native orientation; the calibration view treats it as the image space, and `imageSize` carries its pixel dimensions. Orientation handling is consistent because all calibration math is in normalized image space.)

- [ ] **Step 3: Commit**

```bash
git add PickleVision/PickleVision/CameraService.swift
git commit -m "feat(app): expose a throttled frozen-frame snapshot from CameraService"
```

---

### Task 4: CalibrationView — frozen frame + draggable corners + loupe (device)

**Files:**
- Create: `PickleVision/PickleVision/CalibrationView.swift`

**Interfaces:**
- Produces `struct CalibrationView: View` taking `let image: CGImage`, `let imageSize: CGSize`, and `@Binding var corners: [CGPoint]` (normalized). Renders the frozen image aspect-fill, draws 4 draggable handles, and shows a magnifier loupe while dragging.

- [ ] **Step 1: Write `CalibrationView.swift`**

```swift
import SwiftUI
import PickleVisionCore

/// Shows a frozen frame with four draggable corner handles (normalized coords)
/// and a magnifier loupe for precise placement.
struct CalibrationView: View {
    let image: CGImage
    let imageSize: CGSize
    @Binding var corners: [CGPoint]   // normalized [0,1], order nearLeft,nearRight,farRight,farLeft

    @State private var dragging: Int? = nil
    @State private var dragLocation: CGPoint = .zero

    private let labels = ["NL", "NR", "FR", "FL"]

    var body: some View {
        GeometryReader { geo in
            let mapper = AspectFillMapper(viewSize: geo.size, contentSize: imageSize)
            let handles = corners.map { mapper.view(fromImageNormalized: $0) }

            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                // Quad outline connecting the handles.
                Path { p in
                    guard handles.count == 4 else { return }
                    p.move(to: handles[0])
                    for h in handles.dropFirst() { p.addLine(to: h) }
                    p.closeSubpath()
                }
                .stroke(Color.yellow.opacity(0.9), lineWidth: 2)

                // Handles.
                ForEach(handles.indices, id: \.self) { i in
                    handleView(label: labels[i])
                        .position(handles[i])
                }

                if let d = dragging {
                    loupe(at: dragLocation, mapper: mapper, geo: geo, handleIndex: d)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(geo: geo, mapper: mapper, handles: handles))
        }
    }

    private func handleView(label: String) -> some View {
        ZStack {
            Circle().stroke(Color.yellow, lineWidth: 2).frame(width: 28, height: 28)
            Circle().fill(Color.yellow).frame(width: 6, height: 6)
            Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(.yellow)
                .offset(y: 20)
        }
    }

    private func dragGesture(geo: GeometryProxy, mapper: AspectFillMapper, handles: [CGPoint]) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragging == nil {
                    let draft = CalibrationDraft(layout: .regulationPickleball)
                    dragging = draft.nearestCornerIndex(toView: value.startLocation, handles: handles, within: 44)
                }
                if let i = dragging {
                    dragLocation = value.location
                    corners[i] = clampNormalized(mapper.imageNormalized(fromView: value.location))
                }
            }
            .onEnded { _ in dragging = nil }
    }

    private func clampNormalized(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1))
    }

    /// A magnifier showing the area under the dragged handle.
    private func loupe(at location: CGPoint, mapper: AspectFillMapper, geo: GeometryProxy, handleIndex: Int) -> some View {
        let loupeSize: CGFloat = 110
        let zoom: CGFloat = 2.5
        return Image(decorative: image, scale: 1, orientation: .up)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(zoom)
            .offset(x: (geo.size.width / 2 - location.x) * zoom,
                    y: (geo.size.height / 2 - location.y) * zoom)
            .frame(width: loupeSize, height: loupeSize)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .overlay(Image(systemName: "plus").font(.system(size: 10)).foregroundStyle(.white))
            .position(x: min(max(location.x, loupeSize), geo.size.width - loupeSize),
                      y: max(location.y - loupeSize, loupeSize))
    }
}
```

- [ ] **Step 2: Build and confirm clean**

Build the `PickleVision` scheme via the Xcode MCP / xcodebuild. Expected: BUILD SUCCEEDED, zero warnings.

- [ ] **Step 3: Commit**

```bash
git add PickleVision/PickleVision/CalibrationView.swift
git commit -m "feat(app): CalibrationView with draggable corner handles + loupe"
```

---

### Task 5: CourtOverlayView — draw the calibrated court (device)

**Files:**
- Create: `PickleVision/PickleVision/CourtOverlayView.swift`

**Interfaces:**
- Produces `struct CourtOverlayView: View` taking `let model: CourtModel`, `let imageSize: CGSize`. Draws the court's lines (sidelines, baselines, net, NVZ) by mapping each court point → normalized image (via `model.imagePoint(forCourt:)`) → view (via `AspectFillMapper`).

- [ ] **Step 1: Write `CourtOverlayView.swift`**

```swift
import SwiftUI
import PickleVisionCore

/// Draws the calibrated court geometry over the feed/frame so the user can
/// confirm the mapping visually.
struct CourtOverlayView: View {
    let model: CourtModel
    let imageSize: CGSize

    var body: some View {
        GeometryReader { geo in
            let mapper = AspectFillMapper(viewSize: geo.size, contentSize: imageSize)

            func toView(_ court: CGPoint) -> CGPoint? {
                guard let n = model.imagePoint(forCourt: court) else { return nil }
                return mapper.view(fromImageNormalized: n)
            }
            func segment(_ a: CGPoint, _ b: CGPoint) -> Path {
                var p = Path()
                if let va = toView(a), let vb = toView(b) { p.move(to: va); p.addLine(to: vb) }
                return p
            }

            let profile = model.profile
            ZStack {
                // In-bounds outline.
                Path { p in
                    let poly = profile.inBoundsPolygon.compactMap(toView)
                    if poly.count == profile.inBoundsPolygon.count {
                        p.move(to: poly[0]); poly.dropFirst().forEach { p.addLine(to: $0) }; p.closeSubpath()
                    }
                }.stroke(Color.green, lineWidth: 2)

                // NVZ lines.
                ForEach(profile.nvzLines.indices, id: \.self) { i in
                    segment(profile.nvzLines[i][0], profile.nvzLines[i][1])
                        .stroke(Color.yellow, lineWidth: 1.5)
                }
                // Net line.
                segment(profile.netLine[0], profile.netLine[1])
                    .stroke(Color.red, lineWidth: 2.5)
            }
        }
        .allowsHitTesting(false)
    }
}
```

- [ ] **Step 2: Build and confirm clean**

Build the `PickleVision` scheme. Expected: BUILD SUCCEEDED, zero warnings.

- [ ] **Step 3: Commit**

```bash
git add PickleVision/PickleVision/CourtOverlayView.swift
git commit -m "feat(app): CourtOverlayView draws the calibrated court geometry"
```

---

### Task 6: Calibration flow — layout picker + tap-test + save + entry point (device)

Ties it together into a screen: freeze a frame → pick layout → drag corners → see overlay → tap-test → save.

**Files:**
- Create: `PickleVision/PickleVision/CalibrationScreen.swift`
- Modify: `PickleVision/PickleVision/CameraScreen.swift` (add a "Calibrate" button)

**Interfaces:**
- Consumes: `CameraService` (frozen frame), `CalibrationView` (Task 4), `CourtOverlayView` (Task 5), `CalibrationDraft` + `AspectFillMapper` (Tasks 1–2), `CalibrationStore` + `StoredCalibration` + `CodablePoint`.
- Produces `struct CalibrationScreen: View` taking `@ObservedObject var camera: CameraService`.

- [ ] **Step 1: Write `CalibrationScreen.swift`**

```swift
import SwiftUI
import PickleVisionCore

struct CalibrationScreen: View {
    @ObservedObject var camera: CameraService
    @Environment(\.dismiss) private var dismiss

    @State private var frozen: CGImage?
    @State private var frozenSize: CGSize = .zero
    @State private var layout: CourtLayout = .regulationPickleball
    @State private var corners: [CGPoint] = CalibrationDraft.defaultCorners()
    @State private var showOverlay = false
    @State private var tapResult: String?
    @State private var venueName = "My Court"

    private var draft: CalibrationDraft {
        CalibrationDraft(corners: corners, layout: layout)
    }
    private var store: CalibrationStore {
        CalibrationStore(directory: URL.documentsDirectory.appendingPathComponent("calibrations"))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Layout", selection: $layout) {
                Text("Pickleball").tag(CourtLayout.regulationPickleball)
                Text("Tennis box").tag(CourtLayout.tennisFrontBox)
                Text("Custom").tag(CourtLayout.custom)
            }
            .pickerStyle(.segmented)
            .padding()

            ZStack {
                if let img = frozen {
                    CalibrationView(image: img, imageSize: frozenSize, corners: $corners)
                    if showOverlay, let model = draft.courtModel() {
                        CourtOverlayView(model: model, imageSize: frozenSize)
                    }
                    tapTestCatcher
                } else {
                    ContentUnavailableView("Point at the court", systemImage: "camera.viewfinder")
                }
            }

            if let tr = tapResult {
                Text(tr).font(.callout).padding(8)
            }

            HStack {
                Button("Re-freeze") { freeze() }
                Spacer()
                Button(showOverlay ? "Hide court" : "Show court") { showOverlay.toggle() }
                    .disabled(!draft.isComplete)
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.courtModel() == nil)
            }
            .padding()
        }
        .navigationTitle("Calibrate")
        .onAppear { camera.start(); freeze() }
    }

    /// Transparent layer: tapping reads the court coordinate at that point.
    private var tapTestCatcher: some View {
        GeometryReader { geo in
            Color.clear.contentShape(Rectangle())
                .onTapGesture { location in
                    guard showOverlay, let model = draft.courtModel() else { return }
                    let mapper = AspectFillMapper(viewSize: geo.size, contentSize: frozenSize)
                    let n = mapper.imageNormalized(fromView: location)
                    let court = model.courtPoint(forImage: n)
                    let inBounds = model.isInBounds(courtPoint: court)
                    tapResult = String(format: "(%.1f, %.1f) ft · %@", court.x, court.y, inBounds ? "IN" : "OUT")
                }
        }
    }

    private func freeze() {
        if let img = camera.latestImage {
            frozen = img
            frozenSize = camera.imageSize
        }
    }

    private func save() {
        let cal = StoredCalibration(
            venueName: venueName,
            layout: layout,
            imageCorners: corners.map { CodablePoint($0) },
            customDimensions: nil,
            savedAt: Date()
        )
        try? store.save(cal)
        dismiss()
    }
}
```

- [ ] **Step 2: Add the entry point in `CameraScreen.swift`**

In `CameraScreen`'s `hud` (Task-6 of Plan 2), add a Calibrate button that pushes `CalibrationScreen(camera: camera)`. Replace the `hud`'s `HStack` closing so it includes a navigation entry. Concretely, wrap `CameraScreen`'s content so a toolbar/button can present it — add to the `.authorized` branch's `hud` a bottom button:

```swift
            // inside hud's VStack, after the top HStack and Spacer():
            NavigationLink {
                CalibrationScreen(camera: camera)
            } label: {
                Label("Calibrate court", systemImage: "scope")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(.bottom, 30)
```

(`CameraScreen` is already inside the `HomeView` `NavigationStack`, so `NavigationLink` works.)

- [ ] **Step 3: Build and confirm clean**

Build the `PickleVision` scheme. Expected: BUILD SUCCEEDED, zero warnings.

- [ ] **Step 4: Commit**

```bash
git add PickleVision/PickleVision/CalibrationScreen.swift PickleVision/PickleVision/CameraScreen.swift
git commit -m "feat(app): calibration flow — layout, drag, overlay, tap-test, save"
```

- [ ] **Step 5: On-device acceptance (USER)**

Run on the iPhone. Mount it behind the baseline. Verify:
1. Camera screen → tap **Calibrate court**.
2. The frame freezes; drag the four corners (NL/NR/FR/FL) onto the real court corners using the loupe.
3. Pick the layout (Pickleball or Tennis box).
4. Tap **Show court** — the green/red/yellow court overlay should sit on the real lines.
5. Tap a known spot (e.g., a corner, the centerline) → it reads a sensible court coordinate and IN/OUT.
6. Tap **Save**. Re-open calibration and confirm it can reload (a later refinement; for now confirm save doesn't error).

This on-device run is the real acceptance for this plan.

---

## Self-Review (coverage against the spec)

- **Spec §6 manual calibration (tap/drag + loupe)** → Tasks 4 (drag + loupe) + 1–2 (the coordinate + draft logic).
- **Spec §5 `CourtModel`/`CourtProfile` + profiles** → reused; layout picker in Task 6 (pickleball / tennis front-box / custom).
- **Spec §6 step 4 verify (overlay + tap-test)** → Tasks 5 (overlay) + 6 (tap-test).
- **Spec §4 `CalibrationStore` persistence** → Task 6 save (load-on-launch is a small follow-up flagged below).
- **Spec normalized-coords + resolution independence** → enforced via `AspectFillMapper` + normalized corners.

**Deferred (correctly out of scope here):** auto-detect (next plan, "Plan 3.5"); the guided setup *coaching* and the runtime *drift guard* (Plan 4); loading a saved calibration back into the live camera screen and re-calibrate-on-move (small follow-up — Task 6 saves; wiring load into `CameraScreen` is a Plan 3.5/4 item); preview/overlay orientation polish for landscape mount (revisit with real-court testing).

**Placeholder scan:** none — logic tasks have complete code + `swift test` gates; device tasks have complete code + build gates + an on-device acceptance.

**Type consistency:** `AspectFillMapper(viewSize:contentSize:)`, `CalibrationDraft(corners:layout:)` / `.courtModel()` / `.nearestCornerIndex(toView:handles:within:)`, `CourtModel.courtPoint(forImage:)` / `.imagePoint(forCourt:)` / `.isInBounds(courtPoint:)`, and `CalibrationStore.save(_:)` are used consistently across producing and consuming tasks.
