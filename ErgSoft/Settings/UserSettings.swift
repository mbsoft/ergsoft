import Foundation
import SwiftUI
import Combine

enum UnitSystem: String, CaseIterable, Identifiable { case metric, imperial; var id: String { rawValue } }
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var scheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
}
enum AppLanguage: String, CaseIterable, Identifiable {
    case en = "en", frCA = "fr-CA", esMX = "es-MX", ptBR = "pt-BR"
    var id: String { rawValue }
    var displayName: String {
        switch self { case .en: "English"; case .frCA: "Français (Canada)"; case .esMX: "Español (México)"; case .ptBR: "Português (Brasil)" }
    }
}

/// A personal benchmark. `key` identifies the test (e.g. "2k", "ftp"); `activity` is rower/bike.
struct Benchmark: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case time, watts, index }
    var id: String { "\(activity.rawValue)-\(key)" }
    var activity: ErgKind
    var key: String
    var value: Double        // seconds for .time, watts for .watts, unitless for .index
    var date: Date
}

/// Catalog of benchmark tests. Distances in metres; imperial equivalents are the common rounded ones.
struct BenchmarkTest: Identifiable, Hashable {
    let key: String
    let kind: Benchmark.Kind
    let meters: Int?               // nil for non-distance tests
    let imperialMeters: Int?       // suggested imperial equivalent distance
    let imperialLabel: String?
    let labelKey: String

    var id: String { key }

    static let all: [BenchmarkTest] = [
        .init(key: "500m", kind: .time, meters: 500,  imperialMeters: 402,  imperialLabel: "¼ mi",  labelKey: "500m"),
        .init(key: "1k",   kind: .time, meters: 1000, imperialMeters: 805,  imperialLabel: "½ mi",  labelKey: "1k"),
        .init(key: "2k",   kind: .time, meters: 2000, imperialMeters: 1609, imperialLabel: "1 mi",  labelKey: "2k"),
        .init(key: "5k",   kind: .time, meters: 5000, imperialMeters: 4828, imperialLabel: "3 mi",  labelKey: "5k"),
        .init(key: "6k",   kind: .time, meters: 6000, imperialMeters: 6437, imperialLabel: "4 mi",  labelKey: "6k"),
        .init(key: "ftp",  kind: .watts, meters: nil, imperialMeters: nil, imperialLabel: nil, labelKey: "bench.ftp"),
        .init(key: "max",  kind: .watts, meters: nil, imperialMeters: nil, imperialLabel: nil, labelKey: "bench.max"),
        .init(key: "spi",  kind: .index, meters: nil, imperialMeters: nil, imperialLabel: nil, labelKey: "bench.spi"),
    ]

    func title(units: UnitSystem) -> String {
        if let m = meters {
            if units == .imperial, let il = imperialLabel { return "\(il) (\(imperialMeters ?? m) m)" }
            return key
        }
        return L10n.t(labelKey)
    }
}

/// All user preferences, persisted in UserDefaults.
@MainActor
final class UserSettings: ObservableObject {
    static let shared = UserSettings()

    @AppStorage("units") var unitsRaw = UnitSystem.metric.rawValue { didSet { objectWillChange.send() } }
    @AppStorage("appearance") var appearanceRaw = Appearance.system.rawValue { didSet { objectWillChange.send() } }
    @AppStorage("language") var languageRaw = AppLanguage.en.rawValue { didSet { L10n.language = language; objectWillChange.send() } }
    @AppStorage("dob") var dobTimestamp: Double = 0 { didSet { objectWillChange.send() } }
    @AppStorage("country") var country = Locale.current.region?.identifier ?? "US" { didSet { objectWillChange.send() } }
    @AppStorage("maxHRManual") var maxHRManual: Int = 0 { didSet { objectWillChange.send() } }   // 0 = derive from age
    @AppStorage("weightKg") var weightKg: Double = 0 { didSet { objectWillChange.send() } }
    @AppStorage("benchmarksJSON") private var benchmarksJSON = "[]" { didSet { objectWillChange.send() } }
    @AppStorage("integrations") private var integrationsJSON = "{}" { didSet { objectWillChange.send() } }

