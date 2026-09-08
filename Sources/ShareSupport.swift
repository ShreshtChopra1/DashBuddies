import SwiftUI
import RealityKit

/// Bridges the live RealityKit buddy view to SwiftUI so we can export a PNG of
/// whatever the user is currently looking at. `BuddyView` stores its `ARView`
/// here when it's created.
final class SceneSnapshotProxy {
    weak var arView: ARView?

    /// Render the current buddy to a PNG temp file. `ARView.snapshot` is async,
    /// so this returns via a completion handler (always called on the main thread).
    func makePNG(completion: @escaping (URL?) -> Void) {
        guard let arView else { completion(nil); return }
        arView.snapshot(saveToHDR: false) { image in
            let url: URL? = {
                guard let image, let data = image.pngData() else { return nil }
                let out = FileManager.default.temporaryDirectory.appendingPathComponent("MyDashBuddy.png")
                do {
                    try data.write(to: out, options: .atomic)
                    return out
                } catch {
                    print("⚠️ Failed to write buddy PNG: \(error)")
                    return nil
                }
            }()
            DispatchQueue.main.async { completion(url) }
        }
    }
}

/// Identifiable wrapper so a freshly-rendered PNG can drive `.sheet(item:)`.
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// Thin wrapper around `UIActivityViewController` (the system share sheet).
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
