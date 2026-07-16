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
    var updatedAt: Date
    var openLoops: Int
    var clearedPercent: Int
    var nextEventTitle: String?
    var nextEventTime: Date?
    var focusTitle: String?

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
