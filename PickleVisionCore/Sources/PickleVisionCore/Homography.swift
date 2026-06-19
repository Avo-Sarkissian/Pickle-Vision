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
