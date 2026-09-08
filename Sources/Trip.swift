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
    /// The GPS trail of the drive. Empty for trips recorded before routes existed.
    let route: [RoutePoint]

    init(id: UUID = UUID(),
         startDate: Date,
         endDate: Date,
         distanceMiles: Double,
         topSpeedMph: Double,
         events: [DriveEvent],
         score: Int,
         route: [RoutePoint] = []) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.distanceMiles = distanceMiles
        self.topSpeedMph = topSpeedMph
        self.events = events
        self.score = score
        self.route = route
    }

    /// Decoded by hand so trips saved before `route` existed still load. `TripStore`
    /// decodes the whole history in one `[Trip]` call, so a single trip that failed
    /// to decode would throw away every saved trip.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        startDate = try c.decode(Date.self, forKey: .startDate)
        endDate = try c.decode(Date.self, forKey: .endDate)
        distanceMiles = try c.decode(Double.self, forKey: .distanceMiles)
        topSpeedMph = try c.decode(Double.self, forKey: .topSpeedMph)
        events = try c.decode([DriveEvent].self, forKey: .events)
        score = try c.decode(Int.self, forKey: .score)
        route = try c.decodeIfPresent([RoutePoint].self, forKey: .route) ?? []
    }

    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }

    var severeCount: Int { events.lazy.filter { $0.severity == .severe }.count }

    func eventCount(of kind: DriveEventKind) -> Int {
        events.lazy.filter { $0.kind == kind }.count
    }
}
