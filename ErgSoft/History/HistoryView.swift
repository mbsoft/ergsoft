import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            List {
                ForEach(sessions) { s in
                    NavigationLink(value: s) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(s.planName).font(.headline)
                                Spacer()
                                Text(s.startedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 12) {
                                Text("\(Fmt.meters(s.totalMeters))m")
                                Text(Fmt.clock(s.durationSeconds))
                                if s.kind == .rower { Text(Fmt.pace(s.averagePaceSecondsPer500m) + "/500m") }
                                if s.averageHeartRate > 0 { Text("♥ \(Int(s.averageHeartRate))") }
                            }.font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
                .onDelete { idx in idx.map { sessions[$0] }.forEach(context.delete) }
            }
            .overlay { if sessions.isEmpty { ContentUnavailableView("No workouts yet", systemImage: "figure.rower") } }
            .navigationTitle("History")
            .navigationDestination(for: WorkoutSession.self) { SessionDetailView(session: $0) }
        }
    }
}
