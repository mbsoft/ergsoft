import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            WorkoutView()
                .tabItem { Label("Workout", systemImage: "figure.rower") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            SettingsView()
                .tabItem { Label("Devices", systemImage: "antenna.radiowaves.left.and.right") }
        }
    }
}
