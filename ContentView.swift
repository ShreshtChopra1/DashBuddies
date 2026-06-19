import SwiftUI

struct ContentView: View {
    @StateObject private var store: TripStore
    @StateObject private var recorder: TripRecorder
    @StateObject private var automator: TripAutomator
    @StateObject private var buddy = BuddyState()

    @State private var snapshotProxy = SceneSnapshotProxy()
    @State private var shareItem: ShareItem?
    @State private var showingShop = false
    @State private var showingRoom = false
    @State private var showingHistory = false
    @State private var showingRecording = false

    private let brandBlue = Color(red: 0.10, green: 0.45, blue: 0.95)
    private let cardFill = Color(white: 0.96)

    init() {
        let store = TripStore()
        let recorder = TripRecorder(store: store)
        _store = StateObject(wrappedValue: store)
        _recorder = StateObject(wrappedValue: recorder)
        _automator = StateObject(wrappedValue: TripAutomator(recorder: recorder))
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 12) {
                wordmark
                topHalf.frame(maxHeight: .infinity)
                bottomHalf.frame(maxHeight: .infinity)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .preferredColorScheme(.light)
        .onAppear { recorder.requestPermissions() }
        // Show the recording dashboard whenever a trip starts — whether the user
        // tapped Start or the automator detected driving.
        .onChange(of: recorder.isRecording) { recording in
            if recording { showingRecording = true }
        }
        .fullScreenCover(isPresented: $showingRecording) {
            TripRecordingView(recorder: recorder, buddy: buddy)
        }
        .fullScreenCover(isPresented: $showingRoom) {
            BuddyRoomView(buddy: buddy)
        }
        .sheet(isPresented: $showingShop) { ShopView(buddy: buddy) }
        .sheet(isPresented: $showingHistory) { TripHistoryView(store: store) }
        .sheet(item: $shareItem) { item in ActivityView(items: [item.url]) }
    }

    // MARK: - Header

    private var wordmark: some View {
        HStack(spacing: 10) {
            Image("AppLogo")
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text("DashBuddies")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(brandBlue)
            Spacer()
            Button { showingShop = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "circle.hexagongrid.fill").foregroundStyle(.yellow)
                    Text("\(buddy.coins)").font(.subheadline.weight(.bold)).foregroundStyle(.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(cardFill, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Top half: the buddy

    private var topHalf: some View {
        VStack(spacing: 12) {
            buddyStage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 12) {
                actionPill("Share", "square.and.arrow.up") { shareBuddy() }
                actionPill("Customize", "tshirt.fill") { showingShop = true }
            }
        }
    }

    private var buddyStage: some View {
        BuddyView(characterID: buddy.currentCharacter.id,
                  environment: buddy.currentEnvironment,
                  snapshotProxy: snapshotProxy)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                HStack(spacing: 5) {
                    Text(buddy.mood.emoji)
                    Text("\(buddy.mood.label) · Lv \(buddy.level)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(12)
            }
            .overlay(alignment: .topTrailing) {
                Button { showingRoom = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(12)
            }
    }

    private func actionPill(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(brandBlue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(cardFill, in: Capsule())
        }
    }

    // MARK: - Bottom half: drive

    private var bottomHalf: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                stat("Last drive", store.trips.first.map { "\($0.score)" } ?? "—")
                stat("Trips", "\(store.trips.count)")
                stat("Buddy", "Lv \(buddy.level)")
            }
            if TripAutomator.isAvailable { autoDetectRow }
            Spacer(minLength: 4)
            startButton
            Button { showingHistory = true } label: {
                Label("Trip History", systemImage: "clock.arrow.circlepath")
            }
            .font(.callout.weight(.medium))
            .tint(brandBlue)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(.primary)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 14))
    }

    private var autoDetectRow: some View {
        Toggle(isOn: $automator.autoDetectEnabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Auto-detect driving")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(automator.autoDetectEnabled ? automator.activityDescription
                                                 : "Start trips automatically when you drive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(brandBlue)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 14))
    }

    private var startButton: some View {
        Button {
            showingRecording = true
            recorder.start()
        } label: {
            Label("Start Trip", systemImage: "play.fill")
                .font(.title3.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(brandBlue, in: Capsule())
                .shadow(color: brandBlue.opacity(0.3), radius: 8, y: 4)
        }
    }

    // MARK: - Actions

    private func shareBuddy() {
        snapshotProxy.makePNG { url in
            if let url { shareItem = ShareItem(url: url) }
        }
    }
}

#Preview {
    ContentView()
}
