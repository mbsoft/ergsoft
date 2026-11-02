import SwiftUI

struct BenchmarksView: View {
    @EnvironmentObject var settings: UserSettings
    @State private var activity: ErgKind = .rower
    @State private var editing: BenchmarkTest?

    var body: some View {
        List {
            Picker("", selection: $activity) {
                Text(L10n.t("rower")).tag(ErgKind.rower)
                Text(L10n.t("bike")).tag(ErgKind.bike)
            }.pickerStyle(.segmented).listRowBackground(Color.clear)

            if settings.units == .imperial {
                Text(L10n.t("bench.imperial_note")).font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach(BenchmarkTest.all.filter { $0.meters != nil }) { row($0) }
            } header: { Text(L10n.t("distance")) }

            Section {
                ForEach(BenchmarkTest.all.filter { $0.meters == nil }) { row($0) }
            } header: { Text(L10n.t("watts")) } footer: { Text(L10n.t("bench.spi_help")).font(.caption) }
        }
        .navigationTitle(L10n.t("benchmarks"))
        .sheet(item: $editing) { t in BenchmarkEditor(test: t, activity: activity).environmentObject(settings) }
    }

    private func row(_ t: BenchmarkTest) -> some View {
        let b = settings.benchmark(t.key, activity)
        return Button { editing = t } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(t.title(units: settings.units)).foregroundStyle(.primary)
                    if let b { Text(b.date, style: .date).font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer()
                Text(b.map { format($0, t) } ?? L10n.t("not_set")).foregroundStyle(b == nil ? .tertiary : .secondary).monospacedDigit()
            }
        }
    }

    static func format(_ b: Benchmark, _ t: BenchmarkTest) -> String {
        switch t.kind {
        case .time: return Fmt.pace(b.value).replacingOccurrences(of: ".0", with: "")   // m:ss.t
        case .watts: return "\(Int(b.value)) W"
        case .index: return String(format: "%.1f", b.value)
        }
    }
    private func format(_ b: Benchmark, _ t: BenchmarkTest) -> String { Self.format(b, t) }
}

struct BenchmarkEditor: View {
    @EnvironmentObject var settings: UserSettings
    @Environment(\.dismiss) private var dismiss
    let test: BenchmarkTest
    let activity: ErgKind
    @State private var minutes = 0
    @State private var seconds = 0
    @State private var tenths = 0
    @State private var number = ""
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section(test.title(units: settings.units)) {
                    switch test.kind {
                    case .time:
                        HStack(spacing: 0) {
                            Picker("min", selection: $minutes) { ForEach(0..<90) { Text("\($0)").tag($0) } }.pickerStyle(.wheel).frame(width: 80).clipped()
                            Text(":")
                            Picker("sec", selection: $seconds) { ForEach(0..<60) { Text(String(format: "%02d", $0)).tag($0) } }.pickerStyle(.wheel).frame(width: 80).clipped()
                            Text(".")
                            Picker("tenths", selection: $tenths) { ForEach(0..<10) { Text("\($0)").tag($0) } }.pickerStyle(.wheel).frame(width: 60).clipped()
                        }.frame(maxWidth: .infinity)
                        if let m = (settings.units == .imperial ? test.imperialMeters : test.meters) {
                            let total = Double(minutes * 60 + seconds) + Double(tenths) / 10
                            if total > 0 { LabeledContent(L10n.t("pace"), value: Fmt.pace(total / (Double(m) / 500)) + " /500m") }
                        }
                    case .watts:
                        HStack { TextField("0", text: $number).keyboardType(.numberPad); Text("W").foregroundStyle(.secondary) }
                    case .index:
                        TextField("0.0", text: $number).keyboardType(.decimalPad)
                    }
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                }
                if settings.benchmark(test.key, activity) != nil {
                    Button("Remove", role: .destructive) { settings.removeBenchmark("\(activity.rawValue)-\(test.key)"); dismiss() }
                }
            }
            .navigationTitle(L10n.t("benchmarks"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear {
                if let b = settings.benchmark(test.key, activity) {
                    date = b.date
                    switch test.kind {
                    case .time: minutes = Int(b.value) / 60; seconds = Int(b.value) % 60; tenths = Int((b.value - Double(Int(b.value))) * 10)
                    case .watts: number = String(Int(b.value))
                    case .index: number = String(format: "%.1f", b.value)
                    }
                }
            }
        }
    }

    private func save() {
        let v: Double
        switch test.kind {
        case .time: v = Double(minutes * 60 + seconds) + Double(tenths) / 10
        case .watts, .index: v = Double(number.replacingOccurrences(of: ",", with: ".")) ?? 0
        }
        guard v > 0 else { return }
        settings.setBenchmark(Benchmark(activity: activity, key: test.key, value: v, date: date))
        dismiss()
    }
}
