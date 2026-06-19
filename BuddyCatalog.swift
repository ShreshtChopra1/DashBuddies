import UIKit

/// Where an accessory sits on the buddy. One equipped item per slot.
enum AccessorySlot: String, Codable, CaseIterable {
    case hat, eyes, neck, back
}

/// The visual style an accessory renders as. (Not drawn on the RealityKit buddy
/// yet — accessories need real meshes; see BuddyView.)
enum AccessoryKind: String, Codable {
    case cap, topHat, crown, sunglasses, bowtie, scarf, cape
}

/// A pickable buddy creature, backed by a real rigged USDZ in `Sources/Models`.
///
/// `scaleOverride`: RealityKit under-reports `visualBounds` for some rigged models,
/// so auto-normalisation makes them render huge. When set, we use this fixed scale
/// instead (calibrated visually). `nil` ⇒ auto-fit from bounds (reliable models).
struct BuddyCharacter: Identifiable, Hashable {
    let id: String
    let name: String
    let modelName: String   // USDZ file base name in the app bundle
    let emoji: String
    let scaleOverride: Float?
    let yOffset: Float

    init(id: String, name: String, modelName: String, emoji: String,
         scaleOverride: Float? = nil, yOffset: Float = 0) {
        self.id = id
        self.name = name
        self.modelName = modelName
        self.emoji = emoji
        self.scaleOverride = scaleOverride
        self.yOffset = yOffset
    }
}

/// A buyable cosmetic. `tintHex` colours the procedural geometry.
struct Accessory: Identifiable, Hashable {
    let id: String
    let name: String
    let price: Int
    let slot: AccessorySlot
    let kind: AccessoryKind
    let tintHex: UInt32

    var tint: UIColor { UIColor(hex: tintHex) }
}

/// A place the buddy sits in: a sky gradient and (optionally) a floor.
struct BuddyEnvironment: Identifiable, Hashable {
    let id: String
    let name: String
    let price: Int
    let skyTopHex: UInt32
    let skyBottomHex: UInt32
    let floorHex: UInt32
    let hasFloor: Bool

    var skyTop: UIColor { UIColor(hex: skyTopHex) }
    var skyBottom: UIColor { UIColor(hex: skyBottomHex) }
    var floor: UIColor { UIColor(hex: floorHex) }
}

/// Static catalogs. Add new items here — the shop and 3D view pick them up
/// automatically. The first environment is free and owned by default.
enum BuddyCatalog {
    /// The buddy creatures (real USDZ models). All are free to pick.
    // The chameleon's USDZ has accurate bounds and looks great. The other Apple
    // sample models (robot/drummer/seahorse/hummingbird) have a RealityKit
    // skinned-bounds bug that makes them render the wrong size, and they're not
    // ideal pet avatars — so they're parked here, out of the picker, pending a
    // proper set of cute CC0 creatures (then re-enable with calibrated scales).
    static let characters: [BuddyCharacter] = [
        BuddyCharacter(id: "chameleon", name: "Chameleon", modelName: "chameleon", emoji: "🦎"),
    ]

    static let accessories: [Accessory] = [
        Accessory(id: "cap_red",  name: "Red Cap",     price: 40,  slot: .hat,  kind: .cap,        tintHex: 0xE7472B),
        Accessory(id: "tophat",   name: "Top Hat",     price: 120, slot: .hat,  kind: .topHat,     tintHex: 0x1B1B22),
        Accessory(id: "crown",    name: "Gold Crown",  price: 300, slot: .hat,  kind: .crown,      tintHex: 0xF4C13B),
        Accessory(id: "shades",   name: "Cool Shades", price: 80,  slot: .eyes, kind: .sunglasses, tintHex: 0x14141A),
        Accessory(id: "bowtie",   name: "Bow Tie",     price: 60,  slot: .neck, kind: .bowtie,     tintHex: 0xC02942),
        Accessory(id: "scarf",    name: "Cozy Scarf",  price: 90,  slot: .neck, kind: .scarf,      tintHex: 0xEC7A3C),
        Accessory(id: "cape",     name: "Hero Cape",   price: 150, slot: .back, kind: .cape,       tintHex: 0x2D6CDF),
    ]

    static let environments: [BuddyEnvironment] = [
        BuddyEnvironment(id: "meadow", name: "Meadow", price: 0,   skyTopHex: 0x9FD8FF, skyBottomHex: 0xE8F7D6, floorHex: 0x76C26B, hasFloor: true),
        BuddyEnvironment(id: "beach",  name: "Beach",  price: 100, skyTopHex: 0x8FE3F0, skyBottomHex: 0xFFF2CC, floorHex: 0xE7D29A, hasFloor: true),
        BuddyEnvironment(id: "dusk",   name: "Dusk",   price: 150, skyTopHex: 0x3A2A66, skyBottomHex: 0xF4845F, floorHex: 0x4A3F66, hasFloor: true),
        BuddyEnvironment(id: "space",  name: "Space",  price: 250, skyTopHex: 0x05060F, skyBottomHex: 0x2A2160, floorHex: 0x000000, hasFloor: false),
    ]

    static func accessory(id: String) -> Accessory? { accessories.first { $0.id == id } }
    static func environment(id: String) -> BuddyEnvironment? { environments.first { $0.id == id } }
    static func character(id: String) -> BuddyCharacter? { characters.first { $0.id == id } }
}

extension UIColor {
    /// Build a UIColor from a 0xRRGGBB hex literal.
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
