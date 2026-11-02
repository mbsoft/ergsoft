import Foundation
import HealthKit
import WatchConnectivity

/// Runs an HKWorkoutSession on the watch (which makes the sensor sample HR at ~1 Hz)
/// and streams each reading to the iPhone over WatchConnectivity.
@MainActor
final class WatchWorkoutManager: NSObject, ObservableObject {
    @Published private(set) var heartRate: Int?
    @Published private(set) var isRunning = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var activity: HKWorkoutActivityType = .rowing

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var timer: Timer?

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func requestAuthorization() async {
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        try? await store.requestAuthorization(toShare: share, read: read)
    }

    func start() {
        guard !isRunning else { return }
        if store.authorizationStatus(for: HKObjectType.workoutType()) != .sharingAuthorized {
            Task { await requestAuthorization(); if store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized { start() } }
            return
        }
        let config = HKWorkoutConfiguration()
        config.activityType = activity
        config.locationType = .indoor
        do {
            let s = try HKWorkoutSession(healthStore: store, configuration: config)
            let b = s.associatedWorkoutBuilder()
            b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            s.delegate = self
            b.delegate = self
            session = s; builder = b
            let now = Date()
            s.startActivity(with: now)
            b.beginCollection(withStart: now) { _, _ in }
            isRunning = true
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.elapsed = self?.builder?.elapsedTime ?? 0 }
            }
        } catch {
            print("workout start failed: \(error)")
        }
    }

    func stop() {
        guard isRunning else { return }
        timer?.invalidate()
        session?.end()
        builder?.endCollection(withEnd: Date()) { [weak self] _, _ in
            self?.builder?.finishWorkout { _, _ in }
        }
        isRunning = false
        heartRate = nil
    }

    @Published private(set) var phoneReachable = false
    @Published private(set) var lastSendError: String?

    private var consecutiveFailures = 0

    private func send(hr: Int) {
        let s = WCSession.default
        guard s.activationState == .activated else { return }
        phoneReachable = s.isReachable
        let payload: [String: Any] = ["hr": hr, "ts": Date().timeIntervalSince1970]
        // Channel 1: application context — latest-value, queued, never errors on reachability.
        // The phone gets it whenever it next runs, so HR survives the phone app being backgrounded.
        try? s.updateApplicationContext(payload)
        // Channel 2: live message when the phone app is in the foreground (lowest latency).
        guard s.isReachable else { return }
        s.sendMessage(payload, replyHandler: { [weak self] _ in
            Task { @MainActor in self?.consecutiveFailures = 0; self?.lastSendError = nil }
        }, errorHandler: { [weak self] e in
            Task { @MainActor in
                guard let self else { return }
                self.consecutiveFailures += 1
                // Only surface a persistent problem, not a single dropped packet.
                self.lastSendError = self.consecutiveFailures >= 5 ? "iPhone not reachable — open ErgSoft on the phone" : nil
            }
        })
    }
}

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ s: HKWorkoutSession, didChangeTo to: HKWorkoutSessionState, from: HKWorkoutSessionState, date: Date) {}
    nonisolated func workoutSession(_ s: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in isRunning = false }
    }
}

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ b: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ b: HKLiveWorkoutBuilder, didCollectDataOf types: Set<HKSampleType>) {
        guard types.contains(HKQuantityType(.heartRate)),
              let stats = b.statistics(for: HKQuantityType(.heartRate)),
              let q = stats.mostRecentQuantity() else { return }
        let bpm = Int(q.doubleValue(for: .count().unitDivided(by: .minute())).rounded())
        Task { @MainActor in
            heartRate = bpm
            send(hr: bpm)
        }
    }
}

extension WatchWorkoutManager: WCSessionDelegate {
    nonisolated func session(_ s: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in phoneReachable = s.isReachable }
    }
    nonisolated func sessionReachabilityDidChange(_ s: WCSession) {
        Task { @MainActor in phoneReachable = s.isReachable }
    }
    nonisolated func session(_ s: WCSession, didReceiveMessage message: [String: Any]) { handle(message) }
    nonisolated func session(_ s: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { handle(userInfo) }
    private nonisolated func handle(_ m: [String: Any]) {
        guard let cmd = m["cmd"] as? String else { return }
        Task { @MainActor in
            switch cmd {
            case "start": start()
            case "stop": stop()
            default: break
            }
        }
    }
}
