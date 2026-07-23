//
//  AlertsService.swift
//  Daymark
//
//  National Weather Service active alerts for the home point — free,
//  no key, county-accurate. New alerts also arrive as notifications.
//

import Foundation

struct WeatherAlert: Identifiable, Hashable {
    let id: String
    let event: String        // "Heat Advisory"
    let headline: String
    let severity: String     // Minor / Moderate / Severe / Extreme
    let ends: Date?

    var isUrgent: Bool { severity == "Severe" || severity == "Extreme" }
}

enum AlertsService {
    static func active() async throws -> [WeatherAlert] {
        var components = URLComponents(string: "https://api.weather.gov/alerts/active")!
        components.queryItems = [
            URLQueryItem(name: "point", value: "\(AppConfig.homeLatitude),\(AppConfig.homeLongitude)"),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.setValue("daymark-personal-app", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)

        struct Response: Decodable {
            struct Feature: Decodable {
                struct Properties: Decodable {
                    let id: String?
                    let event: String?
                    let headline: String?
                    let severity: String?
                    let ends: String?
                }
                let properties: Properties
            }
            let features: [Feature]
        }
        let iso = ISO8601DateFormatter()
        return try JSONDecoder().decode(Response.self, from: data).features.compactMap { feature in
            let p = feature.properties
            guard let event = p.event else { return nil }
            return WeatherAlert(
                id: p.id ?? UUID().uuidString,
                event: event,
                headline: p.headline ?? event,
                severity: p.severity ?? "Unknown",
                ends: p.ends.flatMap { iso.date(from: $0) }
            )
        }
    }
}
