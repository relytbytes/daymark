//
//  SatelliteService.swift
//  Daymark
//
//  ISS passes over the house — free TLE-derived predictions. Passes
//  during plausible viewing hours (dusk-ish and pre-dawn) make the
//  Sky Desk; the rest happen unwatchably overhead at noon.
//

import Foundation

struct ISSPass: Identifiable, Hashable {
    let start: Date
    let peak: Date
    let end: Date
    let appearAzimuth: Int
    let disappearAzimuth: Int
    let maxElevation: Int
    var id: Date { start }

    static func compass(_ azimuth: Int) -> String {
        let names = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                     "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        return names[Int((Double(azimuth) / 22.5).rounded()) % 16]
    }

    var line: String {
        "\(start.timeText())–\(end.timeText()) · peaks \(maxElevation)° · \(Self.compass(appearAzimuth)) → \(Self.compass(disappearAzimuth))"
    }
}

enum SatelliteService {
    static func issPasses() async throws -> [ISSPass] {
        let url = URL(string:
            "https://api.g7vrd.co.uk/v1/satellite-passes/25544/\(AppConfig.homeLatitude)/\(AppConfig.homeLongitude).json?minelevation=25&hours=72")!
        let (data, _) = try await URLSession.shared.data(from: url)

        struct Response: Decodable {
            struct Pass: Decodable {
                let start: String?
                let tca: String?
                let end: String?
                let aos_azimuth: Int?
                let los_azimuth: Int?
                let max_elevation: Double?
            }
            let passes: [Pass]?
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let calendar = Calendar.current
        return (try JSONDecoder().decode(Response.self, from: data).passes ?? [])
            .compactMap { pass -> ISSPass? in
                guard let start = pass.start.flatMap({ iso.date(from: $0) }),
                      let peak = pass.tca.flatMap({ iso.date(from: $0) }),
                      let end = pass.end.flatMap({ iso.date(from: $0) })
                else { return nil }
                return ISSPass(
                    start: start, peak: peak, end: end,
                    appearAzimuth: pass.aos_azimuth ?? 0,
                    disappearAzimuth: pass.los_azimuth ?? 0,
                    maxElevation: Int((pass.max_elevation ?? 0).rounded())
                )
            }
            .filter { pass in
                // Watchable windows: evening (19:30–23:59) or pre-dawn (04:00–06:30).
                let hour = calendar.component(.hour, from: pass.start)
                let minute = calendar.component(.minute, from: pass.start)
                let clock = hour * 60 + minute
                return (clock >= 19 * 60 + 30) || (clock >= 4 * 60 && clock <= 6 * 60 + 30)
            }
            .prefix(3)
            .map { $0 }
    }
}
