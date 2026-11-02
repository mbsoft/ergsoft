import Foundation
import HealthKit
import Combine

/// Fallback live HR source: watches HealthKit for new heart-rate samples. Any watch
/// workout (Apple's Workout app included) writes HR at ~1 Hz, delivered to the phone
/// with a few seconds of lag. Readings older than `maxAge` are discarded.
@MainActor
final class HealthHRObserver: ObservableObject {
    @Published private(set) var heartRate: Int?
    @Published private(set) var lastSampleDate: Date?

    private let store = HKHealthStore()
    private var query: HKAnchoredObjectQuery?
    private var anchor: HKQueryAnchor?
    private let maxAge: TimeInterval = 20
    private var staleTimer: Timer?

    func start() {
        guard HKHealthStore.isHealthDataAvailable(), query == nil else { return }
        let type = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-maxAge), end: nil)
        let q = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: anchor, limit: HKObjectQueryNoLimit) { [weak self] _, samples, _, newAnchor, _ in
            self?.handle(samples, newAnchor)
        }
        q.updateHandler = { [weak self] _, samples, _, newAnchor, _ in
            self?.handle(samples, newAnchor)
        }
        store.execute(q)
        query = q
        staleTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let d = self.lastSampleDate else { return }
                if Date().timeIntervalSince(d) > self.maxAge { self.heartRate = nil }
            }
        }
    }

    func stop() {
        if let q = query { store.stop(q) }
        query = nil
        staleTimer?.invalidate()
        heartRate = nil
    }

    private nonisolated func handle(_ samples: [HKSample]?, _ newAnchor: HKQueryAnchor?) {
        guard let latest = (samples as? [HKQuantitySample])?.max(by: { $0.endDate < $1.endDate }) else { return }
        let bpm = Int(latest.quantity.doubleValue(for: .count().unitDivided(by: .minute())).rounded())
        let when = latest.endDate
        Task { @MainActor in
            self.anchor = newAnchor
            if Date().timeIntervalSince(when) <= self.maxAge {
                self.heartRate = bpm
                self.lastSampleDate = when
            }
        }
    }
}
