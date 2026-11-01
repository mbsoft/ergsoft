import Foundation
import HealthKit

/// Saves finished sessions to Apple Health as HKWorkout with distance + energy.
final class HealthKitManager {
    static let shared = HealthKitManager()
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        let share: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
        ]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate)]
        try await store.requestAuthorization(toShare: share, read: read)
    }

    func save(_ s: WorkoutSession) async throws -> UUID? {
        guard isAvailable, let end = s.endedAt else { return nil }
        let activity: HKWorkoutActivityType = s.kind == .bike ? .cycling : .rowing
        let config = HKWorkoutConfiguration()
        config.activityType = activity
        config.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        try await builder.beginCollection(at: s.startedAt)

        var samples: [HKSample] = []
        if s.calories > 0 {
            let q = HKQuantity(unit: .kilocalorie(), doubleValue: Double(s.calories))
            samples.append(HKQuantitySample(type: HKQuantityType(.activeEnergyBurned), quantity: q, start: s.startedAt, end: end))
        }
        if s.kind == .bike, s.totalMeters > 0 {
            let q = HKQuantity(unit: .meter(), doubleValue: s.totalMeters)
            samples.append(HKQuantitySample(type: HKQuantityType(.distanceCycling), quantity: q, start: s.startedAt, end: end))
        }
        // Heart-rate series from recorded points (only if no watch wrote it already is hard to tell; keep it simple)
        let hrType = HKQuantityType(.heartRate)
        let bpm = HKUnit.count().unitDivided(by: .minute())
        for p in s.points where p.heartRate > 0 {
            let t = s.startedAt.addingTimeInterval(p.t)
            samples.append(HKQuantitySample(type: hrType, quantity: HKQuantity(unit: bpm, doubleValue: Double(p.heartRate)), start: t, end: t))
        }
        if !samples.isEmpty { try await builder.addSamples(samples) }

        var meta: [String: Any] = [HKMetadataKeyIndoorWorkout: true]
        if s.kind == .rower { meta["ErgSoftDistanceMeters"] = s.totalMeters }  // no rowing distance type in HK
        try await builder.addMetadata(meta)

        try await builder.endCollection(at: end)
        let workout = try await builder.finishWorkout()
        return workout?.uuid
    }
}
