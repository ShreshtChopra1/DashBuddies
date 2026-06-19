import SwiftUI

/// Full-screen 3D buddy room: orbit the buddy with your fingers, see coins/mood,
/// and open the shop to spend driving-earned coins on accessories + environments.
struct BuddyRoomView: View {
    @ObservedObject var buddy: BuddyState
    @Environment(\.dismiss) private var dismiss
    @State private var showingShop = false

    private let brandBlue = Color(red: 0.10, green: 0.45, blue: 0.95)

    var body: some View {
        ZStack {
            BuddyView(characterID: buddy.currentCharacter.id,
                      environment: buddy.currentEnvironment)
                .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .sheet(isPresented: $showingShop) { ShopView(buddy: buddy) }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.25), in: Circle())
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                pill {
                    Image(systemName: "circle.hexagongrid.fill").foregroundStyle(.yellow)
                    Text("\(buddy.coins)").bold()
                }
                pill {
                    Text(buddy.mood.emoji)
                    Text("\(buddy.mood.label) · Lv \(buddy.level)")
                        .font(.footnote.weight(.semibold))
                }
            }
        }
    }

    private var bottomBar: some View {
        Button { showingShop = true } label: {
            Label("Customize", systemImage: "tshirt.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(brandBlue, in: Capsule())
                .shadow(color: brandBlue.opacity(0.4), radius: 8, y: 4)
        }
    }

    private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6, content: content)
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.black.opacity(0.28), in: Capsule())
    }
}

/// The shop / wardrobe. Two tabs: accessories and environments. Buy with coins,
/// then equip/select. Buttons disable when you can't afford an item.
struct ShopView: View {
    @ObservedObject var buddy: BuddyState
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0

    private let brandBlue = Color(red: 0.10, green: 0.45, blue: 0.95)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Buddies").tag(0)
                    Text("Places").tag(1)
                    Text("Items").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()

                List {
                    switch tab {
                    case 0:
                        ForEach(BuddyCatalog.characters) { characterRow($0) }
                    case 1:
                        ForEach(BuddyCatalog.environments) { environmentRow($0) }
                    default:
                        ForEach(BuddyCatalog.accessories) { accessoryRow($0) }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Shop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "circle.hexagongrid.fill").foregroundStyle(.yellow)
                        Text("\(buddy.coins)").bold()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Rows

    private func characterRow(_ c: BuddyCharacter) -> some View {
        HStack {
            Text(c.emoji)
                .font(.title)
                .frame(width: 44, height: 44)
                .background(Color(white: 0.95), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(c.name).font(.body.weight(.medium))
                Text("Buddy").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if buddy.selectedCharacterID == c.id {
                Text("Active")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color.green.opacity(0.18), in: Capsule())
                    .foregroundStyle(.green)
            } else {
                Button("Use") { buddy.selectCharacter(c.id) }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .overlay(Capsule().stroke(brandBlue, lineWidth: 1.5))
                    .foregroundStyle(brandBlue)
                    .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func accessoryRow(_ item: Accessory) -> some View {
        HStack {
            swatch(Color(uiColor: item.tint), symbol: symbol(for: item.slot))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body.weight(.medium))
                Text(item.slot.rawValue.capitalized)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            actionButton(
                owned: buddy.isOwned(item),
                equipped: buddy.isEquipped(item),
                price: item.price,
                affordable: buddy.canAfford(item.price),
                buy: { buddy.purchase(item) },
                toggle: { buddy.toggleEquip(item) }
            )
        }
        .padding(.vertical, 4)
    }

    private func environmentRow(_ env: BuddyEnvironment) -> some View {
        HStack {
            swatch(Color(uiColor: env.skyTop), symbol: "photo.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text(env.name).font(.body.weight(.medium))
                Text(env.hasFloor ? "Has ground" : "Open space")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            actionButton(
                owned: buddy.isOwned(env),
                equipped: buddy.isSelected(env),
                price: env.price,
                affordable: buddy.canAfford(env.price),
                buy: { buddy.purchase(env) },
                toggle: { buddy.select(env) },
                equippedLabel: "Active",
                toggleLabel: "Use"
            )
        }
        .padding(.vertical, 4)
    }

    // MARK: - Shared bits

    @ViewBuilder
    private func actionButton(owned: Bool, equipped: Bool, price: Int, affordable: Bool,
                              buy: @escaping () -> Void, toggle: @escaping () -> Void,
                              equippedLabel: String = "Worn", toggleLabel: String = "Wear") -> some View {
        if !owned {
            Button(action: buy) {
                HStack(spacing: 4) {
                    Image(systemName: "circle.hexagongrid.fill").font(.caption2)
                    Text("\(price)")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(affordable ? brandBlue : Color.gray.opacity(0.4), in: Capsule())
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(!affordable)
        } else if equipped {
            Button(action: toggle) {
                Text(equippedLabel)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color.green.opacity(0.18), in: Capsule())
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
        } else {
            Button(action: toggle) {
                Text(toggleLabel)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .overlay(Capsule().stroke(brandBlue, lineWidth: 1.5))
                    .foregroundStyle(brandBlue)
            }
            .buttonStyle(.plain)
        }
    }

    private func swatch(_ color: Color, symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(color, in: RoundedRectangle(cornerRadius: 12))
    }

    private func symbol(for slot: AccessorySlot) -> String {
        switch slot {
        case .hat:  return "graduationcap.fill"
        case .eyes: return "eyeglasses"
        case .neck: return "person.fill"
        case .back: return "wind"
        }
    }
}
