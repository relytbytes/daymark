//
//  SharedSnapshot.swift
//  Daymark
//
//  The app's side of the App Group: a small JSON snapshot the widget
//  extension reads so the home screen can show personal numbers (open
//  loops, cleared %, next event, the focus title) without the widget
//  touching any account or the persisted store directly.
//

import Foundation

struct WidgetSnapshot: Codable {
    struct Event: Codable, Hashable {
        var title: String
        var start: Date
        var end: Date
        var isTomorrow: Bool
    }

    struct Essential: Codable, Hashable, Identifiable {
        var id: String
        var kicker: String
        var title: String
        var done: Bool
    }

    var updatedAt: Date
    var openLoops: Int
    var clearedPercent: Int
    var nextEventTitle: String?
    var nextEventTime: Date?
    var focusTitle: String?
    var events: [Event] = []
    var essentials: [Essential]?

    static let groupID = "group.com.relytbytes.daymark"
    static let filename = "daymark-widget.json"

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent(filename)
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func read() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data) else { return nil }
        // Stale personal data is worse than none.
        guard Date().timeIntervalSince(snapshot.updatedAt) < 18 * 3600 else { return nil }
        return snapshot
    }
}

/// Check-offs made from the widget, queued for the app to absorb on
/// its next open. Desired-state map (id -> done) so repeat taps stay
/// idempotent; stamped so yesterday's taps can't mark today's tasks.
enum WidgetActions {
    struct Pending: Codable {
        var written: Date
        var tasks: [String: Bool]
    }

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.groupID)?
            .appendingPathComponent("daymark-widget-actions.json")
    }

    static func record(_ id: String, done: Bool) {
        guard let url = fileURL else { return }
        var pending = load() ?? Pending(written: Date(), tasks: [:])
        if !Calendar.current.isDateInToday(pending.written) { pending.tasks = [:] }
        pending.written = Date()
        pending.tasks[id] = done
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(pending) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func load() -> Pending? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Pending.self, from: data)
    }

    /// Hand today's queued check-offs to the caller, then clear the file.
    static func drain() -> [String: Bool] {
        guard let pending = load() else { return [:] }
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        guard Calendar.current.isDateInToday(pending.written) else { return [:] }
        return pending.tasks
    }
}
