import Foundation
import WatchConnectivity

/// iPhone side of WatchConnectivity. The watch app sends {"hr": Int, "ts": Double}
/// at ~1 Hz while an HKWorkoutSession is running.
@MainActor
final class WatchHRReceiver: NSObject, ObservableObject {
    @Published private(set) var heartRate: Int?
    @Published private(set) var watchReachable = false
    @Published private(set) var lastUpdate: Date?

    private var staleTimer: Timer?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        staleTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let t = self.lastUpdate else { return }
                if Date().timeIntervalSince(t) > 8 { self.heartRate = nil }   // drop stale readings
            }
        }
    }

    /// Ask the watch to start/stop its workout session.
    func sendCommand(_ cmd: String) {
        guard WCSession.default.activationState == .activated else { return }
        let msg = ["cmd": cmd]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(msg, replyHandler: nil, errorHandler: nil)
        } else {
            WCSession.default.transferUserInfo(msg)
        }
    }
}

extension WatchHRReceiver: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in watchReachable = session.isReachable }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in watchReachable = session.isReachable }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let hr = message["hr"] as? Int else { return }
        Task { @MainActor in heartRate = hr; lastUpdate = Date() }
    }
}
