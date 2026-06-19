@preconcurrency import AVFoundation
import Combine
import QuartzCore
import PickleVisionCore

/// Owns the capture session. Configuration and start/stop run on a private
/// session queue (off the main thread, per AVFoundation guidance); all
/// `@Published` UI state is published back on the main thread.
final class CameraService: NSObject, ObservableObject {
    enum PermissionState { case unknown, authorized, denied }

    @Published private(set) var permission: PermissionState = .unknown
    @Published private(set) var isRunning = false
    @Published private(set) var selectedFormatDescription = "—"
    @Published private(set) var measuredFPS = 0
    @Published private(set) var thermal = ThermalRecommendation(shouldWarn: false, frameRateCap: nil, message: nil)

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "vision.pickle.session")
    private let frameQueue = DispatchQueue(label: "vision.pickle.frames")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let selector = CameraFormatSelector(targetHeight: 1080, maxFrameRate: 120)
    private let thermalPolicy = ThermalPolicy(baseFrameRate: 120)

    private var device: AVCaptureDevice?
    private var pressureObservation: NSKeyValueObservation?
    private var chosenMaxRate: Double = 120
    private var frameTimes: [CFTimeInterval] = []   // touched only on frameQueue
    private var lastPublishedFPS = 0                // touched only on frameQueue

    /// Requests permission if needed, then configures and starts the session.
    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setPermission(.authorized)
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                self.setPermission(granted ? .authorized : .denied)
                if granted { self.configureAndStart() }
            }
        default:
            setPermission(.denied)
        }
    }

    func stop() {
        sessionQueue.async { [weak self, session] in
            guard let self else { return }
            if session.isRunning { session.stopRunning() }
            self.publishOnMain { self.isRunning = false }
        }
    }

    // MARK: - Configuration (session queue)

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureSession()
            if !self.session.isRunning { self.session.startRunning() }
            let running = self.session.isRunning
            self.publishOnMain { self.isRunning = running }
        }
    }

    private func configureSession() {
        guard session.inputs.isEmpty else { return }   // already configured; don't double-add

        session.beginConfiguration()
        session.sessionPreset = .inputPriority   // we set device.activeFormat ourselves

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        self.device = device

        // Map the device's formats to testable candidates and pick the best.
        let mapped: [(AVCaptureDevice.Format, CameraFormatCandidate)] = device.formats.map { fmt in
            let dims = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
            let maxRate = fmt.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
            return (fmt, CameraFormatCandidate(width: Int(dims.width),
                                               height: Int(dims.height),
                                               maxFrameRate: maxRate,
                                               isBinned: fmt.isVideoBinned,
                                               supportsMultiCam: fmt.isMultiCamSupported))
        }
        if let best = selector.select(from: mapped.map(\.1)),
           let chosen = mapped.first(where: { $0.1 == best })?.0 {
            let rate = min(best.maxFrameRate, 120)
            chosenMaxRate = rate
            if (try? device.lockForConfiguration()) != nil {
                device.activeFormat = chosen
                let duration = CMTime(value: 1, timescale: CMTimeScale(rate))
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
                device.unlockForConfiguration()
            }
            let desc = "\(best.height)p · \(Int(rate))fps"
            publishOnMain { self.selectedFormatDescription = desc }
        }

        if session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: frameQueue)
            session.addOutput(videoOutput)
        }

        session.commitConfiguration()
        observePressure(on: device)
    }

    private func observePressure(on device: AVCaptureDevice) {
        pressureObservation = device.observe(\.systemPressureState, options: [.initial, .new]) { [weak self] dev, _ in
            guard let self else { return }
            let rec = self.thermalPolicy.recommendation(for: CameraService.map(dev.systemPressureState.level))
            self.publishOnMain { self.thermal = rec }
            self.applyThermalCap(rec.frameRateCap)
        }
    }

    /// Re-applies the active frame duration if thermal pressure capped the rate.
    private func applyThermalCap(_ cap: Double?) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.device else { return }
            let target: Double
            if let cap, cap > 0 { target = min(cap, self.chosenMaxRate) }
            else { target = self.chosenMaxRate }
            guard target > 0, (try? device.lockForConfiguration()) != nil else { return }
            let duration = CMTime(value: 1, timescale: CMTimeScale(target))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
        }
    }

    static func map(_ level: AVCaptureDevice.SystemPressureState.Level) -> ThermalLevel {
        switch level {
        case .nominal:  return .nominal
        case .fair:     return .fair
        case .serious:  return .serious
        case .critical: return .critical
        case .shutdown: return .shutdown
        default:        return .nominal
        }
    }

    // MARK: - Main-thread publishing

    private func setPermission(_ state: PermissionState) {
        publishOnMain { self.permission = state }
    }

    private func publishOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        frameTimes.append(now)
        frameTimes.removeAll { now - $0 > 1.0 }
        let fps = frameTimes.count
        // The rolling 1s count changes at most ~once/sec; only publish on change
        // rather than once per frame (would be up to 120 Hz).
        if fps != lastPublishedFPS {
            lastPublishedFPS = fps
            publishOnMain { self.measuredFPS = fps }
        }
    }
}
