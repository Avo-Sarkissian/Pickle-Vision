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

    /// Short labels (kept for reference; full names used for active handle only)
    private let shortLabels = ["NL", "NR", "FR", "FL"]
    /// Full-name labels shown beside the active (dragging) handle
    private let fullLabels = ["nearLeft", "nearRight", "farRight", "farLeft"]

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

                Path { p in
                    guard handles.count == 4 else { return }
                    p.move(to: handles[0])
                    for h in handles.dropFirst() { p.addLine(to: h) }
                    p.closeSubpath()
                }
                .stroke(PVColor.optic.opacity(0.9), lineWidth: 2)

                ForEach(handles.indices, id: \.self) { i in
                    handleView(index: i, isActive: dragging == i).position(handles[i])
                }

                if let d = dragging {
                    loupe(at: dragLocation, mapper: mapper, geo: geo, handleIndex: d)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(geo: geo, mapper: mapper, handles: handles))
        }
    }

    private func handleView(index: Int, isActive: Bool) -> some View {
        ZStack {
            // Active halo
            if isActive {
                Circle()
                    .fill(PVColor.optic.opacity(0.3))
                    .frame(width: 56, height: 56)
            }
            // Handle ring
            Circle()
                .stroke(PVColor.optic, lineWidth: 2)
                .frame(width: isActive ? 40 : 28, height: isActive ? 40 : 28)
            // Center dot
            Circle()
                .fill(PVColor.optic)
                .frame(width: 6, height: 6)
            // Full-name label (active handle only)
            if isActive {
                Text(fullLabels[index])
                    .font(PVFont.mono(9, weight: .semibold))
                    .foregroundStyle(PVColor.optic)
                    .offset(y: 30)
            }
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
            .overlay(Image(systemName: "plus").font(PVFont.mono(10)).foregroundStyle(.white))
            .position(x: min(max(location.x, loupeSize), geo.size.width - loupeSize),
                      y: max(location.y - loupeSize, loupeSize))
    }
}
