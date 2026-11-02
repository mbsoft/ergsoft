import SwiftUI
import UIKit

struct AboutView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var settings: UserSettings

    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—" }
    private var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—" }
    private var bundleID: String { Bundle.main.bundleIdentifier ?? "—" }
    private var deviceModel: String {
        var sys = utsname(); uname(&sys)
        return withUnsafePointer(to: &sys.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) } }
    }
    private var buildDate: String {
        guard let url = Bundle.main.executableURL,
              let d = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else { return "—" }
        return d.formatted(date: .abbreviated, time: .shortened)
    }
    private var diagnosticsText: String {
        """
        ErgSoft \(version) (\(build))
        \(bundleID)
        \(deviceModel) · iOS \(UIDevice.current.systemVersion)
        Machine: \(ble.ergConnected ? "\(ble.ergName) (\(ble.ergKind.rawValue))" : "none")
        Units: \(settings.units.rawValue) · Language: \(settings.language.rawValue)
        """
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(uiImage: UIImage(named: "AppIcon") ?? UIImage())
                        .resizable().frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                        .overlay { if UIImage(named: "AppIcon") == nil { RowerGlyph(size: 60) } }
                    Text("ErgSoft").font(.title2.bold())
                    Text("Version \(version) (\(build))").font(.subheadline).foregroundStyle(.secondary)
                    Text("Open-source training app for FTMS rowers and bikes").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section("Build") {
                LabeledContent("Version", value: version)
                LabeledContent("Build", value: build)
                LabeledContent("Built", value: buildDate)
                LabeledContent("Bundle ID", value: bundleID).font(.footnote)
                LabeledContent("Device", value: "\(deviceModel) · iOS \(UIDevice.current.systemVersion)")
                Button {
                    UIPasteboard.general.string = diagnosticsText
                } label: { Label("Copy diagnostics", systemImage: "doc.on.doc") }
            }

            Section("License") {
                Text("ErgSoft is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. It is distributed WITHOUT ANY WARRANTY.")
                    .font(.footnote).foregroundStyle(.secondary)
                Link(destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!) {
                    Label("GNU GPL v3 — full text", systemImage: "doc.text")
                }
                Link(destination: URL(string: "https://github.com/mbsoft/ergsoft")!) {
                    Label("Source code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: "https://github.com/mbsoft/ergsoft/issues")!) {
                    Label("Report a bug / request a feature", systemImage: "ladybug")
                }
            }

            Section("Acknowledgements") {
                ack("Bluetooth SIG — Fitness Machine Service (FTMS) and Heart Rate Service specifications",
                    url: "https://www.bluetooth.com/specifications/specs/fitness-machine-service-1-0/")
                ack("Concept2 — pace ↔ watts relationship (2.8 / pace³)",
                    url: "https://www.concept2.com/indoor-rowers/training/calculators/watts-calculator")
                ack("Apple — SwiftUI, Swift Charts, HealthKit, CoreBluetooth, WatchConnectivity, WidgetKit, App Intents", url: nil)
                Text("No third-party packages. Rogue, Concept2, Strava, TrainingPeaks, Intervals.icu and Rojabo are trademarks of their respective owners; ErgSoft is not affiliated with them.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            Section("Privacy") {
                Text("Workouts are stored on this device and, if you allow it, in Apple Health. ErgSoft has no server and sends nothing anywhere unless you connect an integration. Bluetooth is used only to talk to your erg and heart-rate sensors.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                Link(destination: URL(string: "mailto:jwelch@mbsoft.com?subject=ErgSoft%20\(version)")!) {
                    Label("Contact: jwelch@mbsoft.com", systemImage: "envelope")
                }
                Text("© 2026 Jim Welch · mbsoft").font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("About")
    }

    private func ack(_ text: String, url: String?) -> some View {
        Group {
            if let url, let u = URL(string: url) {
                Link(destination: u) { Text(text).font(.footnote) }
            } else {
                Text(text).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
