import SwiftUI
import RealityKit
import Combine

/// Renders the chosen buddy with **RealityKit** (Apple's current 3D engine —
/// SceneKit was deprecated at WWDC 2025). It loads a real rigged USDZ creature,
/// plays its idle animation, and gives a finger-orbit camera whose pitch is
/// hard-clamped so it can never drop under the floor.
///
/// Accessories aren't attached in 3D yet — that needs real accessory meshes;
/// for now the cosmetics are the environment and which creature you pick.
struct BuddyView: UIViewRepresentable {
    let characterID: String
    let environment: BuddyEnvironment
    var snapshotProxy: SceneSnapshotProxy? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        arView.environment.background = .color(environment.skyBottom)
        context.coordinator.setUp(arView)
        context.coordinator.load(characterID)
        snapshotProxy?.arView = arView

        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        arView.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handlePinch(_:)))
        arView.addGestureRecognizer(pinch)
        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        arView.environment.background = .color(environment.skyBottom)
        context.coordinator.load(characterID)   // no-op if unchanged
    }

    final class Coordinator: NSObject {
        private weak var arView: ARView?
        private var loadCancellable: AnyCancellable?
        private var modelAnchor: AnchorEntity?
        private var currentID: String?

        private let camera = PerspectiveCamera()
        private let pivotY: Float = 0.22

        // Orbit state (radians / metres).
        private var yaw: Float = 0.5
        private var pitch: Float = 0.22
        private var distance: Float = 0.82
        private var startYaw: Float = 0, startPitch: Float = 0, startDistance: Float = 0
        private let minPitch: Float = 0       // never below the buddy's level → never under the floor
        private let maxPitch: Float = 1.40    // ~80°, short of the pole so it can't flip over
        private let minDistance: Float = 0.6
        private let maxDistance: Float = 3.0

        func setUp(_ arView: ARView) {
            self.arView = arView

            let key = DirectionalLight()
            key.light.intensity = 4400
            key.light.color = .white
            key.look(at: .zero, from: [2, 5, 3], relativeTo: nil)
            addAnchored(key, to: arView)

            let fill = DirectionalLight()
            fill.light.intensity = 2000
            fill.light.color = UIColor(red: 0.9, green: 0.94, blue: 1, alpha: 1)
            fill.look(at: .zero, from: [-3, 2, -2], relativeTo: nil)
            addAnchored(fill, to: arView)

            camera.camera.fieldOfViewInDegrees = 46
            addAnchored(camera, to: arView)
            updateCamera()
        }

        private func addAnchored(_ entity: Entity, to arView: ARView) {
            let anchor = AnchorEntity(world: .zero)
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)
        }

        func load(_ id: String) {
            guard id != currentID, arView != nil else { return }
            currentID = id
            guard let info = BuddyCatalog.character(id: id),
                  let url = Bundle.main.url(forResource: info.modelName, withExtension: "usdz") else {
                print("⚠️ Missing USDZ for \(id)")
                currentID = nil   // let it retry on the next update
                return
            }

            // Load the new model first; only swap out the old one once it's ready,
            // so switching buddies never leaves a blank gap. Reset on failure so a
            // later update can retry instead of being stuck.
            loadCancellable = Entity.loadModelAsync(contentsOf: url)
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { [weak self] completion in
                    if case let .failure(error) = completion {
                        print("⚠️ Load \(id): \(error)")
                        self?.currentID = nil
                    }
                }, receiveValue: { [weak self] model in
                    guard let self else { return }
                    self.modelAnchor?.removeFromParent()
                    self.place(model, info)
                })
        }

        private func place(_ model: ModelEntity, _ info: BuddyCharacter) {
            guard let arView else { return }
            let anchor = AnchorEntity(world: .zero)
            anchor.addChild(model)
            arView.scene.addAnchor(anchor)
            modelAnchor = anchor

            if let override = info.scaleOverride {
                // Fixed, hand-calibrated scale for models whose bounds RealityKit
                // under-reports. Measure BEFORE scaling (post-scale bounds are
                // corrupted for rigged models), then scale the offset mathematically.
                let b = model.visualBounds(recursive: true, relativeTo: anchor)
                model.scale = SIMD3(repeating: override)
                model.position = SIMD3(-b.center.x * override, info.yOffset - b.min.y * override, -b.center.z * override)
            } else {
                // Auto-fit from bounds (reliable models, e.g. the chameleon).
                // Measure ONCE: re-measuring after scaling returns corrupted bounds
                // for rigged models, so derive the offset from this one reading.
                let b = model.visualBounds(recursive: true, relativeTo: anchor)
                let maxDim = max(b.extents.x, max(b.extents.y, b.extents.z))
                let scale: Float = (maxDim.isFinite && maxDim > 0.0001) ? 0.62 / maxDim : 1
                model.scale = SIMD3(repeating: scale)
                model.position = SIMD3(-b.center.x * scale, info.yOffset - b.min.y * scale, -b.center.z * scale)
            }

            if let idle = model.availableAnimations.first {
                model.playAnimation(idle.repeat(duration: .infinity),
                                    transitionDuration: 0.3, startsPaused: false)
            }
        }

        // MARK: Orbit gestures

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            guard let view = g.view else { return }
            if g.state == .began { startYaw = yaw; startPitch = pitch }
            let t = g.translation(in: view)
            let sensitivity: Float = 0.01
            yaw = startYaw - Float(t.x) * sensitivity
            pitch = min(max(startPitch + Float(t.y) * sensitivity, minPitch), maxPitch)
            updateCamera()
        }

        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            if g.state == .began { startDistance = distance }
            distance = min(max(startDistance / Float(g.scale), minDistance), maxDistance)
            updateCamera()
        }

        private func updateCamera() {
            let target = SIMD3<Float>(0, pivotY, 0)
            let x = distance * cos(pitch) * sin(yaw)
            let y = pivotY + distance * sin(pitch)
            let z = distance * cos(pitch) * cos(yaw)
            camera.look(at: target, from: SIMD3(x, y, z), relativeTo: nil)
        }
    }
}
