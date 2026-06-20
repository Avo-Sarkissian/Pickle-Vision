import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "figure.pickleball").font(.system(size: 64))
                Text("Pickle Vision").font(.largeTitle.bold())
                Text("Mount the phone behind the baseline and start the camera.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                NavigationLink {
                    CameraScreen()
                } label: {
                    Label("Start Camera", systemImage: "camera.fill")
                        .font(.headline).padding(.horizontal, 24).padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .lockOrientation(.portrait)
        }
    }
}
