import UIKit

enum Haptics {
    static func intervalChange() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func workoutDone()    { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}
