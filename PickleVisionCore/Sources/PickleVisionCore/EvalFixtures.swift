import CoreGraphics
import Foundation

// MARK: - TrajectoryFixture

/// A self-contained, deterministic eval fixture: a court (image corners + layout) plus a
/// raw `[BallObservation]` sequence and the `[ReferenceBounce]` ground truth for it.
///
/// This is the first, cheapest fixture level (Phase B5): hand-authored or hand-labeled
/// trajectories that replay through `RefereeCore.evaluate` in `swift test` with zero ML
/// and zero device dependency. They catch core regressions (a `Tracker`/`BounceDetector`/
/// `LineJudge` change that shifts a verdict). Stored as JSON; verdicts are string-coded so
/// a fixture stays readable and hand-editable.
public struct TrajectoryFixture: Equatable, Codable {
    /// Human-readable label for the fixture.
    public var name: String
    /// Normalized [0,1] image corners of the court, order [nearLeft, nearRight, farRight, farLeft].
    public var imageCorners: [CGPoint]
    /// The court layout this trajectory was shot on.
    public var layout: CourtLayout
    /// Custom court dimensions when `layout == .custom`; otherwise nil.
    public var customDimensions: CustomDimensions?
    /// The raw detections to replay (any order/confidence; the Tracker cleans them up).
    public var observations: [BallObservation]
    /// Ground-truth bounces for this trajectory.
    public var reference: [ReferenceBounce]

    public init(
        name: String,
        imageCorners: [CGPoint],
        layout: CourtLayout,
        customDimensions: CustomDimensions? = nil,
        observations: [BallObservation],
        reference: [ReferenceBounce]
    ) {
        self.name = name
        self.imageCorners = imageCorners
        self.layout = layout
        self.customDimensions = customDimensions
        self.observations = observations
        self.reference = reference
    }

    /// Rebuilds the `CourtModel` this fixture was labeled against. Returns nil only when
    /// the corners are degenerate (the same guard `CalibrationDraft` applies everywhere).
    public func courtModel() -> CourtModel? {
        CalibrationDraft(corners: imageCorners, layout: layout, customDimensions: customDimensions).courtModel()
    }
}

// MARK: - ClipLabel

/// Ground-truth labels for one recorded clip: the bounces a human marked via the in-app
/// tap-test, keyed to the clip they belong to.
///
/// This is the second, higher-cost fixture level (Phase B5): a real `SessionClip`
/// (already a JSON sidecar per Phase A) plus this label sidecar. `clipID` matches
/// `SessionClip.id`. The format is scaffolded now so labeling is ready the moment Phase A
/// produces real on-device clips; populating it (and running the full B3 detector pipeline
/// against it) is the works-on-a-real-court gate and is deferred until those clips exist.
public struct ClipLabel: Equatable, Codable {
    /// The id of the `SessionClip` these labels belong to.
    public var clipID: UUID
    /// Ground-truth bounces for the clip, captured through the tap-test.
    public var reference: [ReferenceBounce]

    public init(clipID: UUID, reference: [ReferenceBounce]) {
        self.clipID = clipID
        self.reference = reference
    }
}
