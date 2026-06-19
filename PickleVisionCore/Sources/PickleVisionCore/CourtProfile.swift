import CoreGraphics

public enum CourtLayout: String, Codable {
    case regulationPickleball
    case tennisFrontBox
    case custom
}

public struct CustomDimensions: Codable, Equatable {
    public var widthFeet: Double
    public var lengthFeet: Double
    public var nonVolleyZoneFeet: Double

    public init(widthFeet: Double, lengthFeet: Double, nonVolleyZoneFeet: Double) {
        self.widthFeet = widthFeet
        self.lengthFeet = lengthFeet
        self.nonVolleyZoneFeet = nonVolleyZoneFeet
    }
}

/// Real-world geometry for a supported court layout, in feet, using the
/// near-left-origin convention (see plan Global Constraints).
public struct CourtProfile: Equatable {
    public let layout: CourtLayout
    public let widthFeet: Double
    public let lengthFeet: Double
    public let nonVolleyZoneFeet: Double
    /// [nearLeft, nearRight, farRight, farLeft].
    public let calibrationCorners: [CGPoint]
    public let inBoundsPolygon: [CGPoint]
    public let netLine: [CGPoint]        // two endpoints
    public let nvzLines: [[CGPoint]]     // each two endpoints

    public static func make(layout: CourtLayout, custom: CustomDimensions? = nil) -> CourtProfile {
        switch layout {
        case .regulationPickleball:
            return CourtProfile(width: 20, length: 44, nvz: 7, layout: .regulationPickleball)
        case .tennisFrontBox:
            return CourtProfile(width: 27, length: 42, nvz: 7, layout: .tennisFrontBox)
        case .custom:
            let d = custom ?? CustomDimensions(widthFeet: 20, lengthFeet: 44, nonVolleyZoneFeet: 7)
            return CourtProfile(width: d.widthFeet, length: d.lengthFeet, nvz: d.nonVolleyZoneFeet, layout: .custom)
        }
    }

    private init(width w: Double, length l: Double, nvz: Double, layout: CourtLayout) {
        self.layout = layout
        self.widthFeet = w
        self.lengthFeet = l
        self.nonVolleyZoneFeet = nvz

        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: w, y: 0),
                       CGPoint(x: w, y: l), CGPoint(x: 0, y: l)]
        self.calibrationCorners = corners
        self.inBoundsPolygon = corners

        let mid = l / 2
        self.netLine = [CGPoint(x: 0, y: mid), CGPoint(x: w, y: mid)]
        self.nvzLines = [
            [CGPoint(x: 0, y: mid - nvz), CGPoint(x: w, y: mid - nvz)],
            [CGPoint(x: 0, y: mid + nvz), CGPoint(x: w, y: mid + nvz)],
        ]
    }
}
