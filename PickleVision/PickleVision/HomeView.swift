import SwiftUI
import PickleVisionCore

// MARK: - HomeView

struct HomeView: View {
    @StateObject private var profileStore = CaptureProfileStore()
    @State private var courts: [StoredCalibration] = []
    @State private var path: [NavRoute] = []

    private let store = CalibrationStore(
        directory: URL.documentsDirectory.appendingPathComponent("calibrations")
    )

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if courts.isEmpty {
                        emptyContent     // Task 6.6
                    } else {
                        populatedContent
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
            }
            .background(PVColor.paper.ignoresSafeArea())
            .navigationBarHidden(true)
            .lockOrientation(.portrait)
            .onAppear { courts = store.loadAll() }
            .navigationDestination(for: NavRoute.self) { route in
                switch route {
                case .camera:
                    CameraScreen(profile: profileStore.profile)
                case .settings:
                    SettingsView(
                        profileStore: profileStore,
                        store: store,
                        onChange: { courts = store.loadAll() }
                    )
                case .recalibrate(let id):
                    if let cal = store.load(id: id) {
                        CalibrationScreen(reloading: cal)
                    } else {
                        // Fallback: court no longer on disk — start fresh camera path.
                        CameraScreen(profile: profileStore.profile)
                    }
                case .calibrate:
                    // First-time setup: calibrate directly (not nested under the
                    // live camera), so Save dismisses back here to Home and the
                    // newly-saved court appears in the list (onAppear reloads).
                    CalibrationScreen(camera: CameraService())
                case .clips:
                    HistoryView()
                case .session(let id):
                    if let cal = store.load(id: id), let model = CalibrationStore.courtModel(from: cal) {
                        CameraScreen(profile: profileStore.profile, court: model, courtName: cal.venueName, courtID: cal.id)
                    } else {
                        // Court unreadable: fall back to a generic session.
                        CameraScreen(profile: profileStore.profile)
                    }
                }
            }
        }
    }

    enum NavRoute: Hashable {
        case camera
        case calibrate
        case settings
        case clips
        case recalibrate(id: UUID)
        case session(id: UUID)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().strokeBorder(PVColor.ink, lineWidth: 1.5)
                    Circle().fill(PVColor.optic).frame(width: 7, height: 7)
                }
                .frame(width: 18, height: 18)
                Text("PICKLE\nVISION")
                    .font(PVFont.mono(11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(PVColor.ink)
            }
            Spacer()
            Button {
                path.append(.clips)
            } label: {
                Image(systemName: "film")
                    .font(PVFont.ui(18))
                    .foregroundStyle(PVColor.mutedLight)
                    .frame(width: 44, height: 44, alignment: .topTrailing)
            }
            .buttonStyle(.plain)
            Button {
                path.append(.settings)
            } label: {
                Image(systemName: "gearshape")
                    .font(PVFont.ui(18))
                    .foregroundStyle(PVColor.mutedLight)
                    .frame(width: 44, height: 44, alignment: .topTrailing)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 18)
    }

    // MARK: Populated

    private var populatedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ready to\nref.")
                .font(PVFont.display(44))
                .foregroundStyle(PVColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("Mount the phone behind the baseline, in landscape.")
                .font(PVFont.ui(14))
                .foregroundStyle(PVColor.mutedLight)
                .padding(.top, 12)

            PrimaryButton("Start a session →") {
                if let first = courts.first {
                    path.append(.session(id: first.id))
                } else {
                    path.append(.camera)
                }
            }
            .padding(.top, 22)

            HStack {
                Text("SAVED\nCOURTS")
                    .font(PVFont.mono(11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(PVColor.mutedLight)
                Spacer()
                Text("\(courts.count)")
                    .font(PVFont.mono(13))
                    .foregroundStyle(PVColor.mutedLight)
            }
            .padding(.top, 28)
            .padding(.bottom, 12)

            VStack(spacing: 10) {
                ForEach(courts) { cal in
                    SavedCourtCard(calibration: cal,
                                   onStart:  { path.append(.session(id: cal.id)) },
                                   onReload: { path.append(.recalibrate(id: cal.id)) })
                }
            }

            footer
                .padding(.top, 24)
                .padding(.bottom, 16)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Circle().fill(PVColor.optic).frame(width: 7, height: 7)
            Text("ON-DEVICE · NO ACCOUNT")
                .font(PVFont.mono(11))
                .tracking(1.0)
                .foregroundStyle(PVColor.mutedLight)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(PVColor.paper, in: Capsule())
        .overlay(Capsule().stroke(PVColor.hairline, lineWidth: 1))
    }

    // MARK: Empty (Task 6.6)

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("First\ncourt.")
                .font(PVFont.display(44))
                .foregroundStyle(PVColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("Mount the phone behind the baseline, in landscape, then calibrate the court once.")
                .font(PVFont.ui(14))
                .foregroundStyle(PVColor.mutedLight)
                .padding(.top, 12)

            PrimaryButton("Set up your first court →") {
                path.append(.calibrate)
            }
            .padding(.top, 22)

            Text("SAVED COURTS")
                .font(PVFont.mono(11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(PVColor.mutedLight)
                .padding(.top, 28)
                .padding(.bottom, 12)

            VStack(spacing: 10) {
                Image(systemName: "rectangle.portrait")
                    .font(PVFont.display(30))
                    .foregroundStyle(PVColor.mutedLight)
                    .padding(.top, 28)
                Text("No saved courts yet")
                    .font(PVFont.ui(15, weight: .semibold))
                    .foregroundStyle(PVColor.ink)
                Text("Calibrated courts live here — set one up and it's one tap to reload next time.")
                    .font(PVFont.ui(13))
                    .foregroundStyle(PVColor.mutedLight)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(PVColor.hairline)
            )

            footer.padding(.top, 24).padding(.bottom, 16)
        }
    }
}

// MARK: - Empty-state Preview

#Preview("HomeView — empty (first launch)") {
    // Wraps the HomeView logic in a stripped shell with courts = [] so
    // emptyContent renders without any on-disk calibration data.
    struct EmptyHome: View {
        @State private var path: [HomeView.NavRoute] = []

        private var header: some View {
            HStack(alignment: .top) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle().strokeBorder(PVColor.ink, lineWidth: 1.5)
                        Circle().fill(PVColor.optic).frame(width: 7, height: 7)
                    }
                    .frame(width: 18, height: 18)
                    Text("PICKLE\nVISION")
                        .font(PVFont.mono(11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(PVColor.ink)
                }
                Spacer()
                Image(systemName: "gearshape")
                    .font(PVFont.ui(18))
                    .foregroundStyle(PVColor.mutedLight)
                    .frame(width: 44, height: 44, alignment: .topTrailing)
            }
            .padding(.bottom, 18)
        }

        private var footer: some View {
            HStack(spacing: 8) {
                Circle().fill(PVColor.optic).frame(width: 7, height: 7)
                Text("ON-DEVICE · NO ACCOUNT")
                    .font(PVFont.mono(11))
                    .tracking(1.0)
                    .foregroundStyle(PVColor.mutedLight)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(PVColor.paper, in: Capsule())
            .overlay(Capsule().stroke(PVColor.hairline, lineWidth: 1))
        }

        var body: some View {
            NavigationStack(path: $path) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        // Empty-state content (mirrors emptyContent in HomeView)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("First\ncourt.")
                                .font(PVFont.display(44))
                                .foregroundStyle(PVColor.ink)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("Mount the phone behind the baseline, in landscape, then calibrate the court once.")
                                .font(PVFont.ui(14))
                                .foregroundStyle(PVColor.mutedLight)
                                .padding(.top, 12)

                            PrimaryButton("Set up your first court →") {}
                                .padding(.top, 22)

                            Text("SAVED COURTS")
                                .font(PVFont.mono(11, weight: .semibold))
                                .tracking(1.5)
                                .foregroundStyle(PVColor.mutedLight)
                                .padding(.top, 28)
                                .padding(.bottom, 12)

                            VStack(spacing: 10) {
                                Image(systemName: "rectangle.portrait")
                                    .font(PVFont.display(30))
                                    .foregroundStyle(PVColor.mutedLight)
                                    .padding(.top, 28)
                                Text("No saved courts yet")
                                    .font(PVFont.ui(15, weight: .semibold))
                                    .foregroundStyle(PVColor.ink)
                                Text("Calibrated courts live here — set one up and it's one tap to reload next time.")
                                    .font(PVFont.ui(13))
                                    .foregroundStyle(PVColor.mutedLight)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                                    .padding(.bottom, 28)
                            }
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                                    .foregroundStyle(PVColor.hairline)
                            )

                            footer.padding(.top, 24).padding(.bottom, 16)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                }
                .background(PVColor.paper.ignoresSafeArea())
                .navigationBarHidden(true)
                .navigationDestination(for: HomeView.NavRoute.self) { _ in
                    Text("Camera")
                }
            }
        }
    }
    return EmptyHome()
}

