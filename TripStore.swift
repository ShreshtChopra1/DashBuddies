import Foundation

/// Persists trip history as a JSON file in the app's Documents directory.
/// (SwiftData would be nicer, but it needs iOS 17 and our floor is iOS 16.)
final class TripStore: ObservableObject {
    @Published private(set) var trips: [Trip] = []

    private let fileURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("trips.json")
        load()
    }

    /// Save a finished trip. Newest trips sort first.
    func add(_ trip: Trip) {
        trips.insert(trip, at: 0)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            trips = try JSONDecoder().decode([Trip].self, from: data)
        } catch {
            print("⚠️ Failed to load trips: \(error)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(trips)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("⚠️ Failed to save trips: \(error)")
        }
    }
}
