import SwiftUI

/// The live driving dashboard, shown full-screen while a trip records. On stop
/// (manual or automatic) it swaps to the trip summary — awarding the buddy coins
/// — and Done returns to the landing page.
struct TripRecordingView: View {
    @ObservedObject var recorder: TripRecorder
    @ObservedObject var buddy: BuddyState

    @StateObject private var music = MusicController()
    @Environment(\.dismiss) private var dismiss

    private let brandBlue = Color(red: 0.10, green: 0.45, blue: 0.95)
    private let cardFill = Color(white: 0.96)

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            if let trip = recorder.finishedTrip {
                summary(trip)
            } else {
                dashboard
            }
        }
        .preferredColorScheme(.light)
        .onAppear { music.begin() }
        .onDisappear { music.end() }
    }

    // MARK: - Dashboard

    private var dashboard: some View {
        VStack(spacing: 20) {
            HStack {
                Label("Recording", systemImage: "record.circle")
                    .font(.headline)
                    .foregroundStyle(.red)
                Spacer()
                Text(recorder.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            VStack(spacing: 0) {
                Text(String(format: "%.0f", recorder.speedMph))
                    .font(.system(size: 92, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text("mph")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                tile("bolt.fill", "G-force", String(format: "%.2f g", recorder.accelMagnitude))
                tile("arrow.triangle.turn.up.right.diamond.fill", "Rotation", String(format: "%.2f", recorder.rotationRate))
                tile("exclamationmark.triangle.fill", "Harsh", "\(recorder.harshEvents)")
            }

            NowPlayingCard(music: music, tint: brandBlue)

            Spacer(minLength: 0)

            Button { recorder.stop() } label: {
                Text("Stop Trip")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.red, in: Capsule())
                    .shadow(color: Color.red.opacity(0.3), radius: 8, y: 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private func tile(_ icon: String, _ label: String, _ value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3).foregroundStyle(brandBlue)
            Text(value).font(.headline).monospacedDigit().foregroundStyle(.primary)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Summary

    private func summary(_ trip: Trip) -> some View {
        NavigationStack {
            TripSummaryView(trip: trip)
                .onAppear { buddy.registerTrip(trip) }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

/// Compact Apple Music transport: artwork, track, and prev / play-pause / next.
struct NowPlayingCard: View {
    @ObservedObject var music: MusicController
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(music.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(music.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            HStack(spacing: 20) {
                control("backward.fill") { music.previous() }
                control(music.isPlaying ? "pause.fill" : "play.fill") { music.playPause() }
                control("forward.fill") { music.next() }
            }
        }
        .padding(12)
        .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 16))
    }

    private var artwork: some View {
        Group {
            if let art = music.artwork {
                Image(uiImage: art).resizable().scaledToFill()
            } else {
                ZStack {
                    Color(white: 0.9)
                    Image(systemName: "music.note").foregroundStyle(tint)
                }
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func control(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
        }
    }
}
