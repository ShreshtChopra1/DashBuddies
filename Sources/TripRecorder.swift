import Foundation
import CoreLocation
import CoreMotion

/// Captures live GPS + motion during a trip, detects harsh-driving events, and
/// on Stop rolls everything into a scored, persisted `Trip` (Step 2).
final class TripRecorder: NSObject, ObservableObject {

    // Live values the UI reads while recording.
    @Published var isRecording = false
    @Published var speedMph: Double = 0
    @Published var accelMagnitude: Double = 0   // in g — smoothed horizontal (driving-plane) acceleration
    @Published var carTurnRate: Double = 0      // deg/s — how fast the CAR's course over the ground is changing
    @Published var harshEvents: Int = 0
    @Published var statusMessage = "Idle"

    /// Set when a trip ends; the UI observes this to present the summary screen.
    @Published var finishedTrip: Trip?

    // MARK: - Harsh-event thresholds (tune with real drive data)
    //
    // Detection runs on the *horizontal* (driving-plane) acceleration magnitude,
    // in g — see `startMotion()`, which projects out the vertical axis using the
    // gravity vector so speed bumps and potholes (a vertical jolt) don't register
    // as harsh driving. For reference: a comfortable stop is ~0.1–0.25 g and
    // firm-but-fine braking ~0.3 g, so these thresholds sit well above everyday
    // driving. Combined with the hysteresis + peak-hold below, one continuous
    // maneuver becomes exactly ONE event, classified by its peak.
    private let harshThreshold = 0.45            // g: an event must peak at/above this to count
    private let releaseThreshold = 0.25          // g: the event ends once we settle back below this
    private let severeThreshold = 0.65           // g: a peak at/above this is "severe", not just "harsh"
    private let corneringTurnThreshold = 18.0    // deg/s of car yaw ⇒ label the event as cornering
    private let minDrivingSpeedMph = 5.0         // below this, an accel spike is phone-handling, not driving

    // The live dashboard readouts (g-force, turn rate) are smoothed with an
    // exponential moving average so they read steady instead of flickering at the
    // 20 Hz sensor rate. Detection still runs on the *raw* peaks (see ingestMotion),
    // so a genuine spike is never smoothed away — only the on-screen number is calm.
    private let displaySmoothing = 0.25          // EMA factor for g-force (0 = frozen, 1 = no smoothing)
    private let turnSmoothing = 0.5              // EMA factor for turn rate (applied at the ~1 Hz fix rate)
    private let speedDeadbandMph = 1.5           // below this the filtered speed is GPS noise ⇒ show a clean 0
    private let maxPlausibleTurnRate = 90.0      // deg/s: above this it's a GPS course glitch, not a car

    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionManager()
    private let motionQueue = OperationQueue()

    private let store: TripStore

    // Recording accumulators (all read/written on the main thread).
    private var startDate: Date?
    private var recordedEvents: [DriveEvent] = []
    private var distanceMeters: Double = 0
    private var topSpeedMph: Double = 0
    private var lastLocation: CLLocation?
    private var speedFilter = KalmanSpeedFilter()
    private var peakAccelMagSinceLastFix: Double = 0   // g (horizontal); drives adaptive smoothing
    private var motionAvailable = false

    // Smoothed dashboard readouts (see `displaySmoothing` / `turnSmoothing`).
    private var accelDisplayEMA: Double = 0      // g
    private var turnDisplayEMA: Double = 0       // deg/s

    // Car heading tracking, for turn rate. Derived from the car's course over the
    // ground, so rotating the phone inside the car has no effect on it.
    private var lastCourse: Double?              // previous course, degrees
    private var lastCourseTime: Date?

    /// Every GPS fix of the trip, for the route map / road matching (Step 5).
    private var routePoints: [RoutePoint] = []

    // Harsh-event detector state (hysteresis + peak hold).
    private var inEvent = false
    private var eventPeakG: Double = 0
    private var eventPeakTurnRate: Double = 0

