//
//  CadenceBridge.swift
//  Daymark
//
//  Reads the snapshot Cadence (Ty's training app) already publishes to
//  its App Group for its own widgets. Same developer team, so Daymark
//  simply joins the group — no export/import dance.
//

import Foundation

struct CadenceSnapshot: Decodable {
    let w: Double            // current weight (7-day average)
    let pct: Int             // progress through the 180 → 160 arc
    let delta: Double        // weekly rate
    let streak: Int
    let wk: Int
    let amT: String
    let amDone: Bool
    let pmT: String
    let pmDone: Bool
    let cal: Int
    let calT: Int
    let pro: Int
    let proT: Int
    let water: Int
    let waterT: Int
    let updated: Double

    var updatedAt: Date { Date(timeIntervalSince1970: updated / 1000) }

    /// Snapshots older than two days are stale enough to hide.
    var isFresh: Bool { Date().timeIntervalSince(updatedAt) < 2 * 86400 }
}

enum CadenceBridge {
    static let suite = "group.com.relytbytes.cadence"

    static func read() -> CadenceSnapshot? {
        guard let json = UserDefaults(suiteName: suite)?.string(forKey: "snapshot"),
              let data = json.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(CadenceSnapshot.self, from: data),
              snapshot.isFresh
        else { return nil }
        return snapshot
    }
}
