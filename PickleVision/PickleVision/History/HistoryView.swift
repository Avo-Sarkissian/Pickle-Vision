import SwiftUI

/// Phase-6 placeholder. Scores and stats are not produced yet; this screen
/// shows ghosted sample rows + a dashed future note so the section exists in
/// nav without faking data.
struct HistoryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Sessions")
                        .font(PVFont.display(28))
                        .foregroundStyle(PVColor.ink)
                    Spacer()
                    Text("PHASE 6")
                        .font(PVFont.mono(9, weight: .semibold)).tracking(0.8)
                        .foregroundStyle(PVColor.ink)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(PVColor.optic, in: Capsule())
                }
                Text("Scores and stats record here once scoring ships.")
                    .font(PVFont.ui(14))
                    .foregroundStyle(PVColor.mutedLight)
                    .padding(.top, 8)

                VStack(spacing: 10) {
                    ghostRow(venue: "Riverside · Court 3", meta: "Jun 12", score: "11 — 7",   sub: "42 min · 3 games")
                    ghostRow(venue: "Memorial Park",       meta: "Jun 9",  score: "11 — 9",   sub: "28 min · 1 game")
                }
                .padding(.top, 20)
                .opacity(0.55)

                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(PVColor.hairline)
                    .frame(height: 88)
                    .overlay(
                        VStack(spacing: 6) {
                            Text("Per-player stats · kitchen faults · speed")
                                .font(PVFont.ui(13, weight: .semibold))
                                .foregroundStyle(PVColor.mutedLight)
                            Text("arrive with later phases")
                                .font(PVFont.ui(12))
                                .foregroundStyle(PVColor.mutedLight)
                        }
                    )
                    .padding(.top, 14)
            }
            .padding(.horizontal, 22).padding(.top, 8)
        }
        .background(PVColor.paper.ignoresSafeArea())
        .navigationTitle("Sessions")
        .navigationBarTitleDisplayMode(.inline)
        .lockOrientation(.portrait)
    }

    private func ghostRow(venue: String, meta: String, score: String, sub: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(venue).font(PVFont.ui(15, weight: .semibold)).foregroundStyle(PVColor.ink)
                Text(score).font(PVFont.display(28)).foregroundStyle(PVColor.ink)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(meta).font(PVFont.mono(11)).foregroundStyle(PVColor.mutedLight)
                Text(sub).font(PVFont.ui(12)).foregroundStyle(PVColor.mutedLight)
            }
        }
        .padding(16)
        .background(PVColor.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(PVColor.hairline, lineWidth: 1))
    }
}

#Preview { NavigationStack { HistoryView() } }
