import SwiftUI
import SwiftData

@main
struct ErgSoftApp: App {
    @StateObject private var ble: BLEManager
    @StateObject private var watch: WatchHRReceiver
    @StateObject private var engine: WorkoutEngine
    @StateObject private var broadcaster: HRBroadcaster

    init() {
        let b = BLEManager()
        let w = WatchHRReceiver()
        let h = HRBroadcaster()
        let e = WorkoutEngine(ble: b, watch: w)
        e.broadcaster = h
        _ble = StateObject(wrappedValue: b)
        _watch = StateObject(wrappedValue: w)
        _broadcaster = StateObject(wrappedValue: h)
        _engine = StateObject(wrappedValue: e)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ble)
                .environmentObject(watch)
                .environmentObject(engine)
                .environmentObject(broadcaster)
                .environmentObject(UserSettings.shared)
                .task { try? await HealthKitManager.shared.requestAuthorization() }
        }
        .modelContainer(for: [WorkoutSession.self, SamplePoint.self])
    }
}
