//
//  GameActivityAttributes.swift
//  Shared between the app (starts/updates) and the widget extension
//  (renders): the live game on the Lock Screen and Dynamic Island.
//

import Foundation
#if canImport(ActivityKit)
import ActivityKit

struct GameActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var awayScore: Int
        var homeScore: Int
        var detail: String      // "Bot 7 · 2 out"
    }

    var awayAbbr: String
    var homeAbbr: String
}
#endif
