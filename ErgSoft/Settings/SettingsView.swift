import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: UserSettings
    @State private var dob = Date(timeIntervalSince1970: 0)
    @State private var hasDOB = false
    @State private var weightText = ""
    @State private var maxHRText = ""

    private var regions: [(String, String)] {
        Locale.Region.isoRegions
            .filter { $0.identifier.count == 2 }
            .map { ($0.identifier, Locale.current.localizedString(forRegionCode: $0.identifier) ?? $0.identifier) }
            .sorted { $0.1 < $1.1 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t("profile")) {
                    Picker(L10n.t("units"), selection: Binding(get: { settings.units }, set: { settings.units = $0 })) {
                        Text(L10n.t("metric")).tag(UnitSystem.metric)
                        Text(L10n.t("imperial")).tag(UnitSystem.imperial)
                    }.pickerStyle(.segmented)

                    Picker(L10n.t("appearance"), selection: Binding(get: { settings.appearance }, set: { settings.appearance = $0 })) {
                        ForEach(Appearance.allCases) { Text(L10n.t($0.rawValue)).tag($0) }
                    }.pickerStyle(.segmented)

                    Picker(L10n.t("language"), selection: Binding(get: { settings.language }, set: { settings.language = $0 })) {
                        ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
                    }

                    Picker(L10n.t("country"), selection: $settings.country) {
                        ForEach(regions, id: \.0) { Text($0.1).tag($0.0) }
                    }

                    Toggle(L10n.t("dob"), isOn: $hasDOB)
                        .onChange(of: hasDOB) { _, on in settings.dateOfBirth = on ? dob : nil }
                    if hasDOB {
                        DatePicker("", selection: $dob, in: ...Date(), displayedComponents: .date)
                            .datePickerStyle(.compact).labelsHidden()
                            .onChange(of: dob) { _, d in settings.dateOfBirth = d }
                    }

                    HStack {
                        Text(L10n.t("weight"))
                        Spacer()
                        TextField("0", text: $weightText).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                            .onChange(of: weightText) { _, t in if let v = Double(t.replacingOccurrences(of: ",", with: ".")) { settings.weightDisplay = v } }
                        Text(settings.weightUnit).foregroundStyle(.secondary)
                    }
                }

                Section {
                    HStack {
                        Text(L10n.t("max_hr"))
                        Spacer()
                        TextField("\(settings.maxHeartRate)", text: $maxHRText).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80)
                            .onChange(of: maxHRText) { _, t in settings.maxHRManual = Int(t) ?? 0 }
                        Text("bpm").foregroundStyle(.secondary)
                    }
                    if settings.maxHRIsDerived {
                        Text("\(settings.maxHeartRate) bpm " + L10n.t("derived_from_age")).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(1...5, id: \.self) { z in
                        let r = settings.zoneRange(z)
                        HStack {
                            Circle().fill(HRZone.color(z)).frame(width: 10, height: 10)
                            Text("Z\(z)  \(HRZone.name(z))")
                            Spacer()
                            Text("\(r.lowerBound)–\(r.upperBound)").monospacedDigit().foregroundStyle(.secondary)
                        }.font(.subheadline)
                    }
                } header: { Text(L10n.t("hr_zones")) }

                Section {
                    NavigationLink(L10n.t("benchmarks")) { BenchmarksView() }
                    NavigationLink(L10n.t("integrations")) { IntegrationsView() }
                }
                Section {
                    NavigationLink { AboutView() } label: {
                        LabeledContent("About", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                    }
                }
            }
            .navigationTitle(L10n.t("settings"))
            .toolbar { ToolbarItem(placement: .topBarLeading) { MenuButton() } }
            .onAppear {
                if let d = settings.dateOfBirth { dob = d; hasDOB = true }
                weightText = settings.weightKg > 0 ? String(format: "%.1f", settings.weightDisplay) : ""
                maxHRText = settings.maxHRManual > 0 ? String(settings.maxHRManual) : ""
            }
            .onChange(of: settings.units) { _, _ in
                weightText = settings.weightKg > 0 ? String(format: "%.1f", settings.weightDisplay) : ""
            }
        }
    }
}

enum HRZone {
    static func color(_ z: Int) -> Color { [Color.gray, .blue, .green, .yellow, .orange, .red][max(0, min(5, z))] }
    static func name(_ z: Int) -> String { ["", "Recovery", "Endurance", "Tempo", "Threshold", "Max"][max(0, min(5, z))] }
}
