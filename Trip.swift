import Foundation

/// A completed trip: its telematics summary, the harsh events we detected, and
/// the 0–100 safety score. Codable so trip history can be persisted to disk.
struct Trip: Identifiable, Codable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let distanceMiles: Double
    let topSpeedMph: Double
    let events: [DriveEvent]
    let score: Int

    init(id: UUID = UUID(),
         startDate: Date,
         endDate: Date,
         distanceMiles: Double,
         topSpeedMph: Double,
         events: [DriveEvent],
         score: Int) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.distanceMiles = distanceMiles
        self.topSpeedMph = topSpeedMph
        self.events = events
        self.score = score
    }

    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }

    var severeCount: Int { events.lazy.filter { $0.severity == .severe }.count }

    func eventCount(of kind: DriveEventKind) -> Int {
        events.lazy.filter { $0.kind == kind }.count
    }
}
