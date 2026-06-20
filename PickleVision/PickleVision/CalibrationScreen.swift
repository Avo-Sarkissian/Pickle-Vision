import SwiftUI
import Combine
import PickleVisionCore

/// Court calibration screen. Landscape-first (the phone is mounted landscape
/// behind the baseline): the frozen frame fills the left, controls sit in a
/// column on the right. Falls back to a stacked layout in portrait.
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
    @State private var saveError: String?
    @State private var freezeSink: AnyCancellable?

    private let store = CalibrationStore(
        directory: URL.documentsDirectory.appendingPathComponent("calibrations")
    )

    private var draft: CalibrationDraft {
        CalibrationDraft(corners: corners, layout: layout)
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width >= geo.size.height
            if landscape {
                HStack(spacing: 0) {
                    frameArea
                    Divider()
                    controls.frame(width: 300)
                }
            } else {
                VStack(spacing: 0) {
                    frameArea
                    Divider()
                    controls
                }
            }
        }
        .navigationTitle("Calibrate")
        .navigationBarTitleDisplayMode(.inline)
        .lockOrientation(.landscape)
        .onAppear { camera.start(); freeze() }
        .onChange(of: corners) { tapResult = nil }
        .onChange(of: layout) { tapResult = nil }
        .alert("Couldn’t save calibration", isPresented: saveErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "Please try again.")
        }
    }

    // MARK: - Frame

    private var frameArea: some View {
        ZStack {
            if let img = frozen {
                CalibrationView(image: img, imageSize: frozenSize, corners: $corners)
                if showOverlay, let model = draft.courtModel() {
                    CourtOverlayView(model: model, imageSize: frozenSize)
                }
                tapTestCatcher
            } else {
                ContentUnavailableView("Point at the court", systemImage: "camera.viewfinder")
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipped()
        .layoutPriority(1)
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

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Layout", selection: $layout) {
                Text("Pickleball").tag(CourtLayout.regulationPickleball)
                Text("Tennis box").tag(CourtLayout.tennisFrontBox)
                Text("Custom").tag(CourtLayout.custom)
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 4) {
                Text("Court name").font(.caption).foregroundStyle(.secondary)
                TextField("Court name", text: $venueName)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
            }

            if let tr = tapResult {
                Label(tr, systemImage: "scope")
                    .font(.callout)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }

            Text("Drag the four corners (NL · NR · FR · FL) onto the court lines, then Show court to check the fit.")
                .font(.caption2).foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button { freeze() } label: {
                Label("Re-freeze", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button { showOverlay.toggle() } label: {
                Label(showOverlay ? "Hide court" : "Show court",
                      systemImage: showOverlay ? "eye.slash" : "eye").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!draft.isComplete)

            Button { save() } label: {
                Label("Save", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(draft.courtModel() == nil)
        }
        .controlSize(.large)
        .padding()
    }

    // MARK: - State helpers

    private var saveErrorBinding: Binding<Bool> {
        Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
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
        let trimmed = venueName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cal = StoredCalibration(
            venueName: trimmed.isEmpty ? "My Court" : trimmed,
            layout: layout,
            imageCorners: corners.map { CodablePoint($0) },
            customDimensions: nil,
            savedAt: Date()
        )
        do {
            try store.save(cal)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
