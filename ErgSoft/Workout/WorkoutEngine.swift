import Foundation
import Combine
import SwiftData

/// Drives a workout: consumes erg samples + heart rate, advances intervals,
/// keeps a 1 Hz time series, and finalises a WorkoutSession.
@MainActor
final class WorkoutEngine: ObservableObject {
    enum State { case idle, running, paused, finished }

    @Published private(set) var state: State = .idle
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var meters: Double = 0
    @Published private(set) var strokes: Int = 0
    @Published private(set) var calories: Int = 0
    @Published private(set) var heartRate: Int?
    @Published private(set) var intervalIndex = 0
    @Published private(set) var intervalElapsed: Double = 0
    @Published private(set) var intervalMeters: Double = 0
    @Published private(set) var plan: WorkoutPlan = .justRow
    @Published private(set) var current = ErgSample()
    /// Average of the last 10 s of pace samples (s/500m), nil until enough data.
    @Published private(set) var rollingPace10s: Double?
    private var paceWindow: [(Date, Double)] = []

    private let ble: BLEManager
    private let watch: WatchHRReceiver
    let healthHR = HealthHRObserver()
    weak var broadcaster: HRBroadcaster?
    private var hrTicker: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var ticker: AnyCancellable?
    private var lastTick = Date()
    private var intervalStartMeters: Double = 0
    private var points: [SamplePoint] = []
    private var lastRecordedSecond = -1
    private var wattSum = 0, wattN = 0, hrSum = 0, hrN = 0, hrMax = 0
    private var baseMeters: Double?     // machine odometer at start, if it reports absolute distance
    private var baseStrokes: Int?

    init(ble: BLEManager, watch: WatchHRReceiver) {
        self.ble = ble
        self.watch = watch
        ble.samples.sink { [weak self] in self?.ingest($0) }.store(in: &cancellables)
        // Keep HR current even outside a workout so the console broadcast works while warming up.
        hrTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self, self.state != .running else { return }
            self.heartRate = self.bestHeartRate()
            self.broadcaster?.update(heartRate: self.heartRate)
        }
    }

    var currentInterval: Interval? { plan.intervals.indices.contains(intervalIndex) ? plan.intervals[intervalIndex] : nil }

    /// Progress 0…1 through the current interval, nil for "just row".
    var intervalProgress: Double? {
        guard let iv = currentInterval else { return nil }
        switch iv.goal {
        case .time(let s): return min(1, intervalElapsed / Double(s))
        case .distance(let m): return min(1, intervalMeters / Double(m))
        }
    }

    var intervalRemainingText: String {
        guard let iv = currentInterval else { return "" }
        switch iv.goal {
        case .time(let s): return Fmt.clock(Double(s) - intervalElapsed)
        case .distance(let m): return "\(max(0, m - Int(intervalMeters)))m"
        }
    }

    // MARK: Control

    func start(plan: WorkoutPlan) {
        reset()
        self.plan = plan
        state = .running
        lastTick = Date()
        ble.startMachine()
        healthHR.start()
        ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func pause() { guard state == .running else { return }; state = .paused; ble.stopMachine() }
    func resume() { guard state == .paused else { return }; state = .running; lastTick = Date(); ble.startMachine() }

    func finish(into context: ModelContext, machineName: String, kind: ErgKind) -> WorkoutSession {
        state = .finished
        ticker?.cancel()
        healthHR.stop()
        ble.stopMachine()
        let s = WorkoutSession(startedAt: Date().addingTimeInterval(-elapsed), machineName: machineName, kind: kind, planName: plan.name)
        s.endedAt = Date()
        s.totalMeters = meters
        s.durationSeconds = elapsed
        s.strokes = strokes
        s.calories = calories
        s.averageWatts = wattN > 0 ? Double(wattSum) / Double(wattN) : 0
        s.averageHeartRate = hrN > 0 ? Double(hrSum) / Double(hrN) : 0
        s.maxHeartRate = hrMax
        s.points = points
        context.insert(s)
        try? context.save()
        return s
    }

    func reset() {
        ticker?.cancel()
        state = .idle
        elapsed = 0; meters = 0; strokes = 0; calories = 0
        intervalIndex = 0; intervalElapsed = 0; intervalMeters = 0; intervalStartMeters = 0
        points = []; lastRecordedSecond = -1
        wattSum = 0; wattN = 0; hrSum = 0; hrN = 0; hrMax = 0
        baseMeters = nil; baseStrokes = nil
    }

    // MARK: Internals

    /// Heart rate priority: watch app > strap > HealthKit (any watch workout) > machine
    private func bestHeartRate() -> Int? {
        watch.heartRate ?? ble.strapHeartRate ?? healthHR.heartRate ?? current.heartRate
    }

    private func ingest(_ s: ErgSample) {
        current = s
        if let p = s.paceSecondsPer500m, p > 0 {
            let now = Date()
            paceWindow.append((now, p))
            paceWindow.removeAll { now.timeIntervalSince($0.0) > 10 }
            rollingPace10s = paceWindow.map(\.1).reduce(0, +) / Double(paceWindow.count)
        }
        guard state == .running else { return }
        if let d = s.distanceMeters {
            if baseMeters == nil { baseMeters = d }
            meters = max(meters, d - (baseMeters ?? 0))
        }
        if let c = s.strokeCount {
            if baseStrokes == nil { baseStrokes = c }
            strokes = max(strokes, c - (baseStrokes ?? 0))
        }
        if let kcal = s.caloriesTotal { calories = kcal }
        intervalMeters = meters - intervalStartMeters
    }

    private func tick() {
        guard state == .running else { return }
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        elapsed += dt
        intervalElapsed += dt

        heartRate = bestHeartRate()
        broadcaster?.update(heartRate: heartRate)

        // 1 Hz recording
        let sec = Int(elapsed)
        if sec != lastRecordedSecond {
            lastRecordedSecond = sec
            let w = current.powerWatts ?? 0
            if w > 0 { wattSum += w; wattN += 1 }
            if let hr = heartRate, hr > 0 { hrSum += hr; hrN += 1; hrMax = max(hrMax, hr) }
            points.append(SamplePoint(t: elapsed, meters: meters, watts: w,
                                      pace: current.paceSecondsPer500m ?? 0,
                                      strokeRate: current.strokeRate ?? 0,
                                      heartRate: heartRate ?? 0))
        }

        // Interval advancement
        if let iv = currentInterval {
            let done: Bool
            switch iv.goal {
            case .time(let s): done = intervalElapsed >= Double(s)
            case .distance(let m): done = intervalMeters >= Double(m)
            }
            if done {
                if intervalIndex + 1 < plan.intervals.count {
                    intervalIndex += 1
                    intervalElapsed = 0
                    intervalStartMeters = meters
                    intervalMeters = 0
                    Haptics.intervalChange()
                } else {
                    state = .paused   // plan complete; user taps Finish
                    Haptics.workoutDone()
                }
            }
        }
    }
}
