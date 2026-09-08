# DashBuddies

An iOS app that turns driving telematics into a virtual pet. Drive smoothly and
your buddy thrives; brake hard and corner aggressively and it doesn't.

SwiftUI + CoreLocation + CoreMotion + RealityKit. iOS 16+. No third-party
dependencies.

---

## The actual engineering problem

"Detect hard braking from a phone's accelerometer" sounds like a threshold check.
It isn't, and the reason is that **the phone's orientation in the car is unknown**.
It might be in a mount, face-down on the passenger seat, or sliding around a
cupholder. Three consequences, and how each is handled:

**1. You can't trust any single axis.**
Raw accelerometer axes are meaningless when the device frame doesn't match the
vehicle frame. Detection runs on the *horizontal* component only — the vertical
axis is projected out using CoreMotion's `gravity` vector — so the measurement is
taken in the driving plane no matter how the phone sits. A pothole is vertical, so
it stops registering as a braking event.

**2. The gyroscope is a trap for cornering.**
`rotationRate` measures *the phone*, not the car. A phone sliding in a cupholder
during a hard brake reads as a large yaw — which would label that brake as
cornering. The bias correlates with events instead of averaging out, so more data
never fixes it. Cornering is instead judged from `carTurnRate`: the rate of change
of the car's **course over the ground**, derived from `CLLocation.course` with a
bearing fallback. That's a property of the vehicle's path, so rotating the phone
inside the car cannot affect it.

**3. One maneuver has to equal one event.**
A naive per-sample threshold counter logged ~10 events for a single brake. The
detector is a peak-hold state machine with hysteresis — opens at 0.45 g, closes at
0.25 g — so one maneuver produces exactly one event, tagged with its peak. Events
only count above 5 mph, so picking up a parked phone doesn't score against you.

---

## Adaptive Kalman speed filter

`CLLocation.speed` is jittery enough to make a dashboard readout unusable.
`KalmanSpeedFilter` is a 1-D Kalman filter (46 lines, no dependencies) with one
non-obvious property: **its process noise is fed from the accelerometer on every
update.**

At cruise (≈0 g) the filter assumes speed is barely changing and smooths hard,
giving a rock-steady number. The moment you actually accelerate or brake, the
accelerometer raises the process noise, the filter loosens, and it tracks the real
change instead of lagging behind it. Each GPS reading is also weighted by its own
`speedAccuracy`, so a good Doppler fix is followed closely while a noisy
position-derived one is smoothed heavily.

Using acceleration **magnitude** keeps this orientation-independent, consistent
with everything above. Roughly 62% less cruise-speed error than raw GPS in
simulation.

---

## Architecture

```
Sources/
  TripRecorder.swift       CoreLocation + CoreMotion capture, harsh-event state
                           machine, distance/top-speed accumulation, route breadcrumbs
  KalmanSpeedFilter.swift  1-D Kalman filter with accelerometer-driven process noise
  TripAutomator.swift      CMMotionActivity auto start/stop, 120s parked timeout so
                           red lights don't end a trip
  DriveEvent.swift         Event kinds, severity model, score penalties
  TripScorer.swift         Events -> 0-100 trip score
  Trip / RoutePoint        Codable trip model with a hand-written init(from:)
  TripStore.swift          JSON persistence to Documents
  BuddyState / BuddyView / BuddyRoomView / BuddyCatalog
                           RealityKit companion, accessory slots, scale calibration
  MusicController.swift    Apple Music transport via MPMusicPlayerController
  ContentView / TripRecordingView / TripSummaryView / TripHistoryView
```

Two decisions worth calling out:

- **`Trip` has a hand-written `init(from:)`.** `TripStore` loads the entire history
  in a single `[Trip]` decode, so one undecodable trip would wipe every saved trip.
  Trips saved before `route` existed still decode cleanly, and any future schema
  change follows the same pattern.
- **Codable + JSON rather than SwiftData**, because SwiftData requires iOS 17 and
  the deployment target is 16.

## Status

- [x] Step 1 — live GPS + motion capture
- [x] Step 2 — debounced harsh-event detection, severity, 0–100 scoring, history
- [x] Step 3 — automatic trip start/stop via motion activity
- [ ] Step 4 — buddy game state fully reactive to trip score
- [ ] Step 5 — post-drive route map with green/red segments (MapKit)
- [ ] Reliable *background* auto-start (needs background location + motion plumbing)
- [ ] Brake vs. acceleration split — currently one combined longitudinal class,
      since separating them requires the axis-calibration step

`CLAUDE.md` is the detailed engineering log, including approaches that were tried
and rejected, and why.

## Build

The Xcode project is generated from `project.yml` by
[XcodeGen](https://github.com/yonaskolb/XcodeGen) — `DashBuddies.xcodeproj` is
gitignored and should never be hand-edited.

```sh
git clone https://github.com/ShreshtChopra1/DashBuddies.git
cd DashBuddies
xcodegen generate
open DashBuddies.xcodeproj
```

Set your own Team under Signing & Capabilities and a unique bundle identifier.

> **Run on a physical iPhone.** The Simulator has no real accelerometer or
> gyroscope and only fake GPS, so none of the telematics above can be exercised
> there. A free Apple ID is enough; those builds expire after 7 days.

> **3D models are not included.** The RealityKit buddies load `.usdz` files that
> aren't redistributed here for licensing reasons. Drop your own rigged models into
> `Sources/Models/` and register them in `BuddyCatalog.swift` — each entry takes a
> `scaleOverride` because RealityKit under-reports `visualBounds` on some rigged
> models, which otherwise renders them enormous.

## License

MIT — see [LICENSE](LICENSE).
