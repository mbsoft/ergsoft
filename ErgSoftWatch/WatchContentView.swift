import SwiftUI
import HealthKit

struct WatchContentView: View {
    @EnvironmentObject var wm: WatchWorkoutManager

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "heart.fill").foregroundStyle(.red).font(.title2)
                .symbolEffect(.pulse, isActive: wm.isRunning)
            Text(wm.heartRate.map(String.init) ?? "--")
                .font(.system(size: 54, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(wm.isRunning ? formatted(wm.elapsed) : "Ready").font(.caption).foregroundStyle(.secondary)
            if wm.isRunning {
                Button("Stop", role: .destructive) { wm.stop() }
            } else {
                Picker("Type", selection: $wm.activity) {
                    Text("Row").tag(HKWorkoutActivityType.rowing)
                    Text("Bike").tag(HKWorkoutActivityType.cycling)
                }.pickerStyle(.navigationLink)
                Button("Start") { wm.start() }.tint(.green)
            }
        }
        .task { await wm.requestAuthorization() }
    }

    private func formatted(_ t: TimeInterval) -> String {
        let s = Int(t); return String(format: "%d:%02d", s / 60, s % 60)
    }
}
