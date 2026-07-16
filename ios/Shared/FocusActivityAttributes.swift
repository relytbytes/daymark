//
//  FocusActivityAttributes.swift
//  Daymark (app + widget extension)
//
//  The contract between the app (which starts/ends the focus Live
//  Activity) and the widget extension (which renders it in the
//  Dynamic Island and on the Lock Screen).
//

import Foundation

#if canImport(ActivityKit)
import ActivityKit

struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endsAt: Date
        var taskTitle: String
    }

    var startedAt: Date
}
#endif
