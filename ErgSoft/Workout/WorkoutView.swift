import SwiftUI
import SwiftData

struct WorkoutView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var watch: WatchHRReceiver
    @EnvironmentObject var engine: WorkoutEngine
    @Environment(\.modelContext) private var context
    @EnvironmentObject var settings: UserSettings
    @Environment(\.verticalSizeClass) private var vSize
    @Environment(\.horizontalSizeClass) private var hSize
    @AppStorage("workoutStyle") private var workoutStyle = "tiles"
    private var isPad: Bool { hSize == .regular && vSize == .regular }
    private var landscape: Bool { vSize == .compact }

    @State private var selectedPlan: WorkoutPlan = .justRow
    @State private var showSummary: WorkoutSession?

    private var isRower: Bool { ble.ergKind != .bike }

    var body: some View {
        NavigationStack {
            Group {
                if isPad && workoutStyle == "river" {
                    RiverView()
                } else if landscape {
                    VStack(spacing: 6) {
                        header
                        if engine.currentInterval != nil { intervalBar }
                        metrics
                    }
                    .padding(.horizontal).padding(.top, 4)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            header
                            if engine.currentInterval != nil { intervalBar }
                            metrics
                        }
                        .padding()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                controls
                    .padding(.horizontal).padding(.vertical, landscape ? 4 : 10)
                    .background(.bar)
            }
            .navigationTitle("ErgSoft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar((landscape || (isPad && workoutStyle == "river")) ? .hidden : .visible, for: .navigationBar)
            .overlay(alignment: .topLeading) {
                if landscape || (isPad && workoutStyle == "river") {
                    HStack(spacing: 8) {
                        FloatingMenuButton()
                        if isPad {
                            Picker("", selection: $workoutStyle) {
                                Image(systemName: "square.grid.2x2").tag("tiles")
                                Image(systemName: "water.waves").tag("river")
                            }.pickerStyle(.segmented).frame(width: 100).padding(.top, 8)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { MenuButton() }
                if isPad {
                    ToolbarItem(placement: .topBarTrailing) {
                        Picker("", selection: $workoutStyle) {
                            Image(systemName: "square.grid.2x2").tag("tiles")
                            Image(systemName: "water.waves").tag("river")
                        }.pickerStyle(.segmented).frame(width: 110)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if engine.state == .idle {
                        Menu {
                            ForEach(WorkoutPlan.presets) { p in
                                Button(p.name) { selectedPlan = p }
                            }
                        } label: { Label(selectedPlan.name, systemImage: "list.bullet") }
                    }
                }
            }
            .sheet(item: $showSummary) { s in SessionDetailView(session: s) }
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        }
    }

    private var header: some View {
        HStack {
            Circle().fill(ble.ergConnected ? .green : .gray).frame(width: 10, height: 10)
            Text(ble.ergConnected ? ble.ergName : L10n.t("no_machine")).font(.subheadline)
            Spacer()
            if watch.heartRate != nil {
                Label("Watch", systemImage: "applewatch").font(.caption).foregroundStyle(.red)
            } else if ble.hrStrapConnected {
                Label("Strap", systemImage: "heart").font(.caption).foregroundStyle(.red)
            } else if engine.healthHR.heartRate != nil {
                Label("Health", systemImage: "heart.text.square").font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var intervalBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(engine.intervalIndex + 1)/\(engine.plan.intervals.count)  \(engine.currentInterval?.label ?? "")")
                    .font(.subheadline.bold())
                    .foregroundStyle(engine.currentInterval?.kind == .rest ? .blue : .orange)
                Spacer()
                Text(engine.intervalRemainingText).font(.subheadline).monospacedDigit()
            }
            ProgressView(value: engine.intervalProgress ?? 0)
                .tint(engine.currentInterval?.kind == .rest ? .blue : .orange)
        }
    }

    private struct Tile: Identifiable { let id: Int; let label: String; let value: String; var unit = ""; var tint: Color = .primary }

    private var tiles: [Tile] {
        let c = engine.current
        let hrTint = engine.heartRate.map { HRZone.color(settings.zone(for: $0)) } ?? .red
        let hrUnit = engine.heartRate.map { "Z\(settings.zone(for: $0)) · \(Int(Double($0) / Double(settings.maxHeartRate) * 100))%" } ?? "bpm"
        return [
            Tile(id: 0, label: L10n.t("time"), value: Fmt.clock(engine.elapsed)),
            Tile(id: 1, label: settings.units == .metric ? L10n.t("meters") : L10n.t("distance"),
                 value: settings.units == .metric ? Fmt.meters(engine.meters) : settings.distance(engine.meters)),
            isRower ? Tile(id: 2, label: L10n.t("pace"), value: Fmt.pace(c.paceSecondsPer500m), unit: "/500m")
                    : Tile(id: 2, label: "Speed", value: c.speedKph.map { String(format: "%.1f", $0) } ?? "--", unit: "km/h"),
            Tile(id: 3, label: L10n.t("watts"), value: c.powerWatts.map(String.init) ?? "--", unit: c.averagePowerWatts.map { "avg \($0)" } ?? ""),
            Tile(id: 4, label: isRower ? "s/m" : "rpm", value: c.strokeRate.map { String(Int($0.rounded())) } ?? "--", unit: c.resistanceLevel.map { "drag \($0)" } ?? ""),
            Tile(id: 5, label: L10n.t("heart"), value: engine.heartRate.map(String.init) ?? "--", unit: hrUnit, tint: hrTint),
            Tile(id: 6, label: L10n.t("cal"), value: String(engine.calories), unit: c.caloriesPerHour.map { "\($0)/hr" } ?? ""),
            Tile(id: 7, label: L10n.t("avg_pace"), value: Fmt.pace(c.averagePaceSecondsPer500m), unit: "\(engine.strokes) \(L10n.t("strokes"))"),
        ]
    }

    private var metrics: some View {
        let t = tiles
        let perRow = landscape ? 4 : 2
        let spacing: CGFloat = landscape ? 6 : 8
        return VStack(spacing: spacing) {
            ForEach(0..<(t.count / perRow), id: \.self) { r in
                HStack(spacing: spacing) {
                    ForEach(t[(r * perRow)..<((r + 1) * perRow)]) { x in
                        MetricTile(label: x.label, value: x.value, unit: x.unit, tint: x.tint, compact: landscape)
                    }
                }
            }
        }
    }

    @ViewBuilder private var controls: some View {
        switch engine.state {
        case .idle, .finished:
            Button {
                watch.sendCommand("start")
                HealthKitManager.shared.launchWatchApp(kind: ble.ergKind)
                engine.start(plan: selectedPlan)
            } label: { Text(L10n.t("start")).frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(landscape ? .regular : .large)
                .disabled(!ble.ergConnected)
        case .running:
            Button { engine.pause() } label: { Text(L10n.t("pause")).frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).controlSize(landscape ? .regular : .large)
        case .paused:
            HStack {
                Button { engine.resume() } label: { Text(L10n.t("resume")).frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).controlSize(landscape ? .regular : .large)
                Button(role: .destructive) {
                    watch.sendCommand("stop")
                    let s = engine.finish(into: context, machineName: ble.ergName, kind: ble.ergKind)
                    Task {
                        if let uuid = try? await HealthKitManager.shared.save(s) { s.healthKitUUID = uuid; try? context.save() }
                    }
                    showSummary = s
                    engine.reset()
                } label: { Text(L10n.t("finish")).frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(landscape ? .regular : .large)
            }
        }
    }
}
