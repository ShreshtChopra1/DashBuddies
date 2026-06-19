import Foundation

/// How a harsh event manifested.
///
/// The phone's orientation in the car is unknown (see CLAUDE.md), so we can't
/// yet tell braking from acceleration — both are longitudinal g-force. We *can*
/// separate turning, since hard cornering shows up as strong rotation on the
/// gyroscope. Splitting brake vs. accel needs the axis-calibration step.
enum DriveEventKind: String, Codable {
    case hardBrakingOrAccel
    case hardCornering

    var label: String {
        switch self {
        case .hardBrakingOrAccel: return "Hard braking / acceleration"
        case .hardCornering:      return "Hard cornering"
        }
    }

    /// SF Symbol used in the summary list.
    var symbol: String {
        switch self {
        case .hardBrakingOrAccel: return "car.fill"
        case .hardCornering:      return "arrow.triangle.turn.up.right.diamond.fill"
        }
    }
}

/// Severity of a single harsh event, derived from its peak g-force.
/// Anything gentler than the harsh threshold isn't recorded as an event at all.
enum EventSeverity: String, Codable {
    case harsh
    case severe

    var label: String {
        switch self {
        case .harsh:  return "Harsh"
        case .severe: return "Severe"
        }
    }

    /// Points deducted from the trip score for one event of this severity.
    var penalty: Int {
        switch self {
        case .harsh:  return 5
        case .severe: return 10
        }
    }
}

/// One harsh-driving event detected during a trip. Codable so it persists as
/// part of the trip history.
struct DriveEvent: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let kind: DriveEventKind
    let severity: EventSeverity
    let peakG: Double          // peak linear-acceleration magnitude during the event, in g
    let peakRotation: Double   // peak rotation-rate magnitude during the event, rad/s

    init(id: UUID = UUID(),
         timestamp: Date = Date(),
         kind: DriveEventKind,
         severity: EventSeverity,
         peakG: Double,
         peakRotation: Double) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.severity = severity
        self.peakG = peakG
        self.peakRotation = peakRotation
    }
}
