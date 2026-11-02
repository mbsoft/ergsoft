import SwiftUI

struct DevicesView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var watch: WatchHRReceiver
    @EnvironmentObject var engine: WorkoutEngine
    @EnvironmentObject var broadcaster: HRBroadcaster

    var body: some View {
        NavigationStack {
            List {
                Section("Machine") {
                    if ble.ergConnected {
                        LabeledContent(ble.ergName, value: ble.ergKind.rawValue.capitalized)
                        NavigationLink("Diagnostics (raw FTMS data)") { DiagnosticsView() }
                        Button("Disconnect", role: .destructive) { ble.disconnectErg() }
                    } else {
                        Text("Not connected").foregroundStyle(.secondary)
                    }
                }
                Section("Heart rate") {
                    LabeledContent("Apple Watch", value: watch.statusText)
                    LabeledContent("Paired / app installed / reachable",
                                   value: "\(watch.isPaired ? "✓" : "✗") / \(watch.isWatchAppInstalled ? "✓" : "✗") / \(watch.isReachable ? "✓" : "✗")")
                    if let e = watch.lastError { Text(e).font(.caption).foregroundStyle(.red) }
                    LabeledContent("HealthKit (any watch workout)", value: engine.healthHR.heartRate.map { "\($0) bpm" } ?? "--")
                    if ble.hrStrapConnected {
                        LabeledContent("Strap", value: ble.strapHeartRate.map { "\($0) bpm" } ?? "--")
                        Button("Disconnect strap", role: .destructive) { ble.disconnectStrap() }
                    }
                }
                Section {
                    Toggle("Send HR to erg console", isOn: $broadcaster.enabled)
                    Text(broadcaster.status).font(.caption).foregroundStyle(.secondary)
                    if broadcaster.subscriberCount > 0 {
                        LabeledContent("Sending", value: broadcaster.lastSent.map { "\($0) bpm" } ?? "--")
                    }
                } header: { Text("Console heart rate") } footer: {
                    Text("Keep ErgSoft on screen while you pair. On the Rogue console choose the heart-rate device named “ErgSoft HR”.")
                }
                Section {
                    ForEach(ble.devices) { d in
                        Button { ble.connect(d) } label: {
                            HStack {
                                if d.isHeartRateOnly { Image(systemName: "heart") } else { RowerGlyph(size: 20) }
                                Text(d.name)
                                Spacer()
                                Text("\(d.rssi) dBm").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Nearby")
                        Spacer()
                        if ble.isScanning { ProgressView().controlSize(.small) }
                        Button(ble.isScanning ? "Stop" : "Scan") { ble.isScanning ? ble.stopScan() : ble.startScan() }
                            .disabled(!ble.isPoweredOn)
                    }
                } footer: {
                    Text(ble.isPoweredOn ? "Turn on the erg console so it advertises, then tap Scan." : "Bluetooth is off.")
                }
            }
            .navigationTitle("Devices")
            .toolbar { ToolbarItem(placement: .topBarLeading) { MenuButton() } }
            .onAppear { engine.healthHR.start() }
            .onChange(of: broadcaster.enabled) { _, on in UIApplication.shared.isIdleTimerDisabled = on }
        }
    }
}
