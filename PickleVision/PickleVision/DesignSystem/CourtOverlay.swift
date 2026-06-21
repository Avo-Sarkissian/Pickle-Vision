import SwiftUI
import PickleVisionCore

/// Reusable zone-colored court overlay.
/// In-bounds = blue fill (low alpha); apron = green fill; all lines = optic-yellow
/// (per handoff: the overlay never draws blue/green LINES so it contrasts the real court).
/// Vector only - Path/Shape, never raster.
struct CourtOverlay: View {
    let model: CourtModel
    let imageSize: CGSize
    var lineWidth: CGFloat = 2.5
    var opacity: Double = 1.0
    var showFills: Bool = true

    var body: some View {
        GeometryReader { geo in
            let mapper = AspectFillMapper(viewSize: geo.size, contentSize: imageSize)
            let inBounds = inBoundsViewPath(mapper)
            ZStack {
                if showFills, let inBounds {
                    // Green apron = whole view with the in-bounds polygon punched out (even-odd).
                    apronPath(viewSize: geo.size, inBounds: inBounds)
                        .fill(PVColor.outBoundsFill, style: FillStyle(eoFill: true))
                    // Blue in-bounds fill.
                    inBounds.fill(PVColor.inBoundsFill)
                }
                // Optic-yellow outline.
                if let inBounds {
                    inBounds.stroke(PVColor.optic, lineWidth: lineWidth)
                }
                // NVZ (kitchen) lines.
                ForEach(model.profile.nvzLines.indices, id: \.self) { i in
                    segment(model.profile.nvzLines[i][0], model.profile.nvzLines[i][1], mapper)
                        .stroke(PVColor.optic, lineWidth: max(1, lineWidth - 1))
                }
                // Net line (slightly heavier).
                segment(model.profile.netLine[0], model.profile.netLine[1], mapper)
                    .stroke(PVColor.optic, lineWidth: lineWidth + 0.5)
            }
            .opacity(opacity)
        }
        .allowsHitTesting(false)
    }

    private func toView(_ court: CGPoint, _ mapper: AspectFillMapper) -> CGPoint? {
        guard let n = model.imagePoint(forCourt: court) else { return nil }
        return mapper.view(fromImageNormalized: n)
    }

    private func segment(_ a: CGPoint, _ b: CGPoint, _ mapper: AspectFillMapper) -> Path {
        var p = Path()
        if let va = toView(a, mapper), let vb = toView(b, mapper) {
            p.move(to: va); p.addLine(to: vb)
        }
        return p
    }

    /// Closed in-bounds polygon in view space, or nil if any corner fails to map.
    private func inBoundsViewPath(_ mapper: AspectFillMapper) -> Path? {
        let poly = model.profile.inBoundsPolygon.compactMap { toView($0, mapper) }
        guard poly.count == model.profile.inBoundsPolygon.count, poly.count >= 3 else { return nil }
        var p = Path()
        p.move(to: poly[0]); poly.dropFirst().forEach { p.addLine(to: $0) }; p.closeSubpath()
        return p
    }

    /// View rectangle plus the in-bounds polygon, for an even-odd "hole" fill.
    private func apronPath(viewSize: CGSize, inBounds: Path) -> Path {
        var p = Path(CGRect(origin: .zero, size: viewSize))
        p.addPath(inBounds)
        return p
    }
}

#Preview("CourtOverlay") {
    // Production stores NORMALIZED [0,1] image corners; mirror that here so the
    // preview renders the same way the app does. Order: [nearLeft, nearRight,
    // farRight, farLeft] - near (wide) at the bottom, far (narrow) at the top.
    let profile = CourtProfile.make(layout: .regulationPickleball)
    let imageSize = CGSize(width: 1280, height: 720)   // frame aspect for the mapper
    let imgCorners = [
        CGPoint(x: 0.18, y: 0.82),   // nearLeft
        CGPoint(x: 0.82, y: 0.82),   // nearRight
        CGPoint(x: 0.64, y: 0.30),   // farRight
        CGPoint(x: 0.36, y: 0.30),   // farLeft
    ]
    let model: CourtModel? = Homography(source: imgCorners, destination: profile.calibrationCorners)
        .map { CourtModel(profile: profile, homography: $0) }

    return ZStack {
        PVColor.feedGradient.ignoresSafeArea()
        if let model {
            CourtOverlay(model: model, imageSize: imageSize)
        } else {
            Text("homography failed").foregroundStyle(.red)
        }
    }
    .frame(width: 560, height: 315)   // landscape, like the live camera
}
