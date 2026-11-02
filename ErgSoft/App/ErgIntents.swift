import AppIntents
import HealthKit

/// "Start Erg Session": opens ErgSoft on the phone and launches the watch app into an HR workout.
struct StartErgSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Erg Session"
    static var description = IntentDescription("Opens ErgSoft and starts heart-rate streaming on your Apple Watch.")
    static var openAppWhenRun = true

    @Parameter(title: "Activity", default: .rower)
    var activity: ErgActivity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let config = HKWorkoutConfiguration()
        config.activityType = activity == .bike ? .cycling : .rowing
        config.locationType = .indoor
        do {
            try await HKHealthStore().startWatchApp(toHandle: config)
            return .result(dialog: "Starting ErgSoft on your watch.")
        } catch {
            return .result(dialog: "ErgSoft opened, but the watch didn't respond: \(error.localizedDescription)")
        }
    }
}

enum ErgActivity: String, AppEnum {
    case rower, bike
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Activity")
    static var caseDisplayRepresentations: [ErgActivity: DisplayRepresentation] = [
        .rower: "Rower", .bike: "Bike"
    ]
}

/// Makes the intent appear in Shortcuts and Siri without any setup ("Start erg session in ErgSoft").
struct ErgShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartErgSessionIntent(),
                    phrases: ["Start erg session in \(.applicationName)",
                              "Start rowing with \(.applicationName)",
                              "Start \(.applicationName)"],
                    shortTitle: "Start Erg Session",
                    systemImageName: "figure.rower")
    }
}
