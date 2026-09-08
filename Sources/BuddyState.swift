import SwiftUI

/// The buddy's mood, derived from `wellbeing`. Drives expression + colour in 3D.
enum BuddyMood {
    case happy, content, sad

    var label: String {
        switch self {
        case .happy:   return "Happy"
        case .content: return "Content"
        case .sad:     return "Worried"
        }
    }

    var emoji: String {
        switch self {
        case .happy:   return "😄"
        case .content: return "🙂"
        case .sad:     return "😟"
        }
    }
}

/// Game state for the virtual companion: currency, progression, owned/equipped
/// cosmetics, and the chosen environment. Persisted as JSON in Documents
/// (mirrors `TripStore`'s approach since SwiftData needs iOS 17).
///
/// Coins and XP are earned from real trips via `registerTrip(_:)`, which keys
/// off each trip's 0–100 score — so driving safely literally feeds the buddy.
final class BuddyState: ObservableObject {
    @Published private(set) var coins: Int
    @Published private(set) var xp: Int
    @Published private(set) var wellbeing: Double          // 0...100, smooths trip scores
    @Published private(set) var ownedAccessoryIDs: Set<String>
    @Published private(set) var equippedAccessoryIDs: Set<String>
    @Published private(set) var ownedEnvironmentIDs: Set<String>
    @Published private(set) var selectedEnvironmentID: String
    @Published private(set) var selectedCharacterID: String

    private var lastAwardedTripID: UUID?
    private let fileURL: URL

    // MARK: - Derived

    var level: Int { xp / 100 + 1 }
    var xpIntoLevel: Int { xp % 100 }

    var mood: BuddyMood {
        switch wellbeing {
        case 72...:    return .happy
        case 42..<72:  return .content
        default:       return .sad
        }
    }

    var equippedAccessories: [Accessory] {
        BuddyCatalog.accessories.filter { equippedAccessoryIDs.contains($0.id) }
    }

    var currentEnvironment: BuddyEnvironment {
        BuddyCatalog.environment(id: selectedEnvironmentID) ?? BuddyCatalog.environments[0]
    }

    var currentCharacter: BuddyCharacter {
        BuddyCatalog.character(id: selectedCharacterID) ?? BuddyCatalog.characters[0]
    }

    // MARK: - Init / persistence

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("buddy.json")

        let starterEnv = BuddyCatalog.environments[0].id
        if let snap = BuddyState.loadSnapshot(from: fileURL) {
            coins = snap.coins
            xp = snap.xp
            wellbeing = snap.wellbeing
            ownedAccessoryIDs = Set(snap.owned)
            equippedAccessoryIDs = Set(snap.equipped)
            ownedEnvironmentIDs = Set(snap.ownedEnvironments).union([starterEnv])
            selectedEnvironmentID = snap.environment
            selectedCharacterID = snap.character ?? BuddyCatalog.characters[0].id
            lastAwardedTripID = snap.lastAwardedTripID.flatMap(UUID.init(uuidString:))
        } else {
            coins = 50                                       // a little starter cash
            xp = 0
            wellbeing = 60
            ownedAccessoryIDs = []
            equippedAccessoryIDs = []
            ownedEnvironmentIDs = [starterEnv]
            selectedEnvironmentID = starterEnv
            selectedCharacterID = BuddyCatalog.characters[0].id
        }
    }

    // MARK: - Earning from trips

    /// Award coins + XP for a finished trip and nudge wellbeing toward its score.
    /// Guards against double-awarding if the summary screen reappears.
    @discardableResult
    func registerTrip(_ trip: Trip) -> Int {
        guard trip.id != lastAwardedTripID else { return 0 }
        lastAwardedTripID = trip.id

        let distanceBonus = Int((trip.distanceMiles * 5).rounded())
        let earned = max(1, trip.score / 2 + distanceBonus)
        coins += earned
        xp += trip.score
        // Wellbeing drifts toward the score; a great drive lifts it, a bad one dips it.
        wellbeing = min(100, max(0, wellbeing + Double(trip.score - 62) / 6))
        save()
        return earned
    }

    // MARK: - Accessories

    func isOwned(_ a: Accessory) -> Bool { ownedAccessoryIDs.contains(a.id) }
    func isEquipped(_ a: Accessory) -> Bool { equippedAccessoryIDs.contains(a.id) }
    func canAfford(_ price: Int) -> Bool { coins >= price }

    func purchase(_ a: Accessory) {
        guard !isOwned(a), coins >= a.price else { return }
        coins -= a.price
        ownedAccessoryIDs.insert(a.id)
        save()
    }

    /// Equip an owned accessory (replacing whatever's in its slot), or unequip it.
    func toggleEquip(_ a: Accessory) {
        guard isOwned(a) else { return }
        if equippedAccessoryIDs.contains(a.id) {
            equippedAccessoryIDs.remove(a.id)
        } else {
            let sameSlot = BuddyCatalog.accessories.filter { $0.slot == a.slot }.map(\.id)
            equippedAccessoryIDs.subtract(sameSlot)
            equippedAccessoryIDs.insert(a.id)
        }
        save()
    }

    // MARK: - Environments

    func isOwned(_ e: BuddyEnvironment) -> Bool { ownedEnvironmentIDs.contains(e.id) }
    func isSelected(_ e: BuddyEnvironment) -> Bool { selectedEnvironmentID == e.id }

    func purchase(_ e: BuddyEnvironment) {
        guard !isOwned(e), coins >= e.price else { return }
        coins -= e.price
        ownedEnvironmentIDs.insert(e.id)
        save()
    }

    func select(_ e: BuddyEnvironment) {
        guard isOwned(e) else { return }
        selectedEnvironmentID = e.id
        save()
    }

    // MARK: - Character

    func selectCharacter(_ id: String) {
        guard BuddyCatalog.character(id: id) != nil, id != selectedCharacterID else { return }
        selectedCharacterID = id
        save()
    }

    // MARK: - Snapshot

    private struct Snapshot: Codable {
        var coins: Int
        var xp: Int
        var wellbeing: Double
        var owned: [String]
        var equipped: [String]
        var ownedEnvironments: [String]
        var environment: String
        var character: String?          // optional for back-compat with older saves
        var lastAwardedTripID: String?
    }

    private static func loadSnapshot(from url: URL) -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    private func save() {
        let snap = Snapshot(
            coins: coins,
            xp: xp,
            wellbeing: wellbeing,
            owned: Array(ownedAccessoryIDs),
            equipped: Array(equippedAccessoryIDs),
            ownedEnvironments: Array(ownedEnvironmentIDs),
            environment: selectedEnvironmentID,
            character: selectedCharacterID,
            lastAwardedTripID: lastAwardedTripID?.uuidString
        )
        do {
            let data = try JSONEncoder().encode(snap)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("⚠️ Failed to save buddy: \(error)")
        }
    }
}
