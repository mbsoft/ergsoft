import SwiftUI
import SwiftData

enum StatsPeriod: String, CaseIterable, Identifiable {
    case last7, last30, last90, year, all
    var id: String { rawValue }
    var label: String { L10n.t(rawValue) }
    var start: Date? {
        let cal = Calendar.current
        switch self {
        case .last7: return cal.date(byAdding: .day, value: -7, to: .now)
        case .last30: return cal.date(byAdding: .day, value: -30, to: .now)
        case .last90: return cal.date(byAdding: .day, value: -90, to: .now)
        case .year: return cal.date(from: cal.dateComponents([.year], from: .now))
        case .all: return nil
        }
    }
}

struct StatsView: View {
    @EnvironmentObject var settings: UserSettings
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var all: [WorkoutSession]
    @State private var period: StatsPeriod = .last30
    @State private var machine: String = "all"   // "all" | ErgKind rawValue

    private var sessions: [WorkoutSession] {
        all.filter { s in
            (period.start.map { s.startedAt >= $0 } ?? true) &&
            (machine == "all" || s.machineKindRaw == machine) &&
            s.endedAt != nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    filters
                    Text(L10n.t("overall")).font(.title2.bold())
                    if sessions.isEmpty {
                        ContentUnavailableView(L10n.t("no_data"), systemImage: "chart.bar")
                    } else {
                        grid
                        zones
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L10n.t("stats"))
            .toolbar { ToolbarItem(placement: .topBarLeading) { MenuButton() } }
        }
    }

    private var filters: some View {
        VStack(spacing: 10) {
            Picker(L10n.t("machine"), selection: $machine) {
                Text(L10n.t("all_machines")).tag("all")
                Text(L10n.t("rower")).tag(ErgKind.rower.rawValue)
                Text(L10n.t("bike")).tag(ErgKind.bike.rawValue)
            }.pickerStyle(.segmented)
            Picker(L10n.t("period"), selection: $period) {
                ForEach(StatsPeriod.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemGroupedBackground)))
        }
    }

    // MARK: Aggregates
    private var totalMeters: Double { sessions.reduce(0) { $0 + $1.totalMeters } }
    private var totalSeconds: Double { sessions.reduce(0) { $0 + $1.durationSeconds } }
    private var totalCal: Int { sessions.reduce(0) { $0 + $1.calories } }
    private var activeDays: Int { Set(sessions.map { Calendar.current.startOfDay(for: $0.startedAt) }).count }
    private var avgPace: Double? { totalMeters > 0 ? totalSeconds / (totalMeters / 500) : nil }
    private var avgWatts: Int {
        let w = sessions.filter { $0.averageWatts > 0 }
        guard !w.isEmpty else { return 0 }
        // time-weighted
        let num = w.reduce(0) { $0 + $1.averageWatts * $1.durationSeconds }
        let den = w.reduce(0) { $0 + $1.durationSeconds }
        return den > 0 ? Int((num / den).rounded()) : 0
    }
    private var avgRate: Int {
        let s = sessions.filter { $0.strokes > 0 && $0.durationSeconds > 0 }
        let strokes = s.reduce(0) { $0 + $1.strokes }
        let mins = s.reduce(0) { $0 + $1.durationSeconds } / 60
        return mins > 0 ? Int((Double(strokes) / mins).rounded()) : 0
    }
    /// Seconds spent in each HR zone 1…5 across the period.
    private var zoneSeconds: [Double] {
        var z = [Double](repeating: 0, count: 6)
        for s in sessions {
            let pts = s.points.sorted { $0.t < $1.t }
            var prev = 0.0
            for p in pts {
                let dt = max(0, min(5, p.t - prev)); prev = p.t
                if p.heartRate > 0 { z[settings.zone(for: p.heartRate)] += dt }
            }
        }
        return z
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            StatTile(title: L10n.t("total_meters"), value: settings.distance(totalMeters), color: .teal)
            StatTile(title: L10n.t("total_time"), value: hm(totalSeconds), color: .orange)
            StatTile(title: L10n.t("active_days"), value: "\(activeDays)", color: .green)
            StatTile(title: L10n.t("total_cal"), value: totalCal >= 1000 ? String(format: "%.1fk", Double(totalCal) / 1000) : "\(totalCal)", color: .yellow)
            StatTile(title: L10n.t("avg_pace"), value: Fmt.pace(avgPace), color: .teal)
            StatTile(title: L10n.t("avg_watts"), value: "\(avgWatts)", color: .orange)
            StatTile(title: L10n.t("avg_rate"), value: "\(avgRate)", color: .green, glyph: true)
            StatTile(title: L10n.t("sessions"), value: "\(sessions.count)", color: .purple)
        }
    }

    private var zones: some View {
        let z = zoneSeconds
        let total = z.dropFirst().reduce(0, +)
        return VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("hr_zones")).font(.headline)
            if total == 0 {
                Text("—").foregroundStyle(.secondary)
            } else {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 3).fill(HRZone.color(i))
                                .frame(width: max(2, geo.size.width * z[i] / total))
                        }
                    }
                }.frame(height: 14)
                ForEach((1...5).reversed(), id: \.self) { i in
                    HStack {
                        Circle().fill(HRZone.color(i)).frame(width: 10, height: 10)
                        Text("Z\(i) \(HRZone.name(i))").font(.subheadline)
                        Spacer()
                        Text(hm(z[i])).monospacedDigit().font(.subheadline)
                        Text(String(format: "%3.0f%%", z[i] / total * 100)).monospacedDigit().font(.subheadline).foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func hm(_ s: Double) -> String {
        let m = Int(s / 60)
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let color: Color
    var glyph = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if glyph { RowerGlyph(size: 24).foregroundStyle(color) }
                Text(value).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(color).minimumScaleFactor(0.6).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }
}
