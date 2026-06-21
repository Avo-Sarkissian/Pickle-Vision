@preconcurrency import AVFoundation
import Combine
import CoreImage
import QuartzCore
@preconcurrency import PickleVisionCore

/// Owns the capture session. Configuration and start/stop run on a private
/// session queue (off the main thread, per AVFoundation guidance); all
/// `@Published` UI state is published back on the main thread.
final class CameraService: NSObject, ObservableObject {
    enum PermissionState { case unknown, authorized, denied, restricted }

    @Published private(set) var permission: PermissionState = .unknown
    @Published private(set) var isRunning = false
    @Published private(set) var selectedFormatDescription = "-"
    @Published private(set) var measuredFPS = 0
    @Published private(set) var thermal = ThermalRecommendation(shouldWarn: false, frameRateCap: nil, message: nil)
    @Published private(set) var latestImage: CGImage?
    @Published private(set) var imageSize: CGSize = CGSize(width: 1920, height: 1080)

    let session = AVCaptureSession()

    @Published private(set) var isRecording = false
    @Published var lastSavedClip: SessionClip?

    private let sessionQueue = DispatchQueue(label: "vision.pickle.session")
    private let frameQueue = DispatchQueue(label: "vision.pickle.frames")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    // Accessed from sessionQueue (startRecording/fileOutput delegate) — guarded by sessionQueue, not main actor.
    nonisolated(unsafe) private var recordingCourtID: UUID?
    nonisolated(unsafe) private var recordingImageSize: CGSize = CGSize(width: 1920, height: 1080)
    nonisolated(unsafe) private var recordingFPS: Double = 120
    nonisolated(unsafe) private let clipStore = ClipStore(directory: URL.documentsDirectory.appendingPathComponent("clips"))
    private var selector = CameraFormatSelector(targetHeight: 1080, maxFrameRate: 120)
    private let thermalPolicy = ThermalPolicy(baseFrameRate: 120)

    private var device: AVCaptureDevice?
    /// Exposed read-only so the preview can attach a rotation coordinator.
    var captureDevice: AVCaptureDevice? { device }
    private var pressureObservation: NSKeyValueObservation?
    private var captureRotation: AVCaptureDevice.RotationCoordinator?
    private var captureRotationObservation: NSKeyValueObservation?
    private var chosenMaxRate: Double = 120
    private var frameTimes: [CFTimeInterval] = []   // touched only on frameQueue
    private var lastPublishedFPS = 0                // touched only on frameQueue
    private var snapshotEnabled = false             // touched only on frameQueue; gates frozen-frame capture
    private let ciContext = CIContext()
    private var thermalPaused = false               // touched only on sessionQueue
    private var interruptionObservers: [NSObjectProtocol] = []

