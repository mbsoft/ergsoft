import SwiftUI

/// Everything the machine sends over FTMS, raw and decoded, plus derived metrics.
struct DiagnosticsView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var engine: WorkoutEngine
    @State private var targetWatts = 150
    @State private var targetHR = 140

    var body: some View {
        let s = ble.latest
        List {
            Section("Link") {
                row("Machine", ble.ergConnected ? "\(ble.ergName) (\(ble.ergKind.rawValue))" : "not connected")
                row("Packets / s", String(format: "%.1f", ble.packetsPerSecond))
                row("Flags", String(format: "0x%04X  %@", s.flags, bits(s.flags)))
                row("Raw", s.raw.map { String(format: "%02X", $0) }.joined(separator: " ")).font(.system(.caption, design: .monospaced))
            }
            Section("Instantaneous") {
                row(ble.ergKind == .bike ? "Cadence" : "Stroke rate", s.strokeRate.map { "\($0) \(ble.ergKind == .bike ? "rpm" : "s/m")" })
                row("Stroke count", s.strokeCount.map(String.init))
                row("Distance", s.distanceMeters.map { "\(Int($0)) m" })
                row("Pace", s.paceSecondsPer500m.map { Fmt.pace($0) + " /500m" })
                row("Speed", s.speedKph.map { String(format: "%.2f km/h", $0) })
                row("Power", s.powerWatts.map { "\($0) W" })
                row("Resistance", s.resistanceLevel.map(String.init))
                row("Heart rate (machine)", s.heartRate.map { "\($0) bpm" })
                row("Elapsed (machine)", s.elapsedSeconds.map { Fmt.clock(Double($0)) })
                row("Remaining (machine)", s.remainingSeconds.map { Fmt.clock(Double($0)) })
            }
            Section("Averages & energy") {
                row("Avg stroke rate / cadence", s.averageStrokeRate.map { "\($0)" })
                row("Avg pace", s.averagePaceSecondsPer500m.map { Fmt.pace($0) })
                row("Avg speed", s.averageSpeedKph.map { String(format: "%.2f km/h", $0) })
                row("Avg power", s.averagePowerWatts.map { "\($0) W" })
                row("Calories total", s.caloriesTotal.map { "\($0) kcal" })
                row("Calories / hour", s.caloriesPerHour.map { "\($0)" })
                row("Calories / minute", s.caloriesPerMinute.map { "\($0)" })
                row("MET", s.met.map { String(format: "%.1f", $0) })
            }
            Section("Derived") {
                row("Watts / stroke", derived.wattsPerStroke.map { String(format: "%.1f", $0) })
                row("Meters / stroke", derived.metersPerStroke.map { String(format: "%.1f", $0) })
                row("Pace → watts (C2)", derived.paceWatts.map { "\($0) W" })
                row("Watts → pace (C2)", derived.wattsPace.map { Fmt.pace($0) })
                row("Projected 500m", derived.proj500.map { Fmt.pace($0) })
                row("Projected 2k", derived.proj2k.map { Fmt.clock($0) })
                row("HR / watt", derived.hrPerWatt.map { String(format: "%.2f", $0) })
                row("Rolling 10 s pace", derived.rollingPace.map { Fmt.pace($0) })
            }
            Section("Machine state") {
                row("Training status", ble.trainingStatus)
                row("Machine status", ble.machineStatus)
                row("Power range", ble.powerRange)
                row("Resistance range", ble.resistanceRange)
                if let f = ble.feature {
                    DisclosureGroup("Features (\(f.machineList.count))") {
                        ForEach(f.machineList, id: \.self) { Text($0).font(.caption) }
                    }
                    DisclosureGroup("Targets supported (\(f.targetList.count))") {
                        ForEach(f.targetList, id: \.self) { Text($0).font(.caption) }
                    }
                } else { row("Features", "not read") }
            }
            Section("Control point") {
                Stepper("Target power \(targetWatts) W", value: $targetWatts, in: 50...500, step: 10)
                Button("Send target power") { ble.setTargetPower(targetWatts) }
                Stepper("Target HR \(targetHR)", value: $targetHR, in: 80...200, step: 5)
                Button("Send target HR") { ble.setTargetHeartRate(targetHR) }
                HStack {
                    Button("Request control") { ble.requestControl() }
                    Spacer()
                    Button("Start") { ble.startMachine() }
                    Spacer()
                    Button("Stop") { ble.stopMachine() }
                    Spacer()
                    Button("Reset", role: .destructive) { ble.resetMachine() }
                }.buttonStyle(.bordered).font(.caption)
                if let last = ble.controlPointLog.first { row("Last response", last).font(.system(.caption, design: .monospaced)) }
            }
            Section("Event log") {
                ForEach(ble.eventLog.prefix(60), id: \.self) { Text($0).font(.system(.caption2, design: .monospaced)) }
            }
        }
        .navigationTitle("Diagnostics")
    }

    private func row(_ k: String, _ v: String?) -> some View {
        LabeledContent(k) { Text(v ?? "—").foregroundStyle(v == nil ? .tertiary : .secondary).multilineTextAlignment(.trailing) }
    }

    private func bits(_ f: UInt16) -> String {
        let names = ble.ergKind == .bike
            ? ["more","avgSpd","cad","avgCad","dist","res","pwr","avgPwr","energy","hr","met","elapsed","remain"]
            : ["more","avgSR","dist","pace","avgPace","pwr","avgPwr","res","energy","hr","met","elapsed","remain"]
        return names.enumerated().filter { f & (1 << UInt16($0.offset)) != 0 }.map(\.element).joined(separator: ",")
    }

    private var derived: Derived { Derived(sample: ble.latest, engine: engine) }
}

@MainActor
struct Derived {
    let sample: ErgSample
    let engine: WorkoutEngine

    var wattsPerStroke: Double? {
        guard let w = sample.powerWatts, let sr = sample.strokeRate, sr > 0 else { return nil }
        return Double(w) * 60.0 / sr        // joules per stroke
    }
    var metersPerStroke: Double? {
        guard engine.strokes > 5 else { return nil }
        return engine.meters / Double(engine.strokes)
    }
    /// Concept2: watts = 2.8 / (sec per metre)^3
    var paceWatts: Int? {
        guard let p = sample.paceSecondsPer500m, p > 0 else { return nil }
        let spm = p / 500.0
        return Int((2.8 / (spm * spm * spm)).rounded())
    }
    var wattsPace: Double? {
        guard let w = sample.powerWatts, w > 0 else { return nil }
        return pow(2.8 / Double(w), 1.0 / 3.0) * 500.0
    }
    var proj500: Double? { sample.paceSecondsPer500m }
    var proj2k: Double? { sample.paceSecondsPer500m.map { $0 * 4 } }
    var hrPerWatt: Double? {
        guard let hr = engine.heartRate, let w = sample.powerWatts, w > 0 else { return nil }
        return Double(hr) / Double(w)
    }
    var rollingPace: Double? { engine.rollingPace10s }
}
