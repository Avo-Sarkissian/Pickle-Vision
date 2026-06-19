# PickleVisionCore (Calibration Logic Foundation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `PickleVisionCore`, a pure-Swift, fully unit-tested package providing the image↔court coordinate math, court layouts, calibration persistence, and drift-decision logic that every later Pickle Vision phase depends on.

**Architecture:** A standalone Swift Package (no app, no camera, no UI) so the whole foundation runs under `swift test` on a Mac with zero device dependency. It exposes one consumer-facing type, `CourtModel` (image↔court mapping + in-bounds test), built from a `Homography` solved out of four tapped corner correspondences and a `CourtProfile` (real-world court geometry). `CalibrationStore` persists/restores calibrations; `DriftDetector` makes the pause/keep-going decision from a motion signal the app layer measures.

**Tech Stack:** Swift 5.9+, Swift Package Manager, XCTest, `simd`, `CoreGraphics`, `Foundation`. **No third-party dependencies.**

This is **Plan 1 of 4** for Phase 0–1 (Foundation + Court Calibration). Spec: `docs/superpowers/specs/2026-06-19-foundation-court-calibration-design.md`. Plans 2–4 (camera, calibration UI, drift guard) consume this package and are device-tested.

## Global Constraints

- **Platforms:** `swift-tools-version: 5.9`; package platforms `iOS(.v16)`, `macOS(.v13)`. Tests run on macOS.
- **No third-party dependencies** in `PickleVisionCore` — Foundation, simd, CoreGraphics only.
- **Court coordinate convention (load-bearing across all tasks):** court coordinates are in **feet**, origin at the **near-left corner** (the baseline nearest the camera, looking onto the court). `x` increases to the **right** across the court **width**; `y` increases **away from the camera** along the court **length** toward the far baseline. Corner order everywhere is `[nearLeft, nearRight, farRight, farLeft]` = `[(0,0), (w,0), (w,l), (0,l)]`.
- **Homography direction:** a `Homography` stored in a `CourtModel` always maps **image → court**. Its `inverse` maps court → image.
- **TDD:** every type is introduced test-first. Commit after each green task.
- All commands run from the repo root: `/Users/avosarkissian/Documents/VS Code/Pickle Vision`.

---

## File Structure

```
PickleVisionCore/
  Package.swift
  Sources/PickleVisionCore/
    PickleVisionCore.swift     # package version constant (smoke)
    LinearAlgebra.swift        # solveLinearSystem (Gaussian elimination)
    Homography.swift           # Homography: build from 4 points, project, inverse
    CourtProfile.swift         # CourtLayout, CustomDimensions, CourtProfile
    CourtModel.swift           # CourtModel: image↔court mapping + in-bounds
    CalibrationStore.swift     # CodablePoint, StoredCalibration, CalibrationStore
    DriftDetector.swift        # DriftState, DriftDetector
  Tests/PickleVisionCoreTests/
    SmokeTests.swift
    LinearAlgebraTests.swift
    HomographyTests.swift
    CourtProfileTests.swift
    CourtModelTests.swift
    CalibrationStoreTests.swift
    DriftDetectorTests.swift
```

Each `.swift` source file has one responsibility; tests mirror sources one-to-one.

---

### Task 1: Package scaffold + smoke test

**Files:**
- Create: `PickleVisionCore/Package.swift`
- Create: `PickleVisionCore/Sources/PickleVisionCore/PickleVisionCore.swift`
- Test: `PickleVisionCore/Tests/PickleVisionCoreTests/SmokeTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: the `PickleVisionCore` module with `public enum PickleVisionCore { public static let version }`.

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PickleVisionCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "PickleVisionCore", targets: ["PickleVisionCore"]),
    ],
    targets: [
        .target(name: "PickleVisionCore"),
        .testTarget(name: "PickleVisionCoreTests", dependencies: ["PickleVisionCore"]),
    ]
)
```

- [ ] **Step 2: Create the source placeholder**

`PickleVisionCore/Sources/PickleVisionCore/PickleVisionCore.swift`:

```swift
/// Namespace + version marker for the Pickle Vision logic core.
public enum PickleVisionCore {
    public static let version = "0.1.0"
}
```

- [ ] **Step 3: Write the smoke test**

`PickleVisionCore/Tests/PickleVisionCoreTests/SmokeTests.swift`:

```swift
import XCTest
@testable import PickleVisionCore

final class SmokeTests: XCTestCase {
    func test_version_isPresent() {
        XCTAssertEqual(PickleVisionCore.version, "0.1.0")
    }
}
```

- [ ] **Step 4: Run the test suite**

Run: `swift test --package-path PickleVisionCore`
Expected: builds, `Test Suite 'SmokeTests' passed`, 1 test, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add PickleVisionCore
git commit -m "feat(core): scaffold PickleVisionCore swift package"
```

---

### Task 2: Linear system solver

**Files:**
- Create: `PickleVisionCore/Sources/PickleVisionCore/LinearAlgebra.swift`
- Test: `PickleVisionCore/Tests/PickleVisionCoreTests/LinearAlgebraTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `func solveLinearSystem(_ a: [[Double]], _ b: [Double]) -> [Double]?` — solves `A·x = b` for a square dense system; returns `nil` if singular or shape-mismatched.

- [ ] **Step 1: Write the failing tests**

`LinearAlgebraTests.swift`:

```swift
import XCTest
@testable import PickleVisionCore

final class LinearAlgebraTests: XCTestCase {
    func test_solves_2x2_system() {
        // 2x + y = 5 ; x - y = 1  -> x = 2, y = 1
        let x = solveLinearSystem([[2, 1], [1, -1]], [5, 1])
        let r = try! XCTUnwrap(x)
        XCTAssertEqual(r[0], 2, accuracy: 1e-9)
        XCTAssertEqual(r[1], 1, accuracy: 1e-9)
    }

    func test_requires_partial_pivot() {
        // First pivot is zero; solver must swap rows.
        // 0x + 1y = 2 ; 1x + 1y = 3 -> x = 1, y = 2
        let x = solveLinearSystem([[0, 1], [1, 1]], [2, 3])
        let r = try! XCTUnwrap(x)
        XCTAssertEqual(r[0], 1, accuracy: 1e-9)
        XCTAssertEqual(r[1], 2, accuracy: 1e-9)
    }

    func test_singular_returns_nil() {
        XCTAssertNil(solveLinearSystem([[1, 2], [2, 4]], [3, 6]))
    }

    func test_shape_mismatch_returns_nil() {
        XCTAssertNil(solveLinearSystem([[1, 2]], [3, 4]))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path PickleVisionCore --filter LinearAlgebraTests`
Expected: FAIL — `cannot find 'solveLinearSystem' in scope`.

- [ ] **Step 3: Implement the solver**

`LinearAlgebra.swift`:

```swift
import Foundation

/// Solves the dense square linear system `A·x = b` via Gaussian elimination
/// with partial pivoting. Returns `nil` if `A` is not square, the shapes
/// disagree, or the system is singular.
func solveLinearSystem(_ a: [[Double]], _ b: [Double]) -> [Double]? {
    let n = b.count
    guard a.count == n, a.allSatisfy({ $0.count == n }) else { return nil }

    var m = a
    var rhs = b

    for col in 0..<n {
        // Partial pivot: find the largest-magnitude entry in this column.
        var pivotRow = col
        var maxVal = abs(m[col][col])
        for r in (col + 1)..<n {
            let v = abs(m[r][col])
            if v > maxVal { maxVal = v; pivotRow = r }
        }
        if maxVal < 1e-12 { return nil }
        if pivotRow != col {
            m.swapAt(col, pivotRow)
            rhs.swapAt(col, pivotRow)
        }

        // Eliminate below the pivot.
        let pivot = m[col][col]
        for r in (col + 1)..<n {
            let factor = m[r][col] / pivot
            if factor == 0 { continue }
            for c in col..<n {
                m[r][c] -= factor * m[col][c]
            }
            rhs[r] -= factor * rhs[col]
        }
    }

    // Back-substitution.
    var x = [Double](repeating: 0, count: n)
    for row in stride(from: n - 1, through: 0, by: -1) {
        var sum = rhs[row]
        for c in (row + 1)..<n {
            sum -= m[row][c] * x[c]
        }
        x[row] = sum / m[row][row]
    }
    return x
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path PickleVisionCore --filter LinearAlgebraTests`
Expected: PASS — 4 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add PickleVisionCore
git commit -m "feat(core): add Gaussian-elimination linear solver"
```

---

### Task 3: Homography

**Files:**
- Create: `PickleVisionCore/Sources/PickleVisionCore/Homography.swift`
- Test: `PickleVisionCore/Tests/PickleVisionCoreTests/HomographyTests.swift`

**Interfaces:**
- Consumes: `solveLinearSystem` (Task 2).
- Produces:
  - `struct Homography` with `let matrix: simd_double3x3`
  - `init?(source: [CGPoint], destination: [CGPoint])` — exactly 4 each, maps source→destination; `nil` if degenerate.
  - `func project(_ p: CGPoint) -> CGPoint`
  - `var inverse: Homography?`

- [ ] **Step 1: Write the failing tests**

`HomographyTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class HomographyTests: XCTestCase {
    // A perspective-ish image trapezoid mapped to a 20x44 court rectangle.
    private let imageCorners = [
        CGPoint(x: 45,  y: 172),  // nearLeft
        CGPoint(x: 275, y: 172),  // nearRight
        CGPoint(x: 200, y: 48),   // farRight
        CGPoint(x: 120, y: 48),   // farLeft
    ]
    private let courtCorners = [
        CGPoint(x: 0,  y: 0),
        CGPoint(x: 20, y: 0),
        CGPoint(x: 20, y: 44),
        CGPoint(x: 0,  y: 44),
    ]

    func test_maps_each_corner_to_its_destination() {
        let h = try! XCTUnwrap(Homography(source: imageCorners, destination: courtCorners))
        for (img, court) in zip(imageCorners, courtCorners) {
            let p = h.project(img)
            XCTAssertEqual(p.x, court.x, accuracy: 1e-6)
            XCTAssertEqual(p.y, court.y, accuracy: 1e-6)
        }
    }

    func test_inverse_round_trips_arbitrary_points() {
        let h = try! XCTUnwrap(Homography(source: imageCorners, destination: courtCorners))
        let inv = try! XCTUnwrap(h.inverse)
        for img in [CGPoint(x: 150, y: 120), CGPoint(x: 210, y: 90), CGPoint(x: 100, y: 160)] {
            let court = h.project(img)
            let back = inv.project(court)
            XCTAssertEqual(back.x, img.x, accuracy: 1e-6)
            XCTAssertEqual(back.y, img.y, accuracy: 1e-6)
        }
    }

    func test_wrong_point_count_returns_nil() {
        XCTAssertNil(Homography(source: Array(imageCorners.prefix(3)), destination: courtCorners))
    }

    func test_degenerate_collinear_source_returns_nil() {
        let collinear = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
                         CGPoint(x: 2, y: 0), CGPoint(x: 3, y: 0)]
        XCTAssertNil(Homography(source: collinear, destination: courtCorners))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path PickleVisionCore --filter HomographyTests`
Expected: FAIL — `cannot find 'Homography' in scope`.

- [ ] **Step 3: Implement `Homography`**

`Homography.swift`:

```swift
import simd
import CoreGraphics

/// A planar projective transform. The matrix maps homogeneous source
/// coordinates to destination coordinates: `dest ~ matrix * [x, y, 1]`.
public struct Homography: Equatable {
    public let matrix: simd_double3x3

    public init(matrix: simd_double3x3) {
        self.matrix = matrix
    }

    /// Builds a homography from exactly four source→destination correspondences
    /// using the Direct Linear Transform (8 unknowns, h33 fixed to 1).
    /// Returns `nil` if there are not four pairs or the configuration is degenerate.
    public init?(source: [CGPoint], destination: [CGPoint]) {
        guard source.count == 4, destination.count == 4 else { return nil }

        var a = [[Double]]()
        var b = [Double]()
        for i in 0..<4 {
            let x = Double(source[i].x), y = Double(source[i].y)
            let X = Double(destination[i].x), Y = Double(destination[i].y)
            a.append([x, y, 1, 0, 0, 0, -x * X, -y * X]); b.append(X)
            a.append([0, 0, 0, x, y, 1, -x * Y, -y * Y]); b.append(Y)
        }
        guard let h = solveLinearSystem(a, b) else { return nil }

        // simd_double3x3 is column-major: columns(col0, col1, col2).
        let col0 = SIMD3<Double>(h[0], h[3], h[6])  // (h11, h21, h31)
        let col1 = SIMD3<Double>(h[1], h[4], h[7])  // (h12, h22, h32)
        let col2 = SIMD3<Double>(h[2], h[5], 1)     // (h13, h23, h33=1)
        let m = simd_double3x3(columns: (col0, col1, col2))

        if abs(m.determinant) < 1e-12 { return nil }
        self.matrix = m
    }

    /// Projects a point through the homography.
    public func project(_ p: CGPoint) -> CGPoint {
        let v = SIMD3<Double>(Double(p.x), Double(p.y), 1)
        let r = matrix * v
        return CGPoint(x: r.x / r.z, y: r.y / r.z)
    }

    /// The inverse transform, or `nil` if the matrix is non-invertible.
    public var inverse: Homography? {
        if abs(matrix.determinant) < 1e-12 { return nil }
        return Homography(matrix: matrix.inverse)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path PickleVisionCore --filter HomographyTests`
Expected: PASS — 4 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add PickleVisionCore
git commit -m "feat(core): add 4-point DLT homography with inverse"
```

---

### Task 4: Court profiles

**Files:**
- Create: `PickleVisionCore/Sources/PickleVisionCore/CourtProfile.swift`
- Test: `PickleVisionCore/Tests/PickleVisionCoreTests/CourtProfileTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum CourtLayout: String, Codable { case regulationPickleball, tennisFrontBox, custom }`
  - `struct CustomDimensions: Codable, Equatable { var widthFeet; var lengthFeet; var nonVolleyZoneFeet }`
  - `struct CourtProfile: Equatable` with `layout, widthFeet, lengthFeet, nonVolleyZoneFeet, calibrationCorners: [CGPoint], inBoundsPolygon: [CGPoint], netLine: [CGPoint], nvzLines: [[CGPoint]]`
  - `static func make(layout: CourtLayout, custom: CustomDimensions? = nil) -> CourtProfile`

- [ ] **Step 1: Write the failing tests**

`CourtProfileTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class CourtProfileTests: XCTestCase {
    func test_pickleball_dimensions_and_corners() {
        let p = CourtProfile.make(layout: .regulationPickleball)
        XCTAssertEqual(p.widthFeet, 20)
        XCTAssertEqual(p.lengthFeet, 44)
        XCTAssertEqual(p.nonVolleyZoneFeet, 7)
        XCTAssertEqual(p.calibrationCorners,
                       [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0),
                        CGPoint(x: 20, y: 44), CGPoint(x: 0, y: 44)])
    }

    func test_pickleball_net_and_nvz_lines() {
        let p = CourtProfile.make(layout: .regulationPickleball)
        XCTAssertEqual(p.netLine, [CGPoint(x: 0, y: 22), CGPoint(x: 20, y: 22)])
        XCTAssertEqual(p.nvzLines.count, 2)
        XCTAssertEqual(p.nvzLines[0], [CGPoint(x: 0, y: 15), CGPoint(x: 20, y: 15)])
        XCTAssertEqual(p.nvzLines[1], [CGPoint(x: 0, y: 29), CGPoint(x: 20, y: 29)])
    }

    func test_tennis_front_box_dimensions() {
        let p = CourtProfile.make(layout: .tennisFrontBox)
        XCTAssertEqual(p.widthFeet, 27)
        XCTAssertEqual(p.lengthFeet, 42)
        XCTAssertEqual(p.netLine, [CGPoint(x: 0, y: 21), CGPoint(x: 27, y: 21)])
    }

    func test_custom_uses_supplied_dimensions() {
        let p = CourtProfile.make(layout: .custom,
                                  custom: CustomDimensions(widthFeet: 24, lengthFeet: 50, nonVolleyZoneFeet: 6))
        XCTAssertEqual(p.widthFeet, 24)
        XCTAssertEqual(p.lengthFeet, 50)
        XCTAssertEqual(p.netLine, [CGPoint(x: 0, y: 25), CGPoint(x: 24, y: 25)])
        XCTAssertEqual(p.nvzLines[0], [CGPoint(x: 0, y: 19), CGPoint(x: 24, y: 19)])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path PickleVisionCore --filter CourtProfileTests`
Expected: FAIL — `cannot find 'CourtProfile' in scope`.

- [ ] **Step 3: Implement profiles**

`CourtProfile.swift`:

```swift
import CoreGraphics

public enum CourtLayout: String, Codable {
    case regulationPickleball
    case tennisFrontBox
    case custom
}

public struct CustomDimensions: Codable, Equatable {
    public var widthFeet: Double
    public var lengthFeet: Double
    public var nonVolleyZoneFeet: Double

    public init(widthFeet: Double, lengthFeet: Double, nonVolleyZoneFeet: Double) {
        self.widthFeet = widthFeet
        self.lengthFeet = lengthFeet
        self.nonVolleyZoneFeet = nonVolleyZoneFeet
    }
}

/// Real-world geometry for a supported court layout, in feet, using the
/// near-left-origin convention (see plan Global Constraints).
public struct CourtProfile: Equatable {
    public let layout: CourtLayout
    public let widthFeet: Double
    public let lengthFeet: Double
    public let nonVolleyZoneFeet: Double
    /// [nearLeft, nearRight, farRight, farLeft].
    public let calibrationCorners: [CGPoint]
    public let inBoundsPolygon: [CGPoint]
    public let netLine: [CGPoint]        // two endpoints
    public let nvzLines: [[CGPoint]]     // each two endpoints

    public static func make(layout: CourtLayout, custom: CustomDimensions? = nil) -> CourtProfile {
        switch layout {
        case .regulationPickleball:
            return CourtProfile(width: 20, length: 44, nvz: 7, layout: .regulationPickleball)
        case .tennisFrontBox:
            return CourtProfile(width: 27, length: 42, nvz: 7, layout: .tennisFrontBox)
        case .custom:
            let d = custom ?? CustomDimensions(widthFeet: 20, lengthFeet: 44, nonVolleyZoneFeet: 7)
            return CourtProfile(width: d.widthFeet, length: d.lengthFeet, nvz: d.nonVolleyZoneFeet, layout: .custom)
        }
    }

    private init(width w: Double, length l: Double, nvz: Double, layout: CourtLayout) {
        self.layout = layout
        self.widthFeet = w
        self.lengthFeet = l
        self.nonVolleyZoneFeet = nvz

        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: w, y: 0),
                       CGPoint(x: w, y: l), CGPoint(x: 0, y: l)]
        self.calibrationCorners = corners
        self.inBoundsPolygon = corners

        let mid = l / 2
        self.netLine = [CGPoint(x: 0, y: mid), CGPoint(x: w, y: mid)]
        self.nvzLines = [
            [CGPoint(x: 0, y: mid - nvz), CGPoint(x: w, y: mid - nvz)],
            [CGPoint(x: 0, y: mid + nvz), CGPoint(x: w, y: mid + nvz)],
        ]
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path PickleVisionCore --filter CourtProfileTests`
Expected: PASS — 4 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add PickleVisionCore
git commit -m "feat(core): add court profiles (pickleball, tennis front-box, custom)"
```

---

### Task 5: CourtModel (image↔court mapping + in-bounds)

**Files:**
- Create: `PickleVisionCore/Sources/PickleVisionCore/CourtModel.swift`
- Test: `PickleVisionCore/Tests/PickleVisionCoreTests/CourtModelTests.swift`

**Interfaces:**
- Consumes: `Homography` (Task 3), `CourtProfile` (Task 4).
- Produces:
  - `struct CourtModel` with `let profile: CourtProfile`, `let homography: Homography` (image→court)
  - `init(profile:homography:)`
  - `func courtPoint(forImage p: CGPoint) -> CGPoint`
  - `func imagePoint(forCourt p: CGPoint) -> CGPoint?`
  - `func isInBounds(courtPoint p: CGPoint) -> Bool`

- [ ] **Step 1: Write the failing tests**

`CourtModelTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class CourtModelTests: XCTestCase {
    private func makeModel() -> CourtModel {
        let profile = CourtProfile.make(layout: .regulationPickleball)
        let imageCorners = [
            CGPoint(x: 45, y: 172), CGPoint(x: 275, y: 172),
            CGPoint(x: 200, y: 48), CGPoint(x: 120, y: 48),
        ]
        let h = Homography(source: imageCorners, destination: profile.calibrationCorners)!
        return CourtModel(profile: profile, homography: h)
    }

    func test_image_corner_maps_to_court_origin() {
        let model = makeModel()
        let c = model.courtPoint(forImage: CGPoint(x: 45, y: 172))
        XCTAssertEqual(c.x, 0, accuracy: 1e-6)
        XCTAssertEqual(c.y, 0, accuracy: 1e-6)
    }

    func test_court_to_image_round_trip() {
        let model = makeModel()
        let img = try! XCTUnwrap(model.imagePoint(forCourt: CGPoint(x: 20, y: 44)))
        XCTAssertEqual(img.x, 200, accuracy: 1e-6)
        XCTAssertEqual(img.y, 48, accuracy: 1e-6)
    }

    func test_in_bounds_point() {
        let model = makeModel()
        XCTAssertTrue(model.isInBounds(courtPoint: CGPoint(x: 10, y: 22)))
    }

    func test_out_of_bounds_point() {
        let model = makeModel()
        XCTAssertFalse(model.isInBounds(courtPoint: CGPoint(x: 21, y: 22))) // past sideline
        XCTAssertFalse(model.isInBounds(courtPoint: CGPoint(x: 10, y: 45))) // past baseline
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path PickleVisionCore --filter CourtModelTests`
Expected: FAIL — `cannot find 'CourtModel' in scope`.

- [ ] **Step 3: Implement `CourtModel`**

`CourtModel.swift`:

```swift
import CoreGraphics

/// The calibrated court — the single interface every later Pickle Vision phase
/// consumes. Wraps an image→court homography plus the court's real-world geometry.
public struct CourtModel {
    public let profile: CourtProfile
    /// Maps image (pixel) coordinates to court (feet) coordinates.
    public let homography: Homography

    public init(profile: CourtProfile, homography: Homography) {
        self.profile = profile
        self.homography = homography
    }

    /// Court (feet) coordinate for a point in the image.
    public func courtPoint(forImage p: CGPoint) -> CGPoint {
        homography.project(p)
    }

    /// Image (pixel) coordinate for a point on the court, or `nil` if the
    /// homography is non-invertible.
    public func imagePoint(forCourt p: CGPoint) -> CGPoint? {
        homography.inverse?.project(p)
    }

    /// Whether a court-space point lies inside the in-bounds polygon.
    public func isInBounds(courtPoint p: CGPoint) -> Bool {
        Self.pointInPolygon(p, profile.inBoundsPolygon)
    }

    /// Ray-casting point-in-polygon test.
    static func pointInPolygon(_ p: CGPoint, _ poly: [CGPoint]) -> Bool {
        guard poly.count >= 3 else { return false }
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let pi = poly[i], pj = poly[j]
            if ((pi.y > p.y) != (pj.y > p.y)) &&
               (p.x < (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y) + pi.x) {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path PickleVisionCore --filter CourtModelTests`
Expected: PASS — 4 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add PickleVisionCore
git commit -m "feat(core): add CourtModel image<->court mapping and in-bounds test"
```

---

### Task 6: Calibration persistence

**Files:**
- Create: `PickleVisionCore/Sources/PickleVisionCore/CalibrationStore.swift`
- Test: `PickleVisionCore/Tests/PickleVisionCoreTests/CalibrationStoreTests.swift`

**Interfaces:**
- Consumes: `CourtLayout`, `CustomDimensions`, `CourtProfile` (Task 4), `Homography` (Task 3), `CourtModel` (Task 5).
- Produces:
  - `struct CodablePoint: Codable, Equatable` with `init(_ CGPoint)`, `init(x:y:)`, `var cgPoint`
  - `struct StoredCalibration: Codable, Equatable` with `venueName, layout, imageCorners: [CodablePoint], customDimensions: CustomDimensions?, savedAt: Date`
  - `final class CalibrationStore` with `init(directory: URL)`, `func save(_:) throws`, `func load(venueName:) throws -> StoredCalibration?`, `func courtModel(from:) -> CourtModel?`

- [ ] **Step 1: Write the failing tests**

`CalibrationStoreTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import PickleVisionCore

final class CalibrationStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pvcore-tests-" + UUID().uuidString)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func sample() -> StoredCalibration {
        StoredCalibration(
            venueName: "Home Court",
            layout: .regulationPickleball,
            imageCorners: [
                CodablePoint(x: 45, y: 172), CodablePoint(x: 275, y: 172),
                CodablePoint(x: 200, y: 48), CodablePoint(x: 120, y: 48),
            ],
            customDimensions: nil,
            savedAt: Date(timeIntervalSince1970: 1_000_000)
        )
    }

    func test_save_then_load_round_trips() throws {
        let store = CalibrationStore(directory: dir)
        let cal = sample()
        try store.save(cal)
        let loaded = try XCTUnwrap(store.load(venueName: "Home Court"))
        XCTAssertEqual(loaded, cal)
    }

    func test_load_missing_returns_nil() throws {
        let store = CalibrationStore(directory: dir)
        XCTAssertNil(try store.load(venueName: "Nowhere"))
    }

    func test_rebuilds_court_model_from_stored_calibration() throws {
        let store = CalibrationStore(directory: dir)
        let model = try XCTUnwrap(store.courtModel(from: sample()))
        let origin = model.courtPoint(forImage: CGPoint(x: 45, y: 172))
        XCTAssertEqual(origin.x, 0, accuracy: 1e-6)
        XCTAssertEqual(origin.y, 0, accuracy: 1e-6)
        XCTAssertEqual(model.profile.layout, .regulationPickleball)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path PickleVisionCore --filter CalibrationStoreTests`
Expected: FAIL — `cannot find 'CalibrationStore' in scope`.

- [ ] **Step 3: Implement persistence**

`CalibrationStore.swift`:

```swift
import Foundation
import CoreGraphics

/// A `Codable` 2D point (CGPoint persistence kept explicit and portable).
public struct CodablePoint: Codable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public init(_ p: CGPoint) { self.x = Double(p.x); self.y = Double(p.y) }
    public var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

/// A persisted court calibration. Stores the tapped image corners and the
/// layout, not the homography — the homography is recomputed on load, which
/// keeps the format tiny and re-derives from source of truth.
public struct StoredCalibration: Codable, Equatable {
    public var venueName: String
    public var layout: CourtLayout
    public var imageCorners: [CodablePoint]   // [nearLeft, nearRight, farRight, farLeft]
    public var customDimensions: CustomDimensions?
    public var savedAt: Date

    public init(venueName: String, layout: CourtLayout, imageCorners: [CodablePoint],
                customDimensions: CustomDimensions?, savedAt: Date) {
        self.venueName = venueName
        self.layout = layout
        self.imageCorners = imageCorners
        self.customDimensions = customDimensions
        self.savedAt = savedAt
    }
}

/// Saves and restores `StoredCalibration`s as JSON files in a directory, and
/// rebuilds a `CourtModel` from one.
public final class CalibrationStore {
    private let directory: URL
    private let fileManager = FileManager.default

    public init(directory: URL) {
        self.directory = directory
    }

    private func url(forVenue venue: String) -> URL {
        let safe = venue.replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent("\(safe).json")
    }

    public func save(_ calibration: StoredCalibration) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(calibration)
        try data.write(to: url(forVenue: calibration.venueName), options: .atomic)
    }

    public func load(venueName: String) throws -> StoredCalibration? {
        let u = url(forVenue: venueName)
        guard fileManager.fileExists(atPath: u.path) else { return nil }
        let data = try Data(contentsOf: u)
        return try JSONDecoder().decode(StoredCalibration.self, from: data)
    }

    /// Recomputes a live `CourtModel` from a stored calibration, or `nil` if
    /// the corners are degenerate.
    public func courtModel(from calibration: StoredCalibration) -> CourtModel? {
        let profile = CourtProfile.make(layout: calibration.layout,
                                        custom: calibration.customDimensions)
        let image = calibration.imageCorners.map { $0.cgPoint }
        guard let h = Homography(source: image, destination: profile.calibrationCorners) else {
            return nil
        }
        return CourtModel(profile: profile, homography: h)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path PickleVisionCore --filter CalibrationStoreTests`
Expected: PASS — 3 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add PickleVisionCore
git commit -m "feat(core): add calibration persistence and CourtModel rebuild"
```

---

### Task 7: Drift-decision logic

**Files:**
- Create: `PickleVisionCore/Sources/PickleVisionCore/DriftDetector.swift`
- Test: `PickleVisionCore/Tests/PickleVisionCoreTests/DriftDetectorTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum DriftState: Equatable { case stable, drifted }`
  - `struct DriftDetector` with `init(translationThreshold: Double = 12, rotationThreshold: Double = 0.02)` and `func evaluate(translation: Double, rotationRadians: Double) -> DriftState`

The drift detector is pure decision logic: the app layer (Plan 4) measures frame-to-frame translation (pixels) and rotation (radians) via Vision image registration, then asks this type whether the camera has moved enough to pause calls.

- [ ] **Step 1: Write the failing tests**

`DriftDetectorTests.swift`:

```swift
import XCTest
@testable import PickleVisionCore

final class DriftDetectorTests: XCTestCase {
    func test_small_motion_is_stable() {
        let d = DriftDetector(translationThreshold: 12, rotationThreshold: 0.02)
        XCTAssertEqual(d.evaluate(translation: 5, rotationRadians: 0.005), .stable)
    }

    func test_large_translation_is_drift() {
        let d = DriftDetector(translationThreshold: 12, rotationThreshold: 0.02)
        XCTAssertEqual(d.evaluate(translation: 20, rotationRadians: 0), .drifted)
    }

    func test_large_rotation_is_drift() {
        let d = DriftDetector(translationThreshold: 12, rotationThreshold: 0.02)
        XCTAssertEqual(d.evaluate(translation: 0, rotationRadians: -0.05), .drifted)
    }

    func test_threshold_is_inclusive() {
        let d = DriftDetector(translationThreshold: 12, rotationThreshold: 0.02)
        XCTAssertEqual(d.evaluate(translation: 12, rotationRadians: 0), .drifted)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path PickleVisionCore --filter DriftDetectorTests`
Expected: FAIL — `cannot find 'DriftDetector' in scope`.

- [ ] **Step 3: Implement `DriftDetector`**

`DriftDetector.swift`:

```swift
import Foundation

public enum DriftState: Equatable {
    case stable
    case drifted
}

/// Decides whether the camera has moved enough to invalidate the calibration.
/// Thresholds are compared inclusively, so a measurement exactly at the
/// threshold counts as drift.
public struct DriftDetector {
    public let translationThreshold: Double   // pixels
    public let rotationThreshold: Double       // radians

    public init(translationThreshold: Double = 12, rotationThreshold: Double = 0.02) {
        self.translationThreshold = translationThreshold
        self.rotationThreshold = rotationThreshold
    }

    public func evaluate(translation: Double, rotationRadians: Double) -> DriftState {
        if translation >= translationThreshold || abs(rotationRadians) >= rotationThreshold {
            return .drifted
        }
        return .stable
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path PickleVisionCore --filter DriftDetectorTests`
Expected: PASS — 4 tests, 0 failures.

- [ ] **Step 5: Run the full suite and commit**

Run: `swift test --package-path PickleVisionCore`
Expected: all suites pass (Smoke, LinearAlgebra, Homography, CourtProfile, CourtModel, CalibrationStore, DriftDetector).

```bash
git add PickleVisionCore
git commit -m "feat(core): add drift-decision logic"
```

---

## Self-Review (coverage against the spec)

This plan implements the **logic foundation** portion of the Foundation + Calibration spec. Mapping to spec sections:

- **§4 `HomographySolver`** → Tasks 2–3 (`solveLinearSystem`, `Homography`).
- **§5 `CourtModel`** (image↔court mapping, in-bounds polygon) → Task 5.
- **§5 `CourtProfile`** (regulation pickleball, tennis front-box w/ virtual NVZ, custom) → Task 4.
- **§5 net line + NVZ lines incl. virtual kitchen** → Task 4 (computed for every layout, including tennis front-box which has no painted NVZ).
- **§4/§6 `CalibrationStore`** (persist per venue, rebuild model) → Task 6.
- **§6 drift guard — decision half** → Task 7 (`DriftDetector`). The measurement half (Vision image registration) is Plan 4.

**Deferred to later plans (correctly out of scope here):** `CameraService` (Plan 2), `CourtAutoDetector` / `StabilityCheck` / `ManualAdjust` / `LensCalibration` / `SetupCoordinator` (Plans 2–4), all SwiftUI views and `CourtOverlayView` (Plans 3–4), the on-device acceptance test (Plans 2–4). These are device-bound and intentionally excluded from this headless, fully-TDD core.

**Placeholder scan:** none — every step has complete, runnable code and an exact command with expected output.

**Type consistency:** `Homography(source:destination:)`, `CourtProfile.make(layout:custom:)`, `CourtModel(profile:homography:)`, `courtPoint(forImage:)`, `imagePoint(forCourt:)`, `CalibrationStore.courtModel(from:)`, and `DriftDetector.evaluate(translation:rotationRadians:)` are used identically in their producing tasks and consuming tasks.
