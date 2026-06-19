import Foundation
import CoreLocation
import CoreMotion

/// Captures live GPS + motion during a trip, detects harsh-driving events, and
/// on Stop rolls everything into a scored, persisted `Trip` (Step 2).
final class TripRecorder: NSObject, ObservableObject {

    // Live values the UI reads while recording.
    @Published var isRecording = false
    @Published var speedMph: Double = 0
    @Published var accelMagnitude: Double = 0   // in g
    @Published var carTurnRate: Double = 0      // deg/s — the CAR's turn rate from GPS course, not the phone's
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
    private let corneringRotationThreshold = 0.9 // rad/s: strong rotation ⇒ label the event as cornering

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

    // Harsh-event detector state (hysteresis + peak hold).
    private var inEvent = false
    private var eventPeakG: Double = 0
    private var eventPeakRotation: Double = 0

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
        inEvent = false
        eventPeakG = 0
        eventPeakRotation = 0
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
            recordedEvents.append(makeEvent(peakG: eventPeakG, peakRotation: eventPeakRotation))
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
                                    duration: end.timeIntervalSince(start))
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
            // Detect on *horizontal* acceleration only. The phone's orientation in
            // the car is unknown, but `gravity` always points down, so we project
            // userAcceleration onto it to get the vertical part and subtract it.
            // Speed bumps and potholes live in that vertical axis — excluding it
            // stops them from counting as harsh events.
            let a = motion.userAcceleration
            let g = motion.gravity
            let gMag = sqrt(g.x * g.x + g.y * g.y + g.z * g.z)
            let vertical = gMag > 0 ? (a.x * g.x + a.y * g.y + a.z * g.z) / gMag : 0
            let totalSq = a.x * a.x + a.y * a.y + a.z * a.z
            let horizontal = totalSq > vertical * vertical ? sqrt(totalSq - vertical * vertical) : 0
            let r = motion.rotationRate
            let rot = sqrt(r.x * r.x + r.y * r.y + r.z * r.z)
            // Hop to main so all detector/accumulator state stays single-threaded.
            DispatchQueue.main.async { self.ingestMotion(magnitude: horizontal, rotation: rot) }
        }
    }

    /// Runs on the main thread. Drives the harsh-event state machine:
    /// an event opens when magnitude crosses `harshThreshold`, holds the peak
    /// while it stays elevated, and closes — emitting exactly one `DriveEvent` —
    /// once magnitude settles back below `releaseThreshold`.
    private func ingestMotion(magnitude mag: Double, rotation rot: Double) {
        accelMagnitude = mag
        rotationRate = rot
        peakAccelMagSinceLastFix = max(peakAccelMagSinceLastFix, mag)
        guard isRecording else { return }

        if !inEvent {
            if mag >= harshThreshold {
                inEvent = true
                eventPeakG = mag
                eventPeakRotation = rot
            }
        } else {
            eventPeakG = max(eventPeakG, mag)
            eventPeakRotation = max(eventPeakRotation, rot)
            if mag < releaseThreshold {
                let event = makeEvent(peakG: eventPeakG, peakRotation: eventPeakRotation)
                recordedEvents.append(event)
                harshEvents = recordedEvents.count
                inEvent = false
                eventPeakG = 0
                eventPeakRotation = 0
                print(String(format: "⚡️ %@ (%@) — peak %.2f g",
                             event.kind.label, event.severity.label, event.peakG))
            }
        }
    }

    private func makeEvent(peakG: Double, peakRotation: Double) -> DriveEvent {
        let severity: EventSeverity = peakG >= severeThreshold ? .severe : .harsh
        let kind: DriveEventKind = peakRotation >= corneringRotationThreshold ? .hardCornering : .hardBrakingOrAccel
        return DriveEvent(kind: kind, severity: severity, peakG: peakG, peakRotation: peakRotation)
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
        let mph = max(0, filtered) * 2.23694
        speedMph = mph

        if isRecording {
            topSpeedMph = max(topSpeedMph, mph)
            if let last = lastLocation {
                let step = loc.distance(from: last)
                // Drop GPS "teleport" glitches; otherwise accumulate trip distance.
                if step.isFinite, step < 1000 { distanceMeters += step }
            }
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
