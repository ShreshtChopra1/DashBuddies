import SwiftUI

/// Saved trip history. Tap a trip to revisit its summary.
struct TripHistoryView: View {
    @ObservedObject var store: TripStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if store.trips.isEmpty {
                    Text("No trips yet. Tap Start Trip to record one.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.trips) { trip in
                        NavigationLink {
                            TripSummaryView(trip: trip)
                        } label: {
                            row(trip)
                        }
                    }
                }
            }
            .navigationTitle("Trip History")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ trip: Trip) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.startDate, format: .dateTime.month().day().hour().minute())
                    .font(.subheadline)
                Text(String(format: "%.1f mi · %d events", trip.distanceMiles, trip.events.count))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(trip.score)")
                .font(.title3).bold().monospacedDigit()
                .foregroundStyle(scoreColor(trip.score))
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...:    return .green
        case 50..<80:  return .orange
        default:       return .red
        }
    }
}
