import SwiftUI
import Charts

struct SessionDetailView: View {
    let session: WorkoutSession
    @EnvironmentObject var settings: UserSettings
    @State private var expanded: ChartSeries?

    private var pts: [SamplePoint] { session.points.sorted { $0.t < $1.t } }

    private var power: ChartSeries {
        ChartSeries(id: "power", title: "Power", unit: "W", color: .orange, inverted: false,
                    points: pts.compactMap { $0.watts > 0 ? ChartPoint(t: $0.t, v: Double($0.watts)) : nil },
                    format: { "\(Int($0.rounded())) W" })
    }
    private var pace: ChartSeries {
        ChartSeries(id: "pace", title: "Pace", unit: "/500m", color: .blue, inverted: true,
                    points: pts.compactMap { $0.pace > 0 && $0.pace < 600 ? ChartPoint(t: $0.t, v: $0.pace) : nil },
                    format: { Fmt.pace($0) })
    }
    private var hr: ChartSeries {
        ChartSeries(id: "hr", title: "Heart rate", unit: "bpm", color: .red, inverted: false,
                    points: pts.compactMap { $0.heartRate > 0 ? ChartPoint(t: $0.t, v: Double($0.heartRate)) : nil },
                    format: { "\(Int($0.rounded()))" })
    }
    private var rate: ChartSeries {
        ChartSeries(id: "rate", title: "Stroke rate", unit: "s/m", color: .green, inverted: false,
                    points: pts.compactMap { $0.strokeRate > 0 ? ChartPoint(t: $0.t, v: $0.strokeRate) : nil },
                    format: { "\(Int($0.rounded()))" })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: [GridItem(), GridItem(), GridItem()]) {
                    stat(settings.units == .metric ? "Meters" : "Distance", settings.distance(session.totalMeters, compact: false))
                    stat("Time", Fmt.clock(session.durationSeconds))
                    if session.kind == .rower { stat("Avg pace", Fmt.pace(session.averagePaceSecondsPer500m)) }
                    stat("Avg W", String(Int(session.averageWatts)))
                    stat("Avg HR", session.averageHeartRate > 0 ? String(Int(session.averageHeartRate)) : "--")
                    stat("Max HR", session.maxHeartRate > 0 ? String(session.maxHeartRate) : "--")
                    stat("Cal", String(session.calories))
                    stat("Strokes", String(session.strokes))
                }
                if !pts.isEmpty {
                    ForEach([power, pace, hr, rate].filter { !$0.points.isEmpty }) { s in
                        miniChart(s)
                    }
                    Text("Tap a chart to zoom and scrub").font(.caption2).foregroundStyle(.tertiary)
                }
                HStack {
                    Image(systemName: session.healthKitUUID == nil ? "heart.slash" : "heart.fill").foregroundStyle(.red)
                    Text(session.healthKitUUID == nil ? "Not saved to Apple Health" : "Saved to Apple Health").font(.caption)
                }
            }
            .padding()
        }
        .navigationTitle(session.planName)
        .fullScreenCover(item: $expanded) { s in ChartDetailView(series: s) }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack { Text(value).font(.title3.bold()).monospacedDigit(); Text(label).font(.caption).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity).padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }

    private func miniChart(_ s: ChartSeries) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text("\(s.title) (\(s.unit))").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption2).foregroundStyle(.tertiary)
            }
            Chart(s.points) { p in
                LineMark(x: .value("t", p.t), y: .value(s.title, p.v)).foregroundStyle(s.color).interpolationMethod(.monotone)
            }
            .chartYScale(domain: .automatic(includesZero: false, reversed: s.inverted))
            .chartXAxis { AxisMarks { v in AxisValueLabel { if let t = v.as(Double.self) { Text(Fmt.clock(t)) } } } }
            .chartYAxis { AxisMarks(position: .trailing) { v in AxisGridLine(); AxisValueLabel { if let d = v.as(Double.self) { Text(s.format(d)) } } } }
            .frame(height: 140)
        }
        .contentShape(Rectangle())
        .onTapGesture { expanded = s }
    }
}
