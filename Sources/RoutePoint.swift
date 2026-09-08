import Foundation
import CoreLocation

/// One GPS sample along a trip's path.
///
/// The trail of these is what the route map draws (Step 5) and what road matching
/// runs against — snapping to roads and looking up speed limits are batch requests
/// over a finished trip's trail, not per-fix calls during the drive, which is both
/// far cheaper on any paid API and more accurate (a matcher sees the whole path).
///
/// `CLLocationCoordinate2D` isn't `Codable`, hence the flat lat/lon pair.
/// `horizontalAccuracy` is kept because map-matching services take a per-point
/// accuracy to weight candidate road segments.
struct RoutePoint: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let speedMph: Double
    let horizontalAccuracy: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
