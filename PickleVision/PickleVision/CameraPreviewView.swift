import SwiftUI
import AVFoundation

/// A SwiftUI wrapper around `AVCaptureVideoPreviewLayer` that fills its bounds
/// and keeps the preview upright via an `AVCaptureDevice.RotationCoordinator`
/// (so the feed is correctly oriented in our forced-landscape camera screen and
/// as the mounted phone tilts).
struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var camera: CameraService

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = camera.session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        if uiView.videoPreviewLayer.session !== camera.session {
            uiView.videoPreviewLayer.session = camera.session
        }
        // The capture device is configured asynchronously; once it exists,
        // attach a rotation coordinator that drives the preview connection's
        // rotation angle. updateUIView re-runs when `camera` publishes
        // (e.g. isRunning), by which point the device is set.
        if context.coordinator.isAttached == false, let device = camera.captureDevice {
            context.coordinator.attach(device: device, previewLayer: uiView.videoPreviewLayer)
        }
    }

    static func dismantleUIView(_ uiView: PreviewUIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
        private var observation: NSKeyValueObservation?
        private weak var previewLayer: AVCaptureVideoPreviewLayer?

        var isAttached: Bool { rotationCoordinator != nil }

        func attach(device: AVCaptureDevice, previewLayer: AVCaptureVideoPreviewLayer) {
            self.previewLayer = previewLayer
            let rc = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            rotationCoordinator = rc
            apply(rc.videoRotationAngleForHorizonLevelPreview)
            observation = rc.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] coord, _ in
                self?.apply(coord.videoRotationAngleForHorizonLevelPreview)
            }
        }

        /// Sets the preview connection's rotation angle (on the main thread -
        /// KVO callbacks can arrive off-main from device-motion updates).
        private func apply(_ angle: CGFloat) {
            let layer = previewLayer
            let work = {
                guard let connection = layer?.connection,
                      connection.isVideoRotationAngleSupported(angle) else { return }
                connection.videoRotationAngle = angle
            }
            if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
        }

        func detach() {
            observation?.invalidate()
            observation = nil
            rotationCoordinator = nil
            previewLayer = nil
        }
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
