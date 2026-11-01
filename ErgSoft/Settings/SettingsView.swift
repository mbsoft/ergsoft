import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var watch: WatchHRReceiver

    var body: some View {
        NavigationStack {
            List {
                Section("Machine") {
                    if ble.ergConnected {
                        LabeledContent(ble.ergName, value: ble.ergKind.rawValue.capitalized)
                        Button("Disconnect", role: .destructive) { ble.disconnectErg() }
                    } else {
                        Text("Not connected").foregroundStyle(.secondary)
                    }
                }
                Section("Heart rate") {
                    LabeledContent("Apple Watch", value: watch.heartRate.map { "\($0) bpm" } ?? (watch.watchReachable ? "Reachable" : "Not reachable"))
                    if ble.hrStrapConnected {
                        LabeledContent("Strap", value: ble.strapHeartRate.map { "\($0) bpm" } ?? "--")
                        Button("Disconnect strap", role: .destructive) { ble.disconnectStrap() }
                    }
                }
                Section {
                    ForEach(ble.devices) { d in
                        Button { ble.connect(d) } label: {
                            HStack {
                                Image(systemName: d.isHeartRateOnly ? "heart" : "figure.rower")
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
        }
    }
}
