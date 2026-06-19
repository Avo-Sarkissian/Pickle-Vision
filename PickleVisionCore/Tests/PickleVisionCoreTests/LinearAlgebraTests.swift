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