    private init() { L10n.language = language }

    var appearance: Appearance { get { Appearance(rawValue: appearanceRaw) ?? .system } set { appearanceRaw = newValue.rawValue } }
    var units: UnitSystem { get { UnitSystem(rawValue: unitsRaw) ?? .metric } set { unitsRaw = newValue.rawValue } }
    var language: AppLanguage { get { AppLanguage(rawValue: languageRaw) ?? .en } set { languageRaw = newValue.rawValue } }
    var dateOfBirth: Date? {
        get { dobTimestamp == 0 ? nil : Date(timeIntervalSince1970: dobTimestamp) }
        set { dobTimestamp = newValue?.timeIntervalSince1970 ?? 0 }
    }
    var age: Int? { dateOfBirth.map { Calendar.current.dateComponents([.year], from: $0, to: Date()).year ?? 0 } }

    /// Max HR: manual override, else 220 − age (Fox), else 185.
    var maxHeartRate: Int {
        if maxHRManual > 0 { return maxHRManual }
        if let a = age, a > 0 { return 220 - a }
        return 185
    }
    var maxHRIsDerived: Bool { maxHRManual == 0 }

    /// Zone 1…5 for a heart rate (50/60/70/80/90 % of max), 0 if below zone 1.
    func zone(for hr: Int) -> Int {
        let pct = Double(hr) / Double(maxHeartRate)
        switch pct { case ..<0.5: return 0; case ..<0.6: return 1; case ..<0.7: return 2; case ..<0.8: return 3; case ..<0.9: return 4; default: return 5 }
    }
    func zoneRange(_ z: Int) -> ClosedRange<Int> {
        let lo = [0, 50, 60, 70, 80, 90][z], hi = [50, 60, 70, 80, 90, 100][z]
        return Int(Double(maxHeartRate) * Double(lo) / 100)...Int(Double(maxHeartRate) * Double(hi) / 100)
    }

    var benchmarks: [Benchmark] {
        get { (try? JSONDecoder().decode([Benchmark].self, from: Data(benchmarksJSON.utf8))) ?? [] }
        set { benchmarksJSON = String(data: (try? JSONEncoder().encode(newValue)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]" }
    }
    func benchmark(_ key: String, _ activity: ErgKind) -> Benchmark? { benchmarks.first { $0.key == key && $0.activity == activity } }
    func setBenchmark(_ b: Benchmark) {
        var list = benchmarks.filter { $0.id != b.id }
        list.append(b)
        benchmarks = list
    }
    func removeBenchmark(_ id: String) { benchmarks = benchmarks.filter { $0.id != id } }

    var integrations: [String: Bool] {
        get { (try? JSONDecoder().decode([String: Bool].self, from: Data(integrationsJSON.utf8))) ?? [:] }
        set { integrationsJSON = String(data: (try? JSONEncoder().encode(newValue)) ?? Data("{}".utf8), encoding: .utf8) ?? "{}" }
    }

    // MARK: Unit helpers
    var weightDisplay: Double {
        get { units == .metric ? weightKg : weightKg * 2.20462 }
        set { weightKg = units == .metric ? newValue : newValue / 2.20462 }
    }
    var weightUnit: String { units == .metric ? "kg" : "lb" }

    func distance(_ meters: Double, compact: Bool = true) -> String {
        switch units {
        case .metric:
            if compact && meters >= 10_000 { return String(format: "%.1fk", meters / 1000) }
            return "\(Int(meters.rounded())) m"
        case .imperial:
            let mi = meters / 1609.344
            if mi < 0.25 { return "\(Int((meters * 1.09361).rounded())) yd" }
            return String(format: "%.1f mi", mi)
        }
    }
}
