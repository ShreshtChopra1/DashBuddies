import Foundation

/// Turns a trip's harsh events into a 0–100 safety score.
///
/// Step 2 keeps this deliberately simple and transparent: start at 100 and
/// subtract a fixed penalty per event by severity (see `EventSeverity.penalty`).
/// `distanceMiles` and `duration` are passed in (and stored on the `Trip`) so a
/// later step can normalise penalties per mile — five events shouldn't mean the
/// same thing on a 2-mile errand as on a 200-mile highway haul.
enum TripScorer {
    static func score(events: [DriveEvent],
                      distanceMiles: Double,
                      duration: TimeInterval) -> Int {
        let penalty = events.reduce(0) { $0 + $1.severity.penalty }
        return max(0, min(100, 100 - penalty))
    }
}
