import SwiftUI
import SwiftData

@main
struct ErgSoftApp: App {
    @StateObject private var ble: BLEManager
    @StateObject private var watch: WatchHRReceiver
    @StateObject private var engine: WorkoutEngine

    init() {
        let b = BLEManager()
        let w = WatchHRReceiver()
        _ble = StateObject(wrappedValue: b)
        _watch = StateObject(wrappedValue: w)
        _engine = StateObject(wrappedValue: WorkoutEngine(ble: b, watch: w))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ble)
                .environmentObject(watch)
                .environmentObject(engine)
                .task { try? await HealthKitManager.shared.requestAuthorization() }
        }
        .modelContainer(for: [WorkoutSession.self, SamplePoint.self])
    }
}
