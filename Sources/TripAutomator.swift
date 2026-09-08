import Foundation
import CoreMotion

/// Step 3: automatically starts a trip when you begin driving and stops it once
/// you've parked, using Core Motion's activity classifier (`automotive` state).
///
/// Manual Start/Stop on the recorder still works as an override. Reliable
/// *background* auto-start needs more plumbing (background motion + location);
/// this first pass drives the recorder while the app is active.
final class TripAutomator: ObservableObject {

    /// Toggling this on begins monitoring motion activity (and prompts for the
    /// Motion & Fitness permission the first time).
    @Published var autoDetectEnabled = false {
        didSet {
            guard autoDetectEnabled != oldValue else { return }
            autoDetectEnabled ? startMonitoring() : stopMonitoring()
        }
    }

    /// Human-readable current activity, shown in the UI.
    @Published var activityDescription = "—"

    private let recorder: TripRecorder
    private let activityManager = CMMotionActivityManager()
    private let queue = OperationQueue()

    // When driving pauses, wait this long before deciding we've actually parked,
    // so red lights and brief stops don't prematurely end the trip.
    private let parkedTimeout: TimeInterval = 120
    private var parkedWorkItem: DispatchWorkItem?

    init(recorder: TripRecorder) {
        self.recorder = recorder
    }

    /// Whether this device can classify motion activity at all.
    static var isAvailable: Bool { CMMotionActivityManager.isActivityAvailable() }

    private func startMonitoring() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            activityDescription = "Motion activity unavailable on this device"
            autoDetectEnabled = false
            return
        }
        activityDescription = "Waiting for driving…"
        activityManager.startActivityUpdates(to: queue) { [weak self] activity in
            guard let self, let activity else { return }
            DispatchQueue.main.async { self.handle(activity) }
        }
    }

    private func stopMonitoring() {
        activityManager.stopActivityUpdates()
        parkedWorkItem?.cancel()
        parkedWorkItem = nil
        activityDescription = "—"
    }

    /// Decide what to do with each activity sample. Runs on the main thread.
    private func handle(_ activity: CMMotionActivity) {
        let confident = activity.confidence != .low

        // Driving → make sure a trip is running.
        if activity.automotive && confident {
            activityDescription = "Driving"
            cancelParkedTimer()
            if !recorder.isRecording { recorder.start() }
            return
        }

        // Clearly out of the car → end the trip promptly.
        if confident && (activity.walking || activity.running || activity.cycling) {
            activityDescription = label(for: activity)
            endTrip()
            return
        }

        // Stationary or uncertain: could just be a red light. Arm the parked
        // timer; if we don't see driving again before it fires, end the trip.
        activityDescription = recorder.isRecording ? "Stopped (waiting…)" : label(for: activity)
        if recorder.isRecording { armParkedTimer() }
    }

    private func armParkedTimer() {
        guard parkedWorkItem == nil else { return }   // already counting down
        let item = DispatchWorkItem { [weak self] in
            self?.parkedWorkItem = nil
            self?.endTrip()
        }
        parkedWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + parkedTimeout, execute: item)
    }

    private func cancelParkedTimer() {
        parkedWorkItem?.cancel()
        parkedWorkItem = nil
    }

    private func endTrip() {
        cancelParkedTimer()
        if recorder.isRecording { recorder.stop() }
    }

    private func label(for activity: CMMotionActivity) -> String {
        if activity.automotive { return "Driving" }
        if activity.walking    { return "Walking" }
        if activity.running    { return "Running" }
        if activity.cycling    { return "Cycling" }
        if activity.stationary { return "Stationary" }
        return "Unknown"
    }
}