// MARK: - Preview

#Preview("HomeView — populated (3 sample courts)") {
    HomeView()
}

#Preview("HomeView — populated (injected courts)") {
    // Uses a temporary CalibrationStore seeded with 3 sample courts so the
    // preview renders the populated state without on-disk data.
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("pv_home_preview_\(Int.random(in: 0..<999999))")
    let sampleStore = CalibrationStore(directory: tmpDir)
    let samples: [StoredCalibration] = [
        StoredCalibration(
            venueName: "Riverside · Court 3",
            layout: .regulationPickleball,
            imageCorners: [
                CodablePoint(x: 0.16, y: 0.80), CodablePoint(x: 0.84, y: 0.80),
                CodablePoint(x: 0.66, y: 0.30), CodablePoint(x: 0.34, y: 0.30),
            ],
            customDimensions: nil,
            savedAt: Date().addingTimeInterval(-2 * 86_400)
        ),
        StoredCalibration(
            venueName: "Brighton Athletic · Court 1",
            layout: .tennisFrontBox,
            imageCorners: [
                CodablePoint(x: 0.18, y: 0.82), CodablePoint(x: 0.82, y: 0.82),
                CodablePoint(x: 0.64, y: 0.28), CodablePoint(x: 0.36, y: 0.28),
            ],
            customDimensions: nil,
            savedAt: Date().addingTimeInterval(-5 * 3_600)
        ),
        StoredCalibration(
            venueName: "Backyard Setup",
            layout: .custom,
            imageCorners: [
                CodablePoint(x: 0.20, y: 0.78), CodablePoint(x: 0.80, y: 0.78),
                CodablePoint(x: 0.62, y: 0.32), CodablePoint(x: 0.38, y: 0.32),
            ],
            customDimensions: CustomDimensions(
                widthFeet: 18, lengthFeet: 38, nonVolleyZoneFeet: 6
            ),
            savedAt: Date().addingTimeInterval(-90)
        ),
    ]
    try? samples.forEach { try sampleStore.save($0) }

    // Wrap in a view that forces a populated-state load from our seeded store.
    // HomeView uses its own internal store, so this preview shows the live
    // empty state if the device has no saved courts; the seeded-store variant
    // illustrates the populated layout directly.
    struct SeededHome: View {
        let courts: [StoredCalibration]
        @State private var path: [HomeView.NavRoute] = []
        var body: some View {
            NavigationStack(path: $path) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        _header
                        _populated(courts: courts, path: $path)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                }
                .background(PVColor.paper.ignoresSafeArea())
                .navigationBarHidden(true)
            }
        }

        private var _header: some View {
            HStack(alignment: .top) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle().strokeBorder(PVColor.ink, lineWidth: 1.5)
                        Circle().fill(PVColor.optic).frame(width: 7, height: 7)
                    }
                    .frame(width: 18, height: 18)
                    Text("PICKLE\nVISION")
                        .font(PVFont.mono(11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(PVColor.ink)
                }
                Spacer()
                Image(systemName: "gearshape")
                    .font(PVFont.ui(18))
                    .foregroundStyle(PVColor.mutedLight)
                    .frame(width: 44, height: 44, alignment: .topTrailing)
            }
            .padding(.bottom, 18)
        }

        private func _populated(courts: [StoredCalibration], path: Binding<[HomeView.NavRoute]>) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("Ready to\nref.")
                    .font(PVFont.display(44))
                    .foregroundStyle(PVColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Mount the phone behind the baseline, in landscape.")
                    .font(PVFont.ui(14))
                    .foregroundStyle(PVColor.mutedLight)
                    .padding(.top, 12)
                PrimaryButton("Start a session →") { path.wrappedValue.append(.camera) }
                    .padding(.top, 22)
                HStack {
                    Text("SAVED\nCOURTS")
                        .font(PVFont.mono(11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(PVColor.mutedLight)
                    Spacer()
                    Text("\(courts.count)")
                        .font(PVFont.mono(13))
                        .foregroundStyle(PVColor.mutedLight)
                }
                .padding(.top, 28)
                .padding(.bottom, 12)
                VStack(spacing: 10) {
                    ForEach(courts) { cal in
                        SavedCourtCard(calibration: cal, onStart: {}, onReload: {})
                    }
                }
                HStack(spacing: 8) {
                    Circle().fill(PVColor.optic).frame(width: 7, height: 7)
                    Text("ON-DEVICE · NO ACCOUNT")
                        .font(PVFont.mono(11))
                        .tracking(1.0)
                        .foregroundStyle(PVColor.mutedLight)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(PVColor.paper, in: Capsule())
                .overlay(Capsule().stroke(PVColor.hairline, lineWidth: 1))
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
        }
    }

    return SeededHome(courts: samples)
}
