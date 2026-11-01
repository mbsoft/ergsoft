import SwiftUI
import SwiftData

struct WorkoutView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var watch: WatchHRReceiver
    @EnvironmentObject var engine: WorkoutEngine
    @Environment(\.modelContext) private var context

    @State private var selectedPlan: WorkoutPlan = .justRow
    @State private var showSummary: WorkoutSession?

    private var isRower: Bool { ble.ergKind != .bike }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                header
                if engine.currentInterval != nil { intervalBar }
                metrics
                Spacer(minLength: 0)
                controls
            }
            .padding()
            .navigationTitle("ErgSoft")
            .toolbar {
                if engine.state == .idle {
                    Menu {
                        ForEach(WorkoutPlan.presets) { p in
                            Button(p.name) { selectedPlan = p }
                        }
                    } label: { Label(selectedPlan.name, systemImage: "list.bullet") }
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
            Text(ble.ergConnected ? ble.ergName : "No machine").font(.subheadline)
            Spacer()
            if watch.heartRate != nil {
                Label("Watch", systemImage: "applewatch").font(.caption).foregroundStyle(.red)
            } else if ble.hrStrapConnected {
                Label("Strap", systemImage: "heart").font(.caption).foregroundStyle(.red)
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

    private var metrics: some View {
        let c = engine.current
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                MetricTile(label: "Time", value: Fmt.clock(engine.elapsed))
                MetricTile(label: "Meters", value: Fmt.meters(engine.meters))
            }
            HStack(spacing: 8) {
                if isRower {
                    MetricTile(label: "Pace", value: Fmt.pace(c.paceSecondsPer500m), unit: "/500m")
                } else {
                    MetricTile(label: "Speed", value: c.speedKph.map { String(format: "%.1f", $0) } ?? "--", unit: "km/h")
                }
                MetricTile(label: "Watts", value: c.powerWatts.map(String.init) ?? "--")
            }
            HStack(spacing: 8) {
                MetricTile(label: isRower ? "s/m" : "rpm", value: c.strokeRate.map { String(Int($0.rounded())) } ?? "--")
                MetricTile(label: "Heart", value: engine.heartRate.map(String.init) ?? "--", unit: "bpm", tint: .red)
            }
            HStack(spacing: 8) {
                MetricTile(label: "Cal", value: String(engine.calories))
                MetricTile(label: "Strokes", value: String(engine.strokes))
            }
        }
    }

    @ViewBuilder private var controls: some View {
        switch engine.state {
        case .idle, .finished:
            Button {
                watch.sendCommand("start")
                engine.start(plan: selectedPlan)
            } label: { Text("Start").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!ble.ergConnected)
        case .running:
            Button { engine.pause() } label: { Text("Pause").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).controlSize(.large)
        case .paused:
            HStack {
                Button { engine.resume() } label: { Text("Resume").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).controlSize(.large)
                Button(role: .destructive) {
                    watch.sendCommand("stop")
                    let s = engine.finish(into: context, machineName: ble.ergName, kind: ble.ergKind)
                    Task {
                        if let uuid = try? await HealthKitManager.shared.save(s) { s.healthKitUUID = uuid; try? context.save() }
                    }
                    showSummary = s
                    engine.reset()
                } label: { Text("Finish").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
    }
}