    init(store: TripStore) {
        self.store = store
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .automotiveNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone   // every fix, not distance-gated
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    /// Ask for "Always" location so trips can record in the background.
    func requestPermissions() {
        locationManager.requestAlwaysAuthorization()
    }

    func start() {
        guard !isRecording else { return }
        startDate = Date()
        recordedEvents = []
        distanceMeters = 0
        topSpeedMph = 0
        lastLocation = nil
        speedFilter.reset()
        peakAccelMagSinceLastFix = 0
        carTurnRate = 0
        accelDisplayEMA = 0
        turnDisplayEMA = 0
        lastCourse = nil
        lastCourseTime = nil
        routePoints = []
        inEvent = false
        eventPeakG = 0
        eventPeakTurnRate = 0
        harshEvents = 0
        speedMph = 0
        finishedTrip = nil
        isRecording = true
        statusMessage = "Recording trip…"

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            // Only allow background updates if we're actually authorized for it.
            locationManager.allowsBackgroundLocationUpdates = true
        case .denied, .restricted:
            statusMessage = "Location is off — enable it in Settings to read speed."
        default:
            break
        }
        locationManager.startUpdatingLocation()
        startMotion()
        print("=== Trip started ===")
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.stopUpdatingLocation()
        motionManager.stopDeviceMotionUpdates()

        // Flush an event that was still in progress when the user hit Stop.
        if inEvent {
            recordedEvents.append(makeEvent(peakG: eventPeakG, peakTurnRate: eventPeakTurnRate))
            inEvent = false
        }

        let end = Date()
        let start = startDate ?? end
        let distanceMiles = distanceMeters / 1609.344
        let trip = Trip(
            startDate: start,
            endDate: end,
            distanceMiles: distanceMiles,
            topSpeedMph: topSpeedMph,
            events: recordedEvents,
            score: TripScorer.score(events: recordedEvents,
                                    distanceMiles: distanceMiles,
                                    duration: end.timeIntervalSince(start)),
            route: routePoints
        )
        store.add(trip)
        finishedTrip = trip
        harshEvents = recordedEvents.count
        statusMessage = "Trip saved — score \(trip.score)/100"
        print("=== Trip ended. Score \(trip.score)/100, \(recordedEvents.count) harsh events ===")
    }

