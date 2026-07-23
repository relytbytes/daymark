//
//  SharedCaptures.swift
//  Shared between the app and the share extension: anything filed
//  from another app's share sheet queues here in the App Group, and
//  Daymark absorbs it into the right desk on its next open.
//

import Foundation

enum SharedCaptures {
    struct Item: Codable, Identifiable {
        var id = UUID()
        var kind: String            // CaptureKind rawValue
        var title: String
        var url: String?
        var note: String?
        var created = Date()
    }

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.groupID)?
            .appendingPathComponent("daymark-shared-captures.json")
    }

    static func enqueue(_ item: Item) {
        guard let url = fileURL else { return }
        var items = load()
        items.append(item)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(items) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func load() -> [Item] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Item].self, from: data)) ?? []
    }

    static func drain() -> [Item] {
        let items = load()
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        return items
    }
}
