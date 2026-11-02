import SwiftUI
import HealthKit
import WatchKit

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    static weak var workout: WatchWorkoutManager?

    /// Called when the iPhone launches us via HKHealthStore.startWatchApp(toHandle:).
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            guard let wm = WatchAppDelegate.workout else { return }
            wm.activity = workoutConfiguration.activityType == .cycling ? .cycling : .rowing
            wm.start()
        }
    }
}

@main
struct ErgSoftWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @StateObject private var workout = WatchWorkoutManager()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(workout)
                .onAppear { WatchAppDelegate.workout = workout }
        }
    }
}
