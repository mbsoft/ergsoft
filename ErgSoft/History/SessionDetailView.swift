import SwiftUI
import Charts

private struct ChartPoint: Identifiable { let t: Double; let v: Double; var id: Double { t } }

struct SessionDetailView: View {
    let session: WorkoutSession

    private var pts: [SamplePoint] { session.points.sorted { $0.t < $1.t } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: [GridItem(), GridItem(), GridItem()]) {
                    stat("Meters", Fmt.meters(session.totalMeters))
                    stat("Time", Fmt.clock(session.durationSeconds))
                    if session.kind == .rower { stat("Avg pace", Fmt.pace(session.averagePaceSecondsPer500m)) }
                    stat("Avg W", String(Int(session.averageWatts)))
                    stat("Avg HR", session.averageHeartRate > 0 ? String(Int(session.averageHeartRate)) : "--")
                    stat("Max HR", session.maxHeartRate > 0 ? String(session.maxHeartRate) : "--")
                    stat("Cal", String(session.calories))
                    stat("Strokes", String(session.strokes))
                }
                if !pts.isEmpty {
                    chart("Power (W)", color: .orange) { p in Double(p.watts) }
                    if session.kind == .rower { chart("Pace (s/500m)", color: .blue, invert: true) { p in p.pace > 0 ? p.pace : nil } }
                    chart("Heart rate", color: .red) { p in p.heartRate > 0 ? Double(p.heartRate) : nil }
                }
                HStack {
                    Image(systemName: session.healthKitUUID == nil ? "heart.slash" : "heart.fill").foregroundStyle(.red)
                    Text(session.healthKitUUID == nil ? "Not saved to Apple Health" : "Saved to Apple Health").font(.caption)
                }
            }
            .padding()
        }
        .navigationTitle(session.planName)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack { Text(value).font(.title3.bold()).monospacedDigit(); Text(label).font(.caption).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity).padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }

    private func chart(_ title: String, color: Color, invert: Bool = false, _ value: @escaping (SamplePoint) -> Double?) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Chart(pts.compactMap { p in value(p).map { ChartPoint(t: p.t, v: $0) } }) { cp in
                LineMark(x: .value("t", cp.t), y: .value(title, cp.v)).foregroundStyle(color).interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: .automatic(reversed: invert))
            .chartXAxis { AxisMarks { v in AxisValueLabel { if let s = v.as(Double.self) { Text(Fmt.clock(s)) } } } }
            .frame(height: 140)
        }
    }
}
