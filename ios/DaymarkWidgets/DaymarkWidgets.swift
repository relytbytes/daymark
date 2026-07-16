//
//  DaymarkWidgets.swift
//  DaymarkWidgets
//
//  The At-a-Glance home screen widget and the focus-timer Live Activity.
//  The widget is deliberately self-contained: it fetches Durham weather
//  and today's D-backs game straight from the same public APIs the app
//  uses, so no App Group or shared state is required.
//

import WidgetKit
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif

// MARK: - Palette (the Daily × Scoreboard system, condensed)

private enum WPalette {
    static let paper = Color(red: 0.992, green: 0.992, blue: 0.988)
    static let ink = Color(red: 0.078, green: 0.078, blue: 0.070)
    static let muted = Color(red: 0.459, green: 0.447, blue: 0.424)
    static let red = Color(red: 0.784, green: 0.063, blue: 0.180)
}

// MARK: - At a Glance widget

struct GlanceEntry: TimelineEntry {
    let date: Date
    var tempF: Int?
    var condition: String = "—"
    var sunset: String = "—"
    var gameLine: String = "No game today"
}

struct GlanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlanceEntry {
        GlanceEntry(date: Date(), tempF: 85, condition: "Clear", sunset: "8:31 PM", gameLine: "DBacks 9:40 PM")
    }

    func getSnapshot(in context: Context, completion: @escaping (GlanceEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceEntry>) -> Void) {
        Task {
            var entry = GlanceEntry(date: Date())
            async let weather = fetchWeather()
            async let game = fetchGame()
            if let weather = await weather {
                entry.tempF = weather.tempF
                entry.condition = weather.condition
                entry.sunset = weather.sunset
            }
            if let game = await game { entry.gameLine = game }
            let refresh = Calendar.current.date(byAdding: .minute, value: 45, to: Date())!
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }

    private struct WeatherBits {
        var tempF: Int?
        var condition = "—"
        var sunset = "—"
    }

    private func fetchWeather() async -> WeatherBits? {
        struct Response: Decodable {
            struct Current: Decodable {
                let temperature_2m: Double
                let weather_code: Int
            }
            struct Daily: Decodable { let sunset: [String] }
            let current: Current
            let daily: Daily
        }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: "35.9940"),
            URLQueryItem(name: "longitude", value: "-78.8986"),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "sunset"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "timezone", value: "America/New_York"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ]
        guard let (data, _) = try? await URLSession.shared.data(from: components.url!),
              let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        var bits = WeatherBits()
        bits.tempF = Int(response.current.temperature_2m.rounded())
        bits.condition = conditionText(response.current.weather_code)
        if let sunsetRaw = response.daily.sunset.first {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
            formatter.timeZone = TimeZone(identifier: "America/New_York")
            if let date = formatter.date(from: sunsetRaw) {
                let out = DateFormatter()
                out.dateFormat = "h:mm a"
                bits.sunset = out.string(from: date)
            }
        }
        return bits
    }

    private func fetchGame() async -> String? {
        struct Schedule: Decodable {
            struct DateEntry: Decodable { let games: [Game] }
            struct Game: Decodable {
                struct Status: Decodable { let abstractGameState: String? }
                struct Teams: Decodable {
                    struct Side: Decodable {
                        struct Team: Decodable { let abbreviation: String? }
                        let team: Team?
                        let score: Int?
                    }
                    let away: Side?
                    let home: Side?
                }
                let gameDate: String?
                let status: Status?
                let teams: Teams?
            }
            let dates: [DateEntry]
        }
        var components = URLComponents(string: "https://statsapi.mlb.com/api/v1/schedule")!
        components.queryItems = [
            URLQueryItem(name: "sportId", value: "1"),
            URLQueryItem(name: "teamId", value: "109"),
        ]
        guard let (data, _) = try? await URLSession.shared.data(from: components.url!),
              let schedule = try? JSONDecoder().decode(Schedule.self, from: data),
              let game = schedule.dates.first?.games.first else { return nil }

        let away = game.teams?.away?.team?.abbreviation ?? "AWY"
        let home = game.teams?.home?.team?.abbreviation ?? "HOM"
        switch game.status?.abstractGameState {
        case "Live":
            return "\(away) \(game.teams?.away?.score ?? 0)–\(game.teams?.home?.score ?? 0) \(home) · LIVE"
        case "Final":
            return "\(away) \(game.teams?.away?.score ?? 0)–\(game.teams?.home?.score ?? 0) \(home) · Final"
        default:
            let formatter = ISO8601DateFormatter()
            if let raw = game.gameDate, let date = formatter.date(from: raw) {
                let out = DateFormatter()
                out.dateFormat = "h:mm a"
                return "\(away) at \(home) · \(out.string(from: date))"
            }
            return "\(away) at \(home)"
        }
    }

    private func conditionText(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1...3: return "Partly cloudy"
        case 45, 48: return "Fog"
        case 51...67: return "Rain"
        case 71...77: return "Snow"
        case 80...82: return "Showers"
        case 95...99: return "Storms"
        default: return "—"
        }
    }
}

struct GlanceWidgetView: View {
    var entry: GlanceEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DAYMARK")
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(WPalette.red)
                Spacer()
                Text(entry.date, style: .time)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(WPalette.muted)
            }
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text(entry.tempF.map { "\($0)°" } ?? "—")
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .foregroundStyle(WPalette.ink)
                Text(entry.condition)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WPalette.muted)
                    .lineLimit(1)
            }
            Rectangle().fill(WPalette.ink.opacity(0.14)).frame(height: 1)
            row("SUNSET", entry.sunset)
            row("DBACKS", entry.gameLine)
        }
        .containerBackground(WPalette.paper, for: .widget)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 7, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(WPalette.muted)
                .frame(width: 40, alignment: .leading)
            Text(value)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
    }
}

struct AtAGlanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DaymarkAtAGlance", provider: GlanceProvider()) { entry in
            GlanceWidgetView(entry: entry)
        }
        .configurationDisplayName("At a Glance")
        .description("Durham weather, sunset, and today's D-backs game.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Focus Live Activity

#if canImport(ActivityKit)
struct FocusActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            // Lock Screen presentation
            HStack(spacing: 12) {
                Circle().fill(WPalette.red).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("FOCUS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.2)
                        .foregroundStyle(WPalette.red)
                    Text(context.state.taskTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WPalette.ink)
                        .lineLimit(1)
                }
                Spacer()
                Text(timerInterval: Date()...context.state.endsAt, countsDown: true)
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(WPalette.ink)
                    .frame(width: 76, alignment: .trailing)
            }
            .padding(14)
            .activityBackgroundTint(WPalette.paper)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("FOCUS")
                        .font(.system(size: 10, weight: .heavy)).tracking(1.2)
                        .foregroundStyle(WPalette.red)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date()...context.state.endsAt, countsDown: true)
                        .font(.system(size: 18, weight: .bold))
                        .monospacedDigit()
                        .frame(width: 64, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.taskTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
            } compactLeading: {
                Circle().fill(WPalette.red).frame(width: 8, height: 8)
            } compactTrailing: {
                Text(timerInterval: Date()...context.state.endsAt, countsDown: true)
                    .monospacedDigit()
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 44)
            } minimal: {
                Circle().fill(WPalette.red).frame(width: 8, height: 8)
            }
        }
    }
}
#endif

// MARK: - Bundle

@main
struct DaymarkWidgetBundle: WidgetBundle {
    var body: some Widget {
        AtAGlanceWidget()
        #if canImport(ActivityKit)
        FocusActivityWidget()
        #endif
    }
}
