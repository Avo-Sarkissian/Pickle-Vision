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
