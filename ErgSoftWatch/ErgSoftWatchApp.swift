import SwiftUI

@main
struct ErgSoftWatchApp: App {
    @StateObject private var workout = WatchWorkoutManager()

    var body: some Scene {
        WindowGroup {
            WatchContentView().environmentObject(workout)
        }
    }
}
