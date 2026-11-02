import SwiftUI
import HealthKit

struct WatchContentView: View {
    @EnvironmentObject var wm: WatchWorkoutManager

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill").foregroundStyle(.red)
                        .symbolEffect(.pulse, isActive: wm.isRunning)
                    Text(wm.heartRate.map(String.init) ?? "--")
                        .font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit()
                }
                HStack(spacing: 10) {
                    Text(wm.isRunning ? formatted(wm.elapsed) : "Ready")
                    Text(wm.phoneReachable ? "iPhone ✓" : "iPhone ✗").foregroundStyle(wm.phoneReachable ? .green : .secondary)
                }
                .font(.caption2).foregroundStyle(.secondary)
                if let e = wm.lastSendError { Text(e).font(.caption2).foregroundStyle(.red).lineLimit(2) }

                if wm.isRunning {
                    Button("Stop", role: .destructive) { wm.stop() }
                } else {
                    HStack(spacing: 6) {
                        typeButton("Row", .rowing)
                        typeButton("Bike", .cycling)
                    }
                    Button("Start") { wm.start() }.tint(.green)
                }
            }
            .padding(.horizontal, 4)
        }
        .task { await wm.requestAuthorization() }
    }

    private func typeButton(_ title: String, _ type: HKWorkoutActivityType) -> some View {
        Button(title) { wm.activity = type }
            .buttonStyle(.bordered)
            .tint(wm.activity == type ? .blue : .gray)
            .font(.caption)
    }

    private func formatted(_ t: TimeInterval) -> String {
        let s = Int(t); return String(format: "%d:%02d", s / 60, s % 60)
    }
}
