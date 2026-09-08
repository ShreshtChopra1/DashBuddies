import SwiftUI

/// Post-drive summary ("Safe-Gate"): the trip's score, headline stats, and the
/// list of harsh events. Pure content — callers supply the navigation container
/// (the Stop sheet wraps it in a NavigationStack; history pushes onto its own).
struct TripSummaryView: View {
    let trip: Trip

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                scoreBadge
                statsGrid
                if trip.events.isEmpty {
                    Label("No harsh events — smooth drive!", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                        .padding(.top, 8)
                } else {
                    eventList
                }
            }
            .padding()
        }
        .navigationTitle("Trip Summary")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var scoreBadge: some View {
        VStack(spacing: 6) {
            Text("\(trip.score)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(scoreColor)
            Text("Safety score / 100")
                .foregroundStyle(.secondary)
            Text(scoreVerdict)
                .font(.headline)
                .foregroundStyle(scoreColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            stat("Distance", String(format: "%.1f mi", trip.distanceMiles))
            stat("Duration", durationText)
            stat("Top speed", String(format: "%.0f mph", trip.topSpeedMph))
            stat("Harsh events", "\(trip.events.count)")
            stat("Severe", "\(trip.severeCount)")
            stat("Cornering", "\(trip.eventCount(of: .hardCornering))")
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3).bold().monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var eventList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Events").font(.headline)
            ForEach(trip.events) { event in
                HStack(spacing: 12) {
                    Image(systemName: event.kind.symbol)
                        .foregroundStyle(event.severity == .severe ? .red : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.kind.label).font(.subheadline)
                        Text(event.timestamp, style: .time)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(format: "%.2f g", event.peakG))
                        .monospacedDigit().bold()
                        .foregroundStyle(event.severity == .severe ? .red : .primary)
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
    }

    private var durationText: String {
        let total = Int(trip.duration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var scoreColor: Color {
        switch trip.score {
        case 80...:    return .green
        case 50..<80:  return .orange
        default:       return .red
        }
    }

    private var scoreVerdict: String {
        switch trip.score {
        case 90...:    return "Excellent"
        case 80..<90:  return "Great"
        case 60..<80:  return "Okay"
        case 40..<60:  return "Rough"
        default:       return "Harsh"
        }
    }
}
