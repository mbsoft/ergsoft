import SwiftUI

/// Placeholders for third-party sync. Each will get an OAuth flow + upload when implemented.
struct IntegrationsView: View {
    @EnvironmentObject var settings: UserSettings

    private let services: [(id: String, name: String, icon: String, note: String)] = [
        ("strava",        "Strava",        "figure.run",            "Upload completed sessions as rowing/cycling activities."),
        ("trainingpeaks", "TrainingPeaks", "chart.line.uptrend.xyaxis", "Push workouts with power and HR streams."),
        ("intervals",     "Intervals.icu", "waveform.path.ecg",     "Sync sessions for fitness/fatigue tracking."),
        ("rojabo",        "Rojabo",        "calendar.badge.clock",  "Pull planned rowing workouts into ErgSoft."),
    ]

    var body: some View {
        List {
            ForEach(services, id: \.id) { s in
                HStack(spacing: 12) {
                    Image(systemName: s.icon).frame(width: 28).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.name)
                        Text(s.note).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L10n.t("connect")) {}
                        .buttonStyle(.bordered).controlSize(.small).disabled(true)
                }
            }
        } 
        .navigationTitle(L10n.t("integrations"))
        .safeAreaInset(edge: .bottom) {
            Text(L10n.t("coming_soon")).font(.caption).foregroundStyle(.secondary).padding(8)
        }
    }
}
