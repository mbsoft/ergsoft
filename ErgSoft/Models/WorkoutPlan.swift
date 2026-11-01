import Foundation

/// One step of an interval workout.
struct Interval: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case work, rest }
    enum Goal: Codable, Hashable {
        case time(seconds: Int)
        case distance(meters: Int)
    }
    var id = UUID()
    var kind: Kind
    var goal: Goal
    var targetPaceSecondsPer500m: Double?   // optional pace target (rower)
    var targetWatts: Int?                   // optional power target

    var label: String {
        switch goal {
        case .time(let s): return "\(kind == .work ? "Work" : "Rest") \(s / 60):\(String(format: "%02d", s % 60))"
        case .distance(let m): return "\(kind == .work ? "Work" : "Rest") \(m)m"
        }
    }
}

struct WorkoutPlan: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var intervals: [Interval]

    static let justRow = WorkoutPlan(name: "Just Row", intervals: [])

    static let presets: [WorkoutPlan] = [
        justRow,
        WorkoutPlan(name: "2000m", intervals: [Interval(kind: .work, goal: .distance(meters: 2000))]),
        WorkoutPlan(name: "20:00 steady", intervals: [Interval(kind: .work, goal: .time(seconds: 1200))]),
        WorkoutPlan(name: "4 × 500m / 2:00 rest", intervals: (0..<4).flatMap { i in
            [Interval(kind: .work, goal: .distance(meters: 500))] +
            (i < 3 ? [Interval(kind: .rest, goal: .time(seconds: 120))] : [])
        }),
        WorkoutPlan(name: "Tabata 8 × 20/10", intervals: (0..<8).flatMap { i in
            [Interval(kind: .work, goal: .time(seconds: 20))] +
            (i < 7 ? [Interval(kind: .rest, goal: .time(seconds: 10))] : [])
        }),
    ]
}