    deinit {
        interruptionObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// Starts capture using the format selector implied by `profile`. `.auto`
    /// keeps the existing 1080p·120 baseline (ThermalPolicy then adapts down).
    func start(profile: CaptureProfile) {
        selector = profile.formatSelector
        start()
    }

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
        case .restricted:
            // Parental controls / MDM: the user can't grant this in Settings, so
            // the UI must say so rather than offer a useless "Open Settings".
            setPermission(.restricted)
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

    // MARK: - Frozen-frame capture (M8: only produce CGImages when asked)

    /// Asks the frame pipeline to emit one fresh `latestImage`. Clears any stale
    /// frame so the calibration freeze waits for a new one.
    func requestFrozenFrame() {
        publishOnMain { self.latestImage = nil }
        frameQueue.async { [weak self] in self?.snapshotEnabled = true }
    }

    /// Stops producing `latestImage` once the freeze has its frame, so the live
    /// camera isn't churning full-resolution CGImages no one reads.
    func endFrozenFrameRequest() {
        frameQueue.async { [weak self] in self?.snapshotEnabled = false }
    }

    // MARK: - Configuration (session queue)

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureSession()
            if !self.session.isRunning { self.session.startRunning() }
            let running = self.session.isRunning
            let device = self.device
            self.publishOnMain {
                self.isRunning = running
                if let device { self.setupCaptureRotation(device: device) }
            }
        }
    }

    // MARK: - Rotation (frozen-frame capture)

    /// Keeps the video-output connection horizon-level so the frozen calibration
    /// frame is upright and matches the live preview. Created on the main thread;
    /// the connection mutation runs on the session queue.
    private func setupCaptureRotation(device: AVCaptureDevice) {
        guard captureRotation == nil else { return }
        let rc = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        captureRotation = rc
        applyCaptureAngle(rc.videoRotationAngleForHorizonLevelCapture)
        captureRotationObservation = rc.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] coord, _ in
            self?.applyCaptureAngle(coord.videoRotationAngleForHorizonLevelCapture)
        }
    }

    private func applyCaptureAngle(_ angle: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self,
                  let connection = self.videoOutput.connection(with: .video),
                  connection.isVideoRotationAngleSupported(angle) else { return }
            connection.videoRotationAngle = angle
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
            // Honor the selected profile's cap (e.g. 240 for 1080p·240) rather than
            // a hard-coded 120; ThermalPolicy still steps it down under heat.
            let rate = min(best.maxFrameRate, selector.maxFrameRate)
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

        // AVCaptureMovieFileOutput and a high-fps AVCaptureVideoDataOutput can coexist,
        // but sustained 4K/120 recording is large and hot. For personal use this is
        // acceptable; revisit if thermals bite (see CONSIDERATIONS.md).
        // Note: no audio input is added, so no microphone permission is required.
        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }

        session.commitConfiguration()
        observePressure(on: device)
        addInterruptionObservers()
    }

    /// Tracks session interruptions (phone call, another app taking the camera,
    /// being backgrounded) so `isRunning` reflects reality and capture resumes
    /// when the interruption ends.
    private func addInterruptionObservers() {
        guard interruptionObservers.isEmpty else { return }
        let nc = NotificationCenter.default
        interruptionObservers.append(
            nc.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) { [weak self] _ in
                self?.isRunning = false
            }
        )
        interruptionObservers.append(
            nc.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.sessionQueue.async {
                    if !self.session.isRunning { self.session.startRunning() }
                    let running = self.session.isRunning
                    self.publishOnMain { self.isRunning = running }
                }
            }
        )
    }

    private func observePressure(on device: AVCaptureDevice) {
        pressureObservation = device.observe(\.systemPressureState, options: [.initial, .new]) { [weak self] dev, _ in
            guard let self else { return }
            let rec = self.thermalPolicy.recommendation(for: CameraService.map(dev.systemPressureState.level))
            self.publishOnMain { self.thermal = rec }
            self.applyThermalCap(rec.frameRateCap)
        }
    }

    /// Re-applies the active frame duration if thermal pressure capped the rate,
    /// and actually pauses/resumes capture at the shutdown level.
    private func applyThermalCap(_ cap: Double?) {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            // Shutdown reports cap == 0 ("pause capture"). Actually stop the
            // session so reality matches the "capture paused" banner - otherwise
            // it kept running at full rate at the hottest moment.
            if let cap, cap == 0 {
                if self.session.isRunning { self.session.stopRunning() }
                self.thermalPaused = true
                self.publishOnMain { self.isRunning = false }
                return
            }

            guard let device = self.device else { return }

            // Pressure eased after a thermal pause - resume capture.
            if self.thermalPaused {
                self.thermalPaused = false
                if !self.session.isRunning { self.session.startRunning() }
                let running = self.session.isRunning
                self.publishOnMain { self.isRunning = running }
            }

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

    // MARK: - Clip recording

    /// Starts recording a clip. `courtID` is optional: pass nil for a quick capture
    /// with no court map yet (record-first flow); the clip is saved unbound.
    func startRecording(courtID: UUID? = nil) {
        sessionQueue.async { [weak self] in
            guard let self, !self.movieOutput.isRecording else { return }
            self.recordingCourtID = courtID
            // Snapshot frame metadata now (on sessionQueue) so the nonisolated
            // AVCaptureFileOutputRecordingDelegate callback can read them safely.
            self.recordingImageSize = self.imageSize
            self.recordingFPS = self.chosenMaxRate
            let name = "\(UUID().uuidString).mov"
            let url = URL.documentsDirectory.appendingPathComponent("clips").appendingPathComponent(name)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
            self.publishOnMain { self.isRecording = true }
        }
    }

    func stopRecording() {
        sessionQueue.async { [weak self] in
            guard let self, self.movieOutput.isRecording else { return }
            self.movieOutput.stopRecording()
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

        // Frozen-frame snapshot - only while a calibration freeze is requested,
        // so the live camera doesn't build full-resolution CGImages no one reads.
        if snapshotEnabled, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let ci = CIImage(cvPixelBuffer: pixelBuffer)
            let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                              height: CVPixelBufferGetHeight(pixelBuffer))
            if let cg = ciContext.createCGImage(ci, from: ci.extent) {
                publishOnMain {
                    self.latestImage = cg
                    self.imageSize = size
                }
            }
        }
    }
}

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection], error: Error?) {
        // Use nonisolated(unsafe) snapshot properties set on sessionQueue at record-start.
        // courtID stays nil for a quick (court-less) capture - do not fabricate one.
        let courtID = recordingCourtID
        let size = recordingImageSize
        let fps = recordingFPS
        DispatchQueue.main.async { self.isRecording = false }
        guard error == nil else { return }   // dismissable failure: just leave isRecording false
        let clip = SessionClip(courtID: courtID, fileName: outputFileURL.lastPathComponent,
                               fps: fps, frameWidth: size.width, frameHeight: size.height,
                               recordedAt: Date())
        try? clipStore.save(clip)
        DispatchQueue.main.async { self.lastSavedClip = clip }
    }
}
