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

                Path { p in
                    guard handles.count == 4 else { return }
                    p.move(to: handles[0])
                    for h in handles.dropFirst() { p.addLine(to: h) }
                    p.closeSubpath()
                }
                .stroke(Color.yellow.opacity(0.9), lineWidth: 2)

                ForEach(handles.indices, id: \.self) { i in
                    handleView(label: labels[i]).position(handles[i])
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
            Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(.yellow).offset(y: 20)
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
            .overlay(Image(systemName: "plus").font(.system(size: 10)).foregroundStyle(.white))
            .position(x: min(max(location.x, loupeSize), geo.size.width - loupeSize),
                      y: max(location.y - loupeSize, loupeSize))
    }
}
