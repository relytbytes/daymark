//
//  WatchBridge.swift
//  Daymark
//
//  The phone's side of the wrist edition: pushes the day's numbers
//  as application context, absorbs check-offs sent back from the
//  watch.
//

import Foundation
import WatchConnectivity

final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()
    var onToggle: ((String) -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func push(_ context: [String: Any]) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled
        else { return }
        try? WCSession.default.updateApplicationContext(context)
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let id = userInfo["toggle"] as? String else { return }
        Task { @MainActor in
            WatchBridge.shared.onToggle?(id)
        }
    }
}
