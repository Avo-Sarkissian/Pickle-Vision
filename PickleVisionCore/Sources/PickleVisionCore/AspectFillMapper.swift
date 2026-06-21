import CoreGraphics

/// Maps points between a view that renders content with aspect-fill (scaled to
/// fill, overflow cropped) and normalized image coordinates in `[0,1]`,
/// where `(0,0)` is the image's top-left.
public struct AspectFillMapper {
    public let viewSize: CGSize
    public let contentSize: CGSize
    private let scale: CGFloat
    private let offset: CGPoint
    private let valid: Bool

    public init(viewSize: CGSize, contentSize: CGSize) {
        self.viewSize = viewSize
        self.contentSize = contentSize
        if viewSize.width > 0, viewSize.height > 0, contentSize.width > 0, contentSize.height > 0 {
            let s = max(viewSize.width / contentSize.width,
                        viewSize.height / contentSize.height)
            self.scale = s
            // Centered; offsets are <= 0 because the scaled content overflows.
            self.offset = CGPoint(x: (viewSize.width - contentSize.width * s) / 2,
                                  y: (viewSize.height - contentSize.height * s) / 2)
            self.valid = true
        } else {
            // Degenerate (zero) size - avoid inf/nan; map to a harmless center.
            self.scale = 1
            self.offset = .zero
            self.valid = false
        }
    }

    /// View point → normalized image coordinate.
    public func imageNormalized(fromView p: CGPoint) -> CGPoint {
        guard valid else { return CGPoint(x: 0.5, y: 0.5) }
        let imgX = (p.x - offset.x) / scale
        let imgY = (p.y - offset.y) / scale
        return CGPoint(x: imgX / contentSize.width, y: imgY / contentSize.height)
    }

    /// Normalized image coordinate → view point.
    public func view(fromImageNormalized n: CGPoint) -> CGPoint {
        guard valid else { return CGPoint(x: viewSize.width / 2, y: viewSize.height / 2) }
        let imgX = n.x * contentSize.width
        let imgY = n.y * contentSize.height
        return CGPoint(x: imgX * scale + offset.x, y: imgY * scale + offset.y)
    }
}
