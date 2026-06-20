import CoreGraphics

public enum CalibrationStep: Int, CaseIterable, Equatable {
    case position, detect, fineTune, verify
}

/// ADVISORY ONLY — informs guidance copy, never gates a transition.
public struct SetupChecks: Equatable {
    public var steady: Bool
    public var framed: Bool
    public var angle: Bool

    public init(steady: Bool = false, framed: Bool = false, angle: Bool = false) {
        self.steady = steady
        self.framed = framed
        self.angle = angle
    }

    public var passingCount: Int { [steady, framed, angle].filter { $0 }.count }
    public var total: Int { 3 }
}

public enum AutoDetectState: Equatable {
    case idle, finding, found, failed
}

/// Pure calibration state. SwiftUI view-model wraps this; all transitions are
/// total (no transition is ever blocked by a check or a CV result).
public struct CalibrationFlow: Equatable {
    public private(set) var step: CalibrationStep
    public var checks: SetupChecks
    public var autoDetect: AutoDetectState

    // Draft fields
    public var corners: [CGPoint]               // normalized image, [NL,NR,FR,FL]
    public var layout: CourtLayout
    public var customDimensions: CustomDimensions?
    public var overlayVisible: Bool
    public var tapPoint: CGPoint?               // normalized image point of last tap-test

    public init(step: CalibrationStep = .position,
                corners: [CGPoint] = CalibrationDraft.defaultCorners(),
                layout: CourtLayout = .regulationPickleball,
                customDimensions: CustomDimensions? = nil) {
        self.step = step
        self.checks = SetupChecks()
        self.autoDetect = .idle
        // Guard the never-block invariant: a wrong-count corner array (corrupt or
        // legacy record) would leave the drag UI without a valid quad. Fall back
        // to the default starting quad so the user always lands on something editable.
        self.corners = (corners.count == 4) ? corners : CalibrationDraft.defaultCorners()
        self.layout = layout
        self.customDimensions = customDimensions
        self.overlayVisible = (step == .fineTune || step == .verify)
        self.tapPoint = nil
    }

    // MARK: - Derived

    public var draft: CalibrationDraft {
        CalibrationDraft(corners: corners, layout: layout, customDimensions: customDimensions)
    }

    public var courtModel: CourtModel? { draft.courtModel() }

    /// Always 4 once defaults/loaded; for "N/4 corners set" display.
    public var cornersSetCount: Int { min(corners.count, 4) }

    public var isComplete: Bool { draft.isComplete }

    public var fitQuality: (quality: FitQuality, score: Double) {
        FitQuality.evaluate(corners: corners, layout: layout, customDimensions: customDimensions)
    }

    // MARK: - Transitions (ALL total, none gated by checks or autoDetect)

    /// Turns the court overlay on whenever a transition lands on a calibrating
    /// step (fine-tune / verify), so the standard manual path shows the overlay
    /// to drag — matching express re-cal. The user's toggle can still turn it off
    /// while on that step; arriving fresh always defaults it on.
    private mutating func showOverlayIfCalibrating() {
        if step == .fineTune || step == .verify { overlayVisible = true }
    }

    public mutating func goToStep(_ s: CalibrationStep) {
        step = s
        showOverlayIfCalibrating()
    }

    /// Advance through the step sequence, clamped at .verify.
    public mutating func advance() {
        let next = min(step.rawValue + 1, CalibrationStep.verify.rawValue)
        step = CalibrationStep(rawValue: next)!
        showOverlayIfCalibrating()
    }

    /// Go back through the step sequence, clamped at .position.
    public mutating func back() {
        let prev = max(step.rawValue - 1, CalibrationStep.position.rawValue)
        step = CalibrationStep(rawValue: prev)!
        showOverlayIfCalibrating()
    }

    /// "Continue anyway" from Position. Always succeeds regardless of checks.
    public mutating func continueFromPosition() {
        step = .detect     // ignores checks entirely — no guard
    }

    /// "Calibrate manually" — skip auto-detect, jump straight to Fine-tune.
    /// Always allowed from any step.
    public mutating func calibrateManually() {
        step = .fineTune
        showOverlayIfCalibrating()
    }

    /// Begin a stubbed auto-detect. In v1 the engine is not present.
    public mutating func startAutoDetect() {
        step = .detect
        autoDetect = .finding
    }

    /// Engine result hook (Plan 3.5 calls this; v1 stub resolves to .failed).
    public mutating func resolveAutoDetect(_ result: AutoDetectState, detectedCorners: [CGPoint]?) {
        if result == .found {
            if let c = detectedCorners, c.count == 4 {
                autoDetect = .found
                corners = c
            } else {
                // A "found" without a valid 4-corner quad isn't a real detection;
                // treat it as failed so the guaranteed manual path stays the
                // source of truth (never-block invariant).
                autoDetect = .failed
            }
        } else {
            autoDetect = result
        }
        // On .failed, step is intentionally left unchanged so the manual path stays reachable.
    }

    /// From a failed/any auto-detect, drop to the guaranteed manual path.
    /// Corners remain whatever they are — defaults if detect never populated them.
    public mutating func dropToManual() {
        step = .fineTune
        showOverlayIfCalibrating()
    }

    /// Express re-calibration: preload a saved court and land on Fine-tune.
    public static func forExpressReCal(corners: [CGPoint],
                                       layout: CourtLayout,
                                       customDimensions: CustomDimensions?) -> CalibrationFlow {
        var f = CalibrationFlow(step: .fineTune,
                                corners: corners,
                                layout: layout,
                                customDimensions: customDimensions)
        f.overlayVisible = true
        return f
    }
}
