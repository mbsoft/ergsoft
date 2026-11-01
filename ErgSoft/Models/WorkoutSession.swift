import Foundation
import SwiftData

/// A completed (or in-progress) workout persisted locally.
@Model
final class WorkoutSession {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var machineName: String
    var machineKindRaw: String
    var planName: String
    var totalMeters: Double
    var durationSeconds: Double
    var averageWatts: Double
    var averageHeartRate: Double
    var maxHeartRate: Int
    var strokes: Int
    var calories: Int
    var healthKitUUID: UUID?
    @Relationship(deleteRule: .cascade) var points: [SamplePoint]

    init(startedAt: Date, machineName: String, kind: ErgKind, planName: String) {
        id = UUID()
        self.startedAt = startedAt
        self.machineName = machineName
        machineKindRaw = kind.rawValue
        self.planName = planName
        totalMeters = 0; durationSeconds = 0; averageWatts = 0; averageHeartRate = 0
        maxHeartRate = 0; strokes = 0; calories = 0
        points = []
    }

    var kind: ErgKind { ErgKind(rawValue: machineKindRaw) ?? .unknown }
    var averagePaceSecondsPer500m: Double? {
        totalMeters > 0 ? durationSeconds / (totalMeters / 500.0) : nil
    }
}

/// One-second-ish time series point.
@Model
final class SamplePoint {
    var t: Double           // seconds since start
    var meters: Double
    var watts: Int
    var pace: Double        // s/500m, 0 if unknown
    var strokeRate: Double
    var heartRate: Int
    var session: WorkoutSession?

    init(t: Double, meters: Double, watts: Int, pace: Double, strokeRate: Double, heartRate: Int) {
        self.t = t; self.meters = meters; self.watts = watts; self.pace = pace
        self.strokeRate = strokeRate; self.heartRate = heartRate
    }
}
