# DashBuddies

iOS (SwiftUI) app that turns safe-driving telematics into a virtual pet.
Driving smoothly nourishes a virtual companion; aggressive driving distresses it.
iOS-first, solo early-stage project.

## Build & run

- The Xcode project is **generated from `project.yml` via XcodeGen** — never edit
  `DashBuddies.xcodeproj` by hand. After adding, removing, or renaming any source
  file, run `xcodegen generate`, then build in Xcode.
- Run on a **physical iPhone** for real sensor data; the Simulator has no real
  accelerometer/gyroscope and only fake GPS.
- Minimum target: iOS 16. Pure SwiftUI, no third-party deps yet.

## Current state

Steps 1–2 done; Step 3 in progress. `TripRecorder` captures GPS (CoreLocation) +
motion (CoreMotion), detects harsh events, accumulates distance/top speed, and on
Stop builds a scored `Trip`. Harsh-event detection uses a peak-hold state machine
with hysteresis (`harshThreshold` 0.45 g to open, `releaseThreshold` 0.25 g to
close) so one maneuver = one event — replacing Step 1's per-sample counter, which
logged ~10 events per brake and fired on everyday braking. Detection runs on the
**horizontal** (driving-plane) acceleration only: we project out the vertical axis
using the `gravity` vector, so speed bumps/potholes don't count (works regardless
of how the phone sits — orientation is still unknown). Events only count while
actually driving (speed ≥ 5 mph) so handling a parked phone doesn't register.
Events are classified by severity (harsh/severe from peak g) and kind (cornering
vs. braking/accel). Cornering is judged from `carTurnRate` (deg/s) — the rate of
change of the car's **course over the ground**, computed in `updateTurnRate` from
`CLLocation.course` (falling back to the bearing between consecutive fixes). This is
a property of the car's *path*, so **rotating the phone inside the car cannot affect
it**. Do NOT switch this to the gyroscope: `rotationRate` measures the phone, and a
phone sliding in a cupholder during a hard brake reads as a large yaw, which would
mislabel that brake as cornering — the contamination correlates with events rather
than averaging out. The earlier GPS version *looked* broken for unrelated reasons
(single-sample derivative, and it snapped to 0 and dropped its reference heading on
every slow/invalid fix); it now EMA-smooths, decays instead of snapping, and rejects
jumps above 90°/s as course glitches. The live g-force readout is EMA-smoothed for a
steady dashboard while the detector still fires on raw peaks; speed below ~1.5 mph
shows a clean 0 (parked GPS creep). `TripScorer` rolls events into a 0–100 score (start at 100,
−5 harsh / −10 severe; distance & duration stored for future per-mile
normalisation). `TripStore` persists trip history as JSON in Documents (Codable,
not SwiftData — that needs iOS 17). Every fix is also kept as a `RoutePoint`
(lat/lon/timestamp/speed/accuracy) on `Trip.route` — the breadcrumb trail that
Step 5's map draws and that road matching runs against. `Trip` has a hand-written
`init(from:)` so trips saved before `route` existed still decode: `TripStore` loads
the whole history in one `[Trip]` call, so one undecodable trip would wipe every
saved trip. Keep that migration pattern for any future schema change. `TripSummaryView` shows a post-drive summary
on Stop; `TripHistoryView` lists saved trips. The dashboard's speed is GPS speed
run through `KalmanSpeedFilter` — Doppler speed weighted by `speedAccuracy` (with a
position-derived fallback), smoothed by a Kalman filter whose process noise is fed
from the accelerometer's horizontal g (rock-steady at cruise, responsive under
accel/braking; ~62% less cruise error than raw GPS in sim). No third-party deps.

`TripAutomator` (Step 3) uses `CMMotionActivityManager` to auto-start a trip on
`automotive` state and auto-stop after a 120 s parked timeout (so red lights don't
end trips). It drives the recorder while the app is active; manual Start/Stop is an
override. Reliable background auto-start still needs background motion/location work.

Step 4 (pet) is in: `BuddyState` (coins/XP/wellbeing→mood, owned/equipped cosmetics,
environments, **selected character**; earns from each trip via `registerTrip`) and
`BuddyCatalog`. The buddy is rendered by **RealityKit** in `BuddyView` (an
`ARView(cameraMode: .nonAR)` wrapper) — SceneKit was deprecated at WWDC25, so the
old procedural `BuddySceneView` was removed. It loads one of five real rigged USDZ
creatures from `Sources/Models` (chameleon/robot/drummer/seahorse/hummingbird,
~78 MB total, bundled as resources; pick in Customize → Buddies), plays the model's
idle animation, lights it with two directional lights, sets the env sky as the
background, and orbits with a finger gesture whose **pitch is hard-clamped** (can't
go under the floor or over the pole). Models are Apple AR Quick Look samples — fine
for prototyping; swap to CC0 before shipping (needs a glTF→USDZ converter, not
installed). Accessories are **not drawn on the 3D model yet** (they need real
meshes); the shop still tracks them, and mood is shown only in the UI pill (no
material tinting on the textured models).

