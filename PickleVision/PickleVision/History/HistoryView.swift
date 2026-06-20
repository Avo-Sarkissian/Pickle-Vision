import SwiftUI
import PickleVisionCore

/// Displays saved clips (newest first). Delete swipes away the row and
/// removes the record + video file from disk.
struct HistoryView: View {
    @State private var clips: [SessionClip] = []

    private let clipStore: ClipStore
    private let calStore: CalibrationStore

    init(
        clipsDirectory: URL = URL.documentsDirectory.appendingPathComponent("clips"),
        calibrationsDirectory: URL = URL.documentsDirectory.appendingPathComponent("calibrations")
    ) {
        clipStore = ClipStore(directory: clipsDirectory)
        calStore = CalibrationStore(directory: calibrationsDirectory)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Clips")
                    .font(PVFont.display(28))
                    .foregroundStyle(PVColor.ink)
                    .padding(.bottom, 8)

                if clips.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 10) {
                        ForEach(clips) { clip in
                            clipRow(clip)
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
        }
        .background(PVColor.paper.ignoresSafeArea())
        .navigationTitle("Clips")
        .navigationBarTitleDisplayMode(.inline)
        .lockOrientation(.portrait)
        .onAppear { clips = clipStore.loadAll() }
    }

    // MARK: Row

    private func clipRow(_ clip: SessionClip) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(courtName(for: clip))
                    .font(PVFont.ui(15, weight: .semibold))
                    .foregroundStyle(PVColor.ink)
                Text(relativeDate(clip.recordedAt))
                    .font(PVFont.ui(13))
                    .foregroundStyle(PVColor.mutedLight)
            }
            Spacer()
            Text("\(Int(clip.fps)) fps")
                .font(PVFont.mono(12))
                .foregroundStyle(PVColor.mutedLight)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(PVColor.hairline, lineWidth: 1))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteClip(id: clip.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "film")
                .font(PVFont.display(30))
                .foregroundStyle(PVColor.mutedLight)
                .padding(.top, 28)
            Text("No clips yet")
                .font(PVFont.ui(15, weight: .semibold))
                .foregroundStyle(PVColor.ink)
            Text("Clips recorded during sessions appear here.")
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
        .padding(.top, 8)
    }

    // MARK: Helpers

    private func courtName(for clip: SessionClip) -> String {
        calStore.load(id: clip.courtID)?.venueName ?? "Unknown court"
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func deleteClip(id: UUID) {
        try? clipStore.delete(id: id)
        clips = clipStore.loadAll()
    }
}

// MARK: - Preview

#Preview {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("pv_history_preview_\(Int.random(in: 0..<999999))")
    let calDir = tmp.appendingPathComponent("calibrations")
    let clipsDir = tmp.appendingPathComponent("clips")

    let calStore = CalibrationStore(directory: calDir)
    let courtA = UUID()
    let courtB = UUID()
    let corners: [CodablePoint] = [
        CodablePoint(x: 0.1, y: 0.8),
        CodablePoint(x: 0.9, y: 0.8),
        CodablePoint(x: 0.9, y: 0.2),
        CodablePoint(x: 0.1, y: 0.2),
    ]
    try? calStore.save(StoredCalibration(
        id: courtA, venueName: "Riverside Courts",
        layout: .regulationPickleball, imageCorners: corners,
        customDimensions: nil, savedAt: Date().addingTimeInterval(-7200)
    ))
    try? calStore.save(StoredCalibration(
        id: courtB, venueName: "Gym Court 3",
        layout: .regulationPickleball, imageCorners: corners,
        customDimensions: nil, savedAt: Date().addingTimeInterval(-86400)
    ))

    let clipStore = ClipStore(directory: clipsDir)
    try? clipStore.save(SessionClip(
        courtID: courtA, fileName: "clip1.mov", fps: 60,
        frameWidth: 1920, frameHeight: 1080,
        recordedAt: Date().addingTimeInterval(-300)
    ))
    try? clipStore.save(SessionClip(
        courtID: courtB, fileName: "clip2.mov", fps: 30,
        frameWidth: 1920, frameHeight: 1080,
        recordedAt: Date().addingTimeInterval(-3600 * 25)
    ))

    return NavigationStack {
        HistoryView(clipsDirectory: clipsDir, calibrationsDirectory: calDir)
    }
}
