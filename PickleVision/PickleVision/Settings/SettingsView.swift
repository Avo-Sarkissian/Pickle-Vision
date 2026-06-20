import SwiftUI
import PickleVisionCore

struct SettingsView: View {
    @ObservedObject var profileStore: CaptureProfileStore
    let store: CalibrationStore
    let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var courts: [StoredCalibration] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionLabel("CAPTURE PROFILE").padding(.top, 8)
                captureProfileCard.padding(.top, 12)
                helperNote.padding(.top, 12)

                sectionLabel("MANAGE SAVED COURTS").padding(.top, 28)
                manageCourts.padding(.top, 12)

                footer.padding(.top, 28).padding(.bottom, 16)
            }
            .padding(.horizontal, 22)
        }
        .background(PVColor.paper.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .lockOrientation(.portrait)
        .onAppear { courts = store.loadAll() }
    }

    // MARK: Section label

    private func sectionLabel(_ s: String) -> some View {
        Text(s)
            .font(PVFont.mono(11, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(PVColor.mutedLight)
    }

    // MARK: Capture profile (single-select)

    private var captureProfileCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(CaptureProfile.allCases.enumerated()), id: \.element) { idx, profile in
                Button { profileStore.profile = profile } label: {
                    profileRow(profile)
                }
                .buttonStyle(.plain)
                if idx < CaptureProfile.allCases.count - 1 {
                    Divider().overlay(PVColor.hairline).padding(.leading, 18)
                }
            }
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(PVColor.hairline, lineWidth: 1))
    }

    private func profileRow(_ profile: CaptureProfile) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.displayTitle)
                    .font(PVFont.ui(15, weight: .semibold))
                    .foregroundStyle(PVColor.ink)
                if let sub = profile.subtitle {
                    Text(sub)
                        .font(PVFont.ui(12))
                        .foregroundStyle(PVColor.mutedLight)
                }
            }
            Spacer()
            badge(for: profile)
            selectionIndicator(for: profile)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func badge(for profile: CaptureProfile) -> some View {
        switch profile.badge {
        case .recommended:
            Text("RECOMMENDED")
                .font(PVFont.mono(9, weight: .semibold)).tracking(0.8)
                .foregroundStyle(PVColor.ink)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(PVColor.optic, in: Capsule())
        case .default:
            Text("DEFAULT")
                .font(PVFont.mono(9, weight: .semibold)).tracking(0.8)
                .foregroundStyle(PVColor.mutedLight)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(PVColor.hairline, in: Capsule())
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private func selectionIndicator(for profile: CaptureProfile) -> some View {
        if profileStore.profile == profile {
            ZStack {
                Circle().fill(PVColor.optic).frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(PVFont.ui(11, weight: .bold))
                    .foregroundStyle(PVColor.ink)
            }
        } else {
            Circle().strokeBorder(PVColor.hairline, lineWidth: 1.5)
                .frame(width: 22, height: 22)
        }
    }

    private var helperNote: some View {
        Text("4K·120 gives the most spatial detail for line calls; the app starts at 1080p·120 and steps fps down under heat. Final defaults land in Phase 2.")
            .font(PVFont.ui(12))
            .foregroundStyle(PVColor.mutedLight)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Manage saved courts

    @ViewBuilder
    private var manageCourts: some View {
        if courts.isEmpty {
            Text("No saved courts yet.")
                .font(PVFont.ui(13)).foregroundStyle(PVColor.mutedLight)
                .padding(.vertical, 8)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(courts.enumerated()), id: \.element.venueName) { idx, cal in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cal.venueName)
                                .font(PVFont.ui(15, weight: .semibold))
                                .foregroundStyle(PVColor.ink)
                            Text(layoutName(cal.layout))
                                .font(PVFont.ui(12))
                                .foregroundStyle(PVColor.mutedLight)
                        }
                        Spacer()
                        Button("Delete") { deleteCourt(cal) }
                            .font(PVFont.ui(14, weight: .semibold))
                            .foregroundStyle(PVColor.recordRed)
                            .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    if idx < courts.count - 1 {
                        Divider().overlay(PVColor.hairline).padding(.leading, 18)
                    }
                }
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(PVColor.hairline, lineWidth: 1))
        }
    }

    private func deleteCourt(_ cal: StoredCalibration) {
        try? store.delete(venueName: cal.venueName)
        courts = store.loadAll()
        onChange()
    }

    private func layoutName(_ layout: CourtLayout) -> String {
        switch layout {
        case .regulationPickleball: return "Pickleball"
        case .tennisFrontBox:       return "Tennis box"
        case .custom:               return "Custom"
        }
    }

    // MARK: Footer

    private var footer: some View {
        Text("Pickle Vision · v0.1 · iPhone 16 Pro")
            .font(PVFont.mono(11))
            .foregroundStyle(PVColor.mutedLight)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Preview

#Preview {
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("pv_settings_preview_\(Int.random(in: 0..<999999))")
    let previewStore = CalibrationStore(directory: tmpDir)
    let samples: [StoredCalibration] = [
        StoredCalibration(
            venueName: "Riverside · Court 3",
            layout: .regulationPickleball,
            imageCorners: [
                CodablePoint(x: 45, y: 172), CodablePoint(x: 275, y: 172),
                CodablePoint(x: 200, y: 48),  CodablePoint(x: 120, y: 48),
            ],
            customDimensions: nil,
            savedAt: Date().addingTimeInterval(-2 * 86_400)
        ),
        StoredCalibration(
            venueName: "Brighton Athletic · Court 1",
            layout: .tennisFrontBox,
            imageCorners: [
                CodablePoint(x: 60, y: 200), CodablePoint(x: 320, y: 200),
                CodablePoint(x: 260, y: 50),  CodablePoint(x: 120, y: 50),
            ],
            customDimensions: nil,
            savedAt: Date().addingTimeInterval(-5 * 3_600)
        ),
    ]
    try? samples.forEach { try previewStore.save($0) }

    return NavigationStack {
        SettingsView(
            profileStore: CaptureProfileStore(),
            store: previewStore,
            onChange: {}
        )
    }
}
