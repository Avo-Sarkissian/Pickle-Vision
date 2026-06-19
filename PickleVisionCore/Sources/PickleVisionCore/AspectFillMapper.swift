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