    private func startMotion() {
        guard motionManager.isDeviceMotionAvailable else {
            statusMessage = "Motion unavailable — run on a real iPhone."
            print("⚠️ Device motion unavailable — you're probably on the Simulator. Run on a real iPhone for accelerometer/gyro data.")
            return
        }
        motionAvailable = true
        motionManager.deviceMotionUpdateInterval = 1.0 / 20.0   // 20 Hz
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            // The phone's orientation in the car is unknown, but `gravity` always
            // points down, so we use it as our reference for both signals below.
            let a = motion.userAcceleration          // linear acceleration, in g
            let g = motion.gravity                   // gravity direction, in g (unit-ish)
            let gMag = sqrt(g.x * g.x + g.y * g.y + g.z * g.z)

            // Detect on *horizontal* (driving-plane) acceleration only. Project
            // userAcceleration onto gravity to get the vertical part and subtract
            // it, so speed bumps/potholes (a vertical jolt) don't register.
            let vertical = gMag > 0 ? (a.x * g.x + a.y * g.y + a.z * g.z) / gMag : 0
            let totalSq = a.x * a.x + a.y * a.y + a.z * a.z
            let horizontal = totalSq > vertical * vertical ? sqrt(totalSq - vertical * vertical) : 0

            // NOTE: the gyroscope is deliberately NOT used for turn rate. It measures
            // the *phone* rotating, which is not the same as the car turning — a phone
            // sliding in a cupholder during a hard brake would read as a big yaw and
            // mislabel that brake as cornering. Turn rate comes from the car's course
            // over the ground instead (see `ingestLocation`).
            DispatchQueue.main.async { self.ingestMotion(horizontalG: horizontal) }
        }
    }

    /// Runs on the main thread at the 20 Hz sensor rate. Smooths the live readouts
    /// for the dashboard and drives the harsh-event state machine on the *raw* peaks:
    /// an event opens when the raw horizontal g crosses `harshThreshold`, holds the
    /// peak while it stays elevated, and closes — emitting exactly one `DriveEvent` —
    /// once it settles back below `releaseThreshold`.
    private func ingestMotion(horizontalG rawG: Double) {
        let drivingNow = speedMph >= minDrivingSpeedMph

        // Smoothed value feeds the UI; raw peaks feed the detector below.
        accelDisplayEMA += displaySmoothing * (rawG - accelDisplayEMA)
        accelMagnitude = accelDisplayEMA

        peakAccelMagSinceLastFix = max(peakAccelMagSinceLastFix, rawG)
        guard isRecording else { return }

        if !inEvent {
            // Only open an event while actually driving — below ~5 mph an accel
            // spike is the phone being handled, not the car.
            if rawG >= harshThreshold, drivingNow {
                inEvent = true
                eventPeakG = rawG
                eventPeakTurnRate = carTurnRate
            }
        } else {
            eventPeakG = max(eventPeakG, rawG)
            eventPeakTurnRate = max(eventPeakTurnRate, carTurnRate)
            if rawG < releaseThreshold {
                let event = makeEvent(peakG: eventPeakG, peakTurnRate: eventPeakTurnRate)
                recordedEvents.append(event)
                harshEvents = recordedEvents.count
                inEvent = false
                eventPeakG = 0
                eventPeakTurnRate = 0
                print(String(format: "⚡️ %@ (%@) — peak %.2f g, turn %.0f°/s",
                             event.kind.label, event.severity.label, event.peakG, event.peakRotation))
            }
        }
    }

    private func makeEvent(peakG: Double, peakTurnRate: Double) -> DriveEvent {
        let severity: EventSeverity = peakG >= severeThreshold ? .severe : .harsh
        let kind: DriveEventKind = peakTurnRate >= corneringTurnThreshold ? .hardCornering : .hardBrakingOrAccel
        return DriveEvent(kind: kind, severity: severity, peakG: peakG, peakRotation: peakTurnRate)
    }

    /// Car turn rate, in deg/s, from how fast its *course over the ground* is
    /// changing. This is a property of the car's path, so rotating the phone inside
    /// the car cannot affect it — unlike the gyroscope, which measures the phone.
    ///
    /// Course is only meaningful while moving, so below `minDrivingSpeedMph` we
    /// decay toward zero and drop the reference heading (rather than snapping to 0
    /// and differencing against a stale heading when we move off again, which is
    /// what made the old version read 0°/s almost always).
    private func updateTurnRate(for loc: CLLocation, speedMph mph: Double) {
        guard mph >= minDrivingSpeedMph, let course = courseDegrees(for: loc) else {
            turnDisplayEMA *= 0.5
            carTurnRate = turnDisplayEMA
            lastCourse = nil
            lastCourseTime = nil
            return
        }

        if let prev = lastCourse, let prevTime = lastCourseTime {
            let dt = loc.timestamp.timeIntervalSince(prevTime)
            // Reject implausible jumps — a real car tops out well under 90°/s, so
            // anything above that is a GPS course glitch, not a maneuver.
            if dt > 0.05 {
                let rate = abs(TripRecorder.angularDifferenceDegrees(course, prev)) / dt
                if rate <= maxPlausibleTurnRate {
                    turnDisplayEMA += turnSmoothing * (rate - turnDisplayEMA)
                }
            }
        }
        carTurnRate = turnDisplayEMA
        lastCourse = course
        lastCourseTime = loc.timestamp
    }

    /// The car's heading: the GPS Doppler course when it's valid, otherwise the
    /// bearing between this fix and the previous one.
    private func courseDegrees(for loc: CLLocation) -> Double? {
        if loc.course >= 0, loc.courseAccuracy >= 0 { return loc.course }
        guard let last = lastLocation, loc.distance(from: last) >= 5 else { return nil }
        return TripRecorder.bearingDegrees(from: last.coordinate, to: loc.coordinate)
    }

    /// Smallest signed angle from `b` to `a` in degrees, handling 0/360 wraparound.
    private static func angularDifferenceDegrees(_ a: Double, _ b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 } else if d < -180 { d += 360 }
        return d
    }

    /// Initial great-circle bearing from `a` to `b`, in degrees (0–360).
    private static func bearingDegrees(from a: CLLocationCoordinate2D,
                                       to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let deg = atan2(y, x) * 180 / .pi
        return deg < 0 ? deg + 360 : deg
    }
}

