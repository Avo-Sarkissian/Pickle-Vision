import SwiftUI
import Combine
import PickleVisionCore

struct CalibrationScreen: View {
    @ObservedObject var camera: CameraService
    @Environment(\.dismiss) private var dismiss

    @State private var frozen: CGImage?
    @State private var frozenSize: CGSize = .zero
    @State private var layout: CourtLayout = .regulationPickleball
    @State private var corners: [CGPoint] = CalibrationDraft.defaultCorners()
    @State private var showOverlay = false
    @State private var tapResult: String?
    @State private var venueName = "My Court"
    @State private var freezeSink: AnyCancellable?

    private var draft: CalibrationDraft {
        CalibrationDraft(corners: corners, layout: layout)
    }
    private var store: CalibrationStore {
        CalibrationStore(directory: URL.documentsDirectory.appendingPathComponent("calibrations"))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Layout", selection: $layout) {
                Text("Pickleball").tag(CourtLayout.regulationPickleball)
                Text("Tennis box").tag(CourtLayout.tennisFrontBox)
                Text("Custom").tag(CourtLayout.custom)
            }
            .pickerStyle(.segmented)
            .padding()

            ZStack {
                if let img = frozen {
                    CalibrationView(image: img, imageSize: frozenSize, corners: $corners)
                    if showOverlay, let model = draft.courtModel() {
                        CourtOverlayView(model: model, imageSize: frozenSize)
                    }
                    tapTestCatcher
                } else {
                    ContentUnavailableView("Point at the court", systemImage: "camera.viewfinder")
                }
            }

            if let tr = tapResult {
                Text(tr).font(.callout).padding(8)
            }

            HStack {
                Button("Re-freeze") { freeze() }
                Spacer()
                Button(showOverlay ? "Hide court" : "Show court") { showOverlay.toggle() }
                    .disabled(!draft.isComplete)
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.courtModel() == nil)
            }
            .padding()
        }
        .navigationTitle("Calibrate")
        .onAppear { camera.start(); freeze() }
        .onChange(of: corners) { tapResult = nil }
        .onChange(of: layout) { tapResult = nil }
    }

    private var tapTestCatcher: some View {
        GeometryReader { geo in
            Color.clear.contentShape(Rectangle())
                .onTapGesture { location in
                    guard showOverlay, let model = draft.courtModel() else { return }
                    let mapper = AspectFillMapper(viewSize: geo.size, contentSize: frozenSize)
                    let n = mapper.imageNormalized(fromView: location)
                    let court = model.courtPoint(forImage: n)
                    let inBounds = model.isInBounds(courtPoint: court)
                    tapResult = String(format: "(%.1f, %.1f) ft · %@", court.x, court.y, inBounds ? "IN" : "OUT")
                }
        }
    }

    /// Captures a frozen frame. If no frame has arrived yet (session just
    /// started), grabs the first one that does.
    private func freeze() {
        if let img = camera.latestImage {
            frozen = img
            frozenSize = camera.imageSize
            return
        }
        freezeSink = camera.$latestImage
            .compactMap { $0 }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { img in
                frozen = img
                frozenSize = camera.imageSize
                freezeSink = nil
            }
    }

    private func save() {
        let cal = StoredCalibration(
            venueName: venueName,
            layout: layout,
            imageCorners: corners.map { CodablePoint($0) },
            customDimensions: nil,
            savedAt: Date()
        )
        try? store.save(cal)
        dismiss()
    }
}