UI is now two-screen. `ContentView` (white, forced light scheme, logo header) is a
landing page: top half shows the live buddy with Share (exports a PNG via
`SceneSnapshotProxy` + `ActivityView`) and Customize (`ShopView`) buttons and an
expand button to the full `BuddyRoomView`; bottom half has trip stats, the
auto-detect toggle, and a blue Start Trip button. Starting a trip (manually or via
the automator) presents `TripRecordingView` full-screen — the live dashboard
(speed, g-force, rotation, harsh count) plus a `NowPlayingCard`, and on Stop it
shows the summary (awards buddy coins) then dismisses.

`MusicController` controls **Apple Music / the system Music app** only
(`MPMusicPlayerController.systemMusicPlayer`): now-playing + play/pause/skip. iOS
forbids third-party control of other players (Spotify, etc.) — that needs each
service's own SDK + login, so Spotify is deferred behind the same UI. The logo PNG
lives in `Assets.xcassets/AppLogo` and is shown in-app; it is **not** the app icon
yet (`ASSETCATALOG_COMPILER_APPICON_NAME` is blank — the PNG has alpha and isn't
square, so a proper square/opaque 1024px icon is still TODO). No backend yet.

## Conventions

- All Swift lives in `Sources/`. One primary type per file.
- UI observes `@Published` values on observable objects; keep view logic thin.
- Keep code simple and readable over clever. Small, reviewable changes.
- Commit after each working step.

## Roadmap (build in order)

2. ✅ **Scoring engine + post-drive summary ("Safe-Gate") + persist trips.**
   Classify events (harsh brake / accel / cornering by severity), roll a trip into
   a 0–100 score, show a summary screen on Stop, save trip history (start with
   `Codable` to disk / SwiftData).
3. 🚧 **Automatic trip start/stop** using `CMMotionActivity` automotive state.
   (Foreground auto start/stop done via `TripAutomator`; background still TODO.)
4. ✅ **Pet + game state** that reacts to the trip score (mood, health, XP).
   (Plus: buddy landing page, share-as-PNG, Apple Music control. Spotify control
   and a real app icon are deferred — see Current state.)
5. 🚧 **MapKit route map** — replay the route with green (smooth) / red (harsh) segments.
   The trail is now recorded (`Trip.route`), so this is unblocked: draw an
   `MKPolyline` per segment, colouring by proximity to a `DriveEvent.timestamp`.
   Then **snap-to-road** and **speed limits** (Safe Streak) as batch lookups over
   the finished trail — see the ToS note below before picking a provider.
6. **Backend** (Firebase: Auth + Firestore) for accounts and cross-device sync.
7. **Guilds, cooperative leaderboards, in-app purchases** (StoreKit 2 or RevenueCat).

## iOS constraints to respect

- The brief's "Distraction-Free Multiplier" (detecting screen unlocks/touches
  mid-trip) is **not possible on iOS** — there's no API for it. Reframe around
  app-foreground detection or Apple's Driving Focus mode.
- Road **speed limits are not in MapKit**; the "Safe Streak" feature needs a
  third-party data provider (HERE / TomTom / Mapbox / OSM-Valhalla) when you get to it.
- **Google Maps Platform is a poor fit here.** Its terms restrict showing GMP-derived
  content on a non-Google base map, which collides with the MapKit route map in
  Step 5 — going Google for road data likely means rendering on Google's SDK too.
  Its `speedLimits` endpoint is also gated behind a premium/asset-tracking tier, not
  a standard key. Prefer OSM-based matching (Valhalla `trace_attributes` returns road
  class *and* `maxspeed`) or Mapbox/HERE, which coexist fine with MapKit. Verify
  current terms/pricing before committing — both change.
- **Match roads in batch after the trip, not per-fix during it.** A matcher given the
  whole trail is more accurate than one fed points live, and it's ~1 request per trip
  instead of one per second.
- The phone's orientation in the car is unknown, so accelerometer axes don't map
  cleanly to forward/lateral without a calibration step. Magnitude-based severity
  is fine until then.
- A third-party app **cannot control other apps' audio** (Spotify, YouTube Music,
  etc.). `MPMusicPlayerController.systemMusicPlayer` only drives Apple Music / the
  system Music app. Controlling Spotify requires the Spotify iOS SDK (App Remote)
  with a developer client ID + in-app login. CarPlay/Bluetooth don't change this.
