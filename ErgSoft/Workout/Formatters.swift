import Foundation

enum Fmt {
    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
    static func pace(_ secPer500: Double?) -> String {
        guard let p = secPer500, p > 0, p < 3600 else { return "--:--" }
        let whole = Int(p)
        let tenths = Int((p - Double(whole)) * 10)
        return String(format: "%d:%02d.%d", whole / 60, whole % 60, tenths)
    }
    static func meters(_ m: Double) -> String { String(Int(m.rounded())) }
}
