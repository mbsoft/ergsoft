import Foundation
import WatchConnectivity

/// iPhone side of WatchConnectivity. The ErgSoft watch app sends {"hr": Int, "ts": Double}
/// at ~1 Hz while an HKWorkoutSession is running.
@MainActor
final class WatchHRReceiver: NSObject, ObservableObject {
    @Published private(set) var heartRate: Int?
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var isPaired = false
    @Published private(set) var isWatchAppInstalled = false
    @Published private(set) var isReachable = false
    @Published private(set) var activationState: WCSessionActivationState = .notActivated
    @Published private(set) var lastError: String?

    var watchReachable: Bool { isReachable }

    var statusText: String {
        guard WCSession.isSupported() else { return "WatchConnectivity unsupported" }
        if activationState != .activated { return "Session not activated" }
        if !isPaired { return "No watch paired" }
        if !isWatchAppInstalled { return "ErgSoft not installed on watch" }
        if let hr = heartRate { return "\(hr) bpm" }
        return isReachable ? "Reachable, no HR yet (start workout on watch)" : "Watch app not reachable — open ErgSoft on the watch"
    }

    private var staleTimer: Timer?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        staleTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refreshFlags()
                if let t = self.lastUpdate, Date().timeIntervalSince(t) > 15 { self.heartRate = nil }
            }
        }
    }

    private func refreshFlags() {
        let s = WCSession.default
        activationState = s.activationState
        isPaired = s.isPaired
        isWatchAppInstalled = s.isWatchAppInstalled
        isReachable = s.isReachable
    }

    /// Ask the watch to start/stop its workout session.
    func sendCommand(_ cmd: String) {
        let s = WCSession.default
        guard s.activationState == .activated else { lastError = "session not activated"; return }
        let msg = ["cmd": cmd]
        if s.isReachable {
            s.sendMessage(msg, replyHandler: nil) { [weak self] e in
                Task { @MainActor in self?.lastError = e.localizedDescription }
            }
        } else {
            s.transferUserInfo(msg)   // delivered when the watch app next runs
        }
    }
}

extension WatchHRReceiver: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            refreshFlags()
            if let error { lastError = error.localizedDescription }
        }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) { Task { @MainActor in refreshFlags() } }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) { Task { @MainActor in refreshFlags() } }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        ingest(message)
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        ingest(message)
        replyHandler(["ok": true])
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext ctx: [String: Any]) {
        ingest(ctx)
    }
    private nonisolated func ingest(_ m: [String: Any]) {
        guard let hr = m["hr"] as? Int else { return }
        // Application context can replay a stale value on activation; ignore anything older than 15 s.
        if let ts = m["ts"] as? Double, Date().timeIntervalSince1970 - ts > 15 { return }
        Task { @MainActor in
            if let ts = m["ts"] as? Double, let last = lastUpdate, Date(timeIntervalSince1970: ts) < last { return }
            heartRate = hr; lastUpdate = Date()
        }
    }
}
