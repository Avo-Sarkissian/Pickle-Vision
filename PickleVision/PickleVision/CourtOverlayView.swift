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
            ZStack {
                inBoundsPath(mapper).stroke(Color.green, lineWidth: 2)

                ForEach(model.profile.nvzLines.indices, id: \.self) { i in
                    segment(model.profile.nvzLines[i][0], model.profile.nvzLines[i][1], mapper)
                        .stroke(Color.yellow, lineWidth: 1.5)
                }

                segment(model.profile.netLine[0], model.profile.netLine[1], mapper)
                    .stroke(Color.red, lineWidth: 2.5)
            }
        }
        .allowsHitTesting(false)
    }

    private func toView(_ court: CGPoint, _ mapper: AspectFillMapper) -> CGPoint? {
        guard let n = model.imagePoint(forCourt: court) else { return nil }
        return mapper.view(fromImageNormalized: n)
    }

    private func segment(_ a: CGPoint, _ b: CGPoint, _ mapper: AspectFillMapper) -> Path {
        var p = Path()
        if let va = toView(a, mapper), let vb = toView(b, mapper) { p.move(to: va); p.addLine(to: vb) }
        return p
    }

    private func inBoundsPath(_ mapper: AspectFillMapper) -> Path {
        var p = Path()
        let poly = model.profile.inBoundsPolygon.compactMap { toView($0, mapper) }
        if poly.count == model.profile.inBoundsPolygon.count {
            p.move(to: poly[0]); poly.dropFirst().forEach { p.addLine(to: $0) }; p.closeSubpath()
        }
        return p
    }
}