extension TripRecorder: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        // Drop invalid, too-coarse, or stale fixes. Core Location often delivers a
        // cached location first, and a 1-km-accuracy cell fix would wreck the math.
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 100 else { return }
        guard -loc.timestamp.timeIntervalSinceNow < 5 else { return }
        // Hop to main so all speed/distance state stays single-threaded.
        DispatchQueue.main.async { self.ingestLocation(loc) }
    }

    /// Runs on the main thread. Computes a Kalman-filtered speed and trip distance.
    private func ingestLocation(_ loc: CLLocation) {
        // Time since the previous fix — drives the filter's prediction step.
        let dt: Double
        if let last = lastLocation {
            dt = loc.timestamp.timeIntervalSince(last.timestamp)
            guard dt > 0 else { return }   // ignore duplicate / out-of-order fixes
        } else {
            dt = 1.0
        }

        // Build a speed measurement and how much to trust it (its variance).
        // The GPS Doppler speed (`loc.speed`) is best when the device reports a
        // valid `speedAccuracy`; otherwise we derive speed from the distance moved,
        // which is noisier — so it gets a larger variance and the filter leans on
        // its prediction instead of jumping.
        let measurement: Double
        let variance: Double
        if loc.speed >= 0, loc.speedAccuracy >= 0 {
            measurement = loc.speed
            let sigma = max(loc.speedAccuracy, 0.5)        // floor avoids over-trusting one reading
            variance = sigma * sigma
        } else if let last = lastLocation {
            measurement = loc.distance(from: last) / dt
            let sigma = max(loc.horizontalAccuracy, 5) / dt
            variance = sigma * sigma
        } else {
            lastLocation = loc                              // first fix, no Doppler → wait for the next
            return
        }

        // Adaptive smoothing: the peak horizontal g since the last fix (→ m/s²)
        // tells the filter how much the speed could really be changing. Cruising
        // (~0 g) smooths hard; accelerating/braking loosens it so it tracks the
        // change. Without the accelerometer (e.g. Simulator) use a fixed value.
        let accelMps2 = peakAccelMagSinceLastFix * 9.81
        peakAccelMagSinceLastFix = 0
        let floor = motionAvailable ? 0.35 : 3.0
        let processNoise = max(floor, accelMps2 * 1.6)

        let filtered = speedFilter.update(measurement: measurement, variance: variance,
                                          dt: dt, accelerationNoise: processNoise)
        // Below a walking pace the filtered residual is GPS noise, not real motion,
        // so show a clean 0 instead of a phantom "3 mph" while parked at a light.
        let filteredMph = max(0, filtered) * 2.23694
        let mph = filteredMph < speedDeadbandMph ? 0 : filteredMph
        speedMph = mph

        updateTurnRate(for: loc, speedMph: mph)

        if isRecording {
            topSpeedMph = max(topSpeedMph, mph)
            if let last = lastLocation {
                let step = loc.distance(from: last)
                // Drop GPS "teleport" glitches; otherwise accumulate trip distance.
                if step.isFinite, step < 1000 { distanceMeters += step }
            }
            // Keep the breadcrumb trail: it drives the route map, and road matching
            // / speed limits are batch lookups over this trail after the trip ends.
            routePoints.append(RoutePoint(latitude: loc.coordinate.latitude,
                                          longitude: loc.coordinate.longitude,
                                          timestamp: loc.timestamp,
                                          speedMph: mph,
                                          horizontalAccuracy: loc.horizontalAccuracy))
        }
        lastLocation = loc
        print(String(format: "📍 acc=%.0fm sAcc=%.1f  raw=%.1f  filtered=%.1f mph",
                     loc.horizontalAccuracy, loc.speedAccuracy,
                     max(0, measurement) * 2.23694, mph))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        switch status {
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.statusMessage = "Location is off — enable it in Settings to read speed."
            }
        case .authorizedAlways:
            if isRecording { manager.allowsBackgroundLocationUpdates = true }
        default:
            break
        }
        print("Location auth status: \(status.rawValue)")
    }
}
