//
//  DaymarkWidgets.swift
//  DaymarkWidgets
//
//  The Daymark widget suite, all self-contained (public APIs, no App
//  Group): the At-a-Glance home screen widget (small + medium), Lock
//  Screen accessories, and the focus-timer Live Activity. Timelines
//  refresh every 45 minutes, tightening to 10 when a game is live.
//

import WidgetKit
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif

// MARK: - Palette (the Daily × Scoreboard system, condensed)

private enum WPalette {
    static let paper = Color(red: 0.992, green: 0.992, blue: 0.988)
    static let wash = Color(red: 0.973, green: 0.969, blue: 0.961)
    static let ink = Color(red: 0.078, green: 0.078, blue: 0.070)
    static let muted = Color(red: 0.459, green: 0.447, blue: 0.424)
    static let subtle = Color(red: 0.541, green: 0.529, blue: 0.498)
    static let red = Color(red: 0.784, green: 0.063, blue: 0.180)
    static let gold = Color(red: 0.725, green: 0.541, blue: 0.122)
    static let blue = Color(red: 0.114, green: 0.435, blue: 0.878)
    static let line = Color(red: 0.078, green: 0.078, blue: 0.070).opacity(0.14)
    static let up = Color(red: 0.055, green: 0.624, blue: 0.431)
    static let down = Color(red: 0.863, green: 0.149, blue: 0.149)
}

// MARK: - Entry

struct GameLine: Hashable {
    var label: String       // "DBACKS" / "BULLS"
    var text: String        // "ARI 4–2 SD · Bot 7" / "at Padres · 9:40 PM"
    var isLive = false
}

struct MarketLine: Hashable {
    var label: String       // "S&P"
    var price: Double
    var changePct: Double
}

struct GlanceEntry: TimelineEntry {
    let date: Date
    var tempF: Int?
    var feels: Int?
    var condition = "—"
    var symbol = "sun.max.fill"
    var high: Int?
    var low: Int?
    var rainPct: Int?
    var sunrise = "—"
    var sunset = "—"
    var sunsetDate: Date?
    var moonSymbol = "moon.fill"
    var moonName = ""
    var games: [GameLine] = []
    var markets: [MarketLine] = []
    var desk: WidgetSnapshot?

    var isEvening: Bool {
        guard let sunsetDate else { return false }
        return date > sunsetDate.addingTimeInterval(-3600)
    }
}

// MARK: - Provider

struct GlanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlanceEntry {
        GlanceEntry(date: Date(), tempF: 85, feels: 92, condition: "Clear", high: 96, low: 74, rainPct: 20,
                    sunset: "8:31 PM",
                    games: [GameLine(label: "DBACKS", text: "at Padres · 9:40 PM"),
                            GameLine(label: "BULLS", text: "DUR 6–3 MEM · Bot 7", isLive: true)])
    }

    func getSnapshot(in context: Context, completion: @escaping (GlanceEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceEntry>) -> Void) {
        Task {
            var entry = GlanceEntry(date: Date())
            async let weather = fetchWeather()
            async let dbacks = fetchGame(teamID: 109, sportID: 1, label: "DBACKS")
            async let bulls = fetchGame(teamID: 234, sportID: 11, label: "BULLS")
            async let markets = fetchMarkets()

            if let weather = await weather {
                entry.tempF = weather.tempF
                entry.feels = weather.feels
                entry.condition = weather.condition
                entry.symbol = weather.symbol
                entry.high = weather.high
                entry.low = weather.low
                entry.rainPct = weather.rainPct
                entry.sunrise = weather.sunrise
                entry.sunset = weather.sunset
                entry.sunsetDate = weather.sunsetDate
            }
            entry.games = [await dbacks, await bulls].compactMap { $0 }
            entry.markets = await markets
            entry.desk = WidgetSnapshot.read()
            let (moonSymbol, moonName) = Moon.phase(on: Date())
            entry.moonSymbol = moonSymbol
            entry.moonName = moonName

            let anyLive = entry.games.contains(where: \.isLive)
            let refresh = Calendar.current.date(byAdding: .minute, value: anyLive ? 10 : 45, to: Date())!
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }

    // MARK: Weather

    private struct WeatherBits {
        var tempF: Int?
        var feels: Int?
        var condition = "—"
        var symbol = "sun.max.fill"
        var high: Int?
        var low: Int?
        var rainPct: Int?
        var sunrise = "—"
        var sunset = "—"
        var sunsetDate: Date?
    }

    private func fetchWeather() async -> WeatherBits? {
        struct Response: Decodable {
            struct Current: Decodable {
                let temperature_2m: Double
                let apparent_temperature: Double?
                let weather_code: Int
            }
            struct Daily: Decodable {
                let sunrise: [String]?
                let sunset: [String]
                let temperature_2m_max: [Double]?
                let temperature_2m_min: [Double]?
                let precipitation_probability_max: [Int]?
            }
            let current: Current
            let daily: Daily
        }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: "35.9940"),
            URLQueryItem(name: "longitude", value: "-78.8986"),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code"),
            URLQueryItem(name: "daily", value: "sunrise,sunset,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "timezone", value: "America/New_York"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ]
        guard let (data, _) = try? await URLSession.shared.data(from: components.url!),
              let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        var bits = WeatherBits()
        bits.tempF = Int(response.current.temperature_2m.rounded())
        bits.feels = response.current.apparent_temperature.map { Int($0.rounded()) }
        (bits.condition, bits.symbol) = Self.condition(response.current.weather_code)
        bits.high = response.daily.temperature_2m_max?.first.map { Int($0.rounded()) }
        bits.low = response.daily.temperature_2m_min?.first.map { Int($0.rounded()) }
        bits.rainPct = response.daily.precipitation_probability_max?.first
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        let out = DateFormatter()
        out.dateFormat = "h:mm a"
        if let sunsetRaw = response.daily.sunset.first,
           let date = formatter.date(from: sunsetRaw) {
            bits.sunsetDate = date
            bits.sunset = out.string(from: date)
        }
        if let sunriseRaw = response.daily.sunrise?.first,
           let date = formatter.date(from: sunriseRaw) {
            bits.sunrise = out.string(from: date)
        }
        return bits
    }

    // MARK: Markets

    /// The index strip, straight from Yahoo's chart API (same source as
    /// the app's markets desk).
    private func fetchMarkets() async -> [MarketLine] {
        let watch: [(ticker: String, label: String)] = [
            ("^GSPC", "S&P"), ("^DJI", "DOW"), ("^IXIC", "NDQ"),
        ]
        var lines: [MarketLine] = []
        await withTaskGroup(of: MarketLine?.self) { group in
            for item in watch {
                group.addTask { await Self.marketLine(ticker: item.ticker, label: item.label) }
            }
            for await line in group {
                if let line { lines.append(line) }
            }
        }
        let order = Dictionary(uniqueKeysWithValues: watch.enumerated().map { ($1.label, $0) })
        return lines.sorted { (order[$0.label] ?? 9) < (order[$1.label] ?? 9) }
    }

    private static func marketLine(ticker: String, label: String) async -> MarketLine? {
        let encoded = ticker.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ticker
        guard let url = URL(string:
            "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?range=5d&interval=1d")
        else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)",
                         forHTTPHeaderField: "User-Agent")
        struct Chart: Decodable {
            struct Wrapper: Decodable { let result: [Result]? }
            struct Result: Decodable {
                struct Indicators: Decodable {
                    struct Quote: Decodable { let close: [Double?]? }
                    let quote: [Quote]?
                }
                let indicators: Indicators?
            }
            let chart: Wrapper
        }
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let parsed = try? JSONDecoder().decode(Chart.self, from: data),
              let closes = parsed.chart.result?.first?.indicators?.quote?.first?.close?
                  .compactMap({ $0 }),
              closes.count >= 2,
              let last = closes.last
        else { return nil }
        let previous = closes[closes.count - 2]
        let pct = previous != 0 ? (last - previous) / previous * 100 : 0
        return MarketLine(label: label, price: last, changePct: pct)
    }

    private static func condition(_ code: Int) -> (String, String) {
        switch code {
        case 0: return ("Clear", "sun.max.fill")
        case 1...2: return ("Partly cloudy", "cloud.sun.fill")
        case 3: return ("Overcast", "cloud.fill")
        case 45, 48: return ("Fog", "cloud.fog.fill")
        case 51...67: return ("Rain", "cloud.rain.fill")
        case 71...77: return ("Snow", "cloud.snow.fill")
        case 80...82: return ("Showers", "cloud.heavyrain.fill")
        case 95...99: return ("Storms", "cloud.bolt.rain.fill")
        default: return ("—", "sun.max.fill")
        }
    }

    // MARK: Games

    private func fetchGame(teamID: Int, sportID: Int, label: String) async -> GameLine? {
        struct Schedule: Decodable {
            struct DateEntry: Decodable { let games: [Game] }
            struct Game: Decodable {
                struct Status: Decodable { let abstractGameState: String? }
                struct Linescore: Decodable {
                    let currentInning: Int?
                    let inningState: String?
                }
                struct Teams: Decodable {
                    struct Side: Decodable {
                        struct Team: Decodable {
                            let abbreviation: String?
                            let teamName: String?
                        }
                        let team: Team?
                        let score: Int?
                    }
                    let away: Side?
                    let home: Side?
                }
                let gameDate: String?
                let status: Status?
                let linescore: Linescore?
                let teams: Teams?
            }
            let dates: [DateEntry]
        }
        var components = URLComponents(string: "https://statsapi.mlb.com/api/v1/schedule")!
        components.queryItems = [
            URLQueryItem(name: "sportId", value: String(sportID)),
            URLQueryItem(name: "teamId", value: String(teamID)),
            URLQueryItem(name: "hydrate", value: "linescore"),
        ]
        guard let (data, _) = try? await URLSession.shared.data(from: components.url!),
              let schedule = try? JSONDecoder().decode(Schedule.self, from: data),
              let game = schedule.dates.first?.games.first else { return nil }

        func abbr(_ side: Schedule.Game.Teams.Side?) -> String {
            side?.team?.abbreviation ?? String(side?.team?.teamName?.prefix(3) ?? "—").uppercased()
        }
        let away = abbr(game.teams?.away)
        let home = abbr(game.teams?.home)
        let awayScore = game.teams?.away?.score ?? 0
        let homeScore = game.teams?.home?.score ?? 0

        switch game.status?.abstractGameState {
        case "Live":
            var inning = ""
            if let state = game.linescore?.inningState, let number = game.linescore?.currentInning {
                inning = " · \(state.prefix(3)) \(number)"
            }
            return GameLine(label: label, text: "\(away) \(awayScore)–\(homeScore) \(home)\(inning)", isLive: true)
        case "Final":
            return GameLine(label: label, text: "\(away) \(awayScore)–\(homeScore) \(home) · Final")
        default:
            let formatter = ISO8601DateFormatter()
            if let raw = game.gameDate, let date = formatter.date(from: raw) {
                let out = DateFormatter()
                out.dateFormat = "h:mm a"
                return GameLine(label: label, text: "\(away) at \(home) · \(out.string(from: date))")
            }
            return GameLine(label: label, text: "\(away) at \(home)")
        }
    }
}

// MARK: - Moon phase (compact local computation)

private enum Moon {
    static func phase(on date: Date) -> (symbol: String, name: String) {
        let jd = date.timeIntervalSince1970 / 86400.0 + 2440587.5
        let d = jd - 2451543.5
        func norm(_ x: Double) -> Double { var v = x.truncatingRemainder(dividingBy: 360); if v < 0 { v += 360 }; return v }
        // Sun ecliptic longitude (low precision)
        let ws = 282.9404 + 4.70935e-5 * d
        let ms = norm(356.0470 + 0.9856002585 * d)
        let sunLon = norm(ws + ms + 1.915 * sin(ms * .pi / 180))
        // Moon mean longitude with the largest evection/variation terms
        let moonLon = norm(218.316 + 13.176396 * d)
        let elongation = norm(moonLon - sunLon)
        switch elongation {
        case ..<22.5: return ("moonphase.new.moon", "New Moon")
        case ..<67.5: return ("moonphase.waxing.crescent", "Waxing Crescent")
        case ..<112.5: return ("moonphase.first.quarter", "First Quarter")
        case ..<157.5: return ("moonphase.waxing.gibbous", "Waxing Gibbous")
        case ..<202.5: return ("moonphase.full.moon", "Full Moon")
        case ..<247.5: return ("moonphase.waning.gibbous", "Waning Gibbous")
        case ..<292.5: return ("moonphase.last.quarter", "Last Quarter")
        case ..<337.5: return ("moonphase.waning.crescent", "Waning Crescent")
        default: return ("moonphase.new.moon", "New Moon")
        }
    }
}

// MARK: - Home screen views

struct GlanceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: GlanceEntry

    var body: some View {
        switch family {
        case .systemMedium: medium
        case .systemLarge: large
        case .accessoryCircular: circular
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        default: small
        }
    }

    // MARK: Small — the front page stamp

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            masthead
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(entry.tempF.map { "\($0)°" } ?? "—")
                    .font(.system(size: 38, weight: .bold, design: .serif))
                    .foregroundStyle(WPalette.ink)
                    .fixedSize()
                    .layoutPriority(2)
                feelsTag(size: 14)
                Image(systemName: entry.symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(WPalette.gold)
                Spacer(minLength: 0)
            }
            Text(detailLine)
                .font(.system(size: 9.5, weight: .heavy))
                .tracking(0.3)
                .foregroundStyle(WPalette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            rule
            if let game = entry.games.first(where: \.isLive) ?? entry.games.first {
                gameRow(game, compact: true)
            } else {
                eveningRow
            }
            if let desk = entry.desk {
                deskRow(desk)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(13)
        .textCase(.uppercase)
        .containerBackground(WPalette.paper, for: .widget)
    }

    // MARK: Medium — weather desk + scoreboard

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                masthead
                Spacer(minLength: 0)
                HStack(alignment: .lastTextBaseline, spacing: 7) {
                    Text(entry.tempF.map { "\($0)°" } ?? "—")
                        .font(.system(size: 44, weight: .bold, design: .serif))
                        .foregroundStyle(WPalette.ink)
                        .fixedSize()
                        .layoutPriority(2)
                    feelsTag(size: 16)
                    Image(systemName: entry.symbol)
                        .font(.system(size: 17))
                        .foregroundStyle(WPalette.gold)
                }
                Text(rangeLine)
                    .font(.system(size: 9.5, weight: .heavy))
                    .tracking(0.3)
                    .foregroundStyle(WPalette.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(WPalette.line).frame(width: 1)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("SCOREBOARD")
                        .font(.system(size: 7.5, weight: .heavy)).tracking(1.2)
                        .foregroundStyle(WPalette.subtle)
                    Spacer()
                    if entry.games.contains(where: \.isLive) {
                        HStack(spacing: 3) {
                            Circle().fill(WPalette.red).frame(width: 5, height: 5)
                            Text("LIVE")
                                .font(.system(size: 7.5, weight: .heavy)).tracking(0.8)
                                .foregroundStyle(WPalette.red)
                        }
                    }
                }
                ForEach(entry.games, id: \.label) { game in
                    gameRow(game, compact: false)
                }
                if entry.games.isEmpty {
                    Text("No games today")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WPalette.muted)
                }
                Spacer(minLength: 0)
                if let desk = entry.desk {
                    deskRow(desk)
                    if let title = desk.nextEventTitle, let time = desk.nextEventTime, time > entry.date {
                        HStack(spacing: 5) {
                            Circle().fill(WPalette.blue).frame(width: 5, height: 5)
                            Text("\(time.formatted(date: .omitted, time: .shortened)) \(title)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(WPalette.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                    }
                }
                eveningRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(13)
        .textCase(.uppercase)
        .containerBackground(WPalette.paper, for: .widget)
    }

    // MARK: Large — the full front page: weather, scoreboard, and the day

    private var large: some View {
        VStack(alignment: .leading, spacing: 8) {
            masthead
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(entry.tempF.map { "\($0)°" } ?? "—")
                            .font(.system(size: 40, weight: .bold, design: .serif))
                            .foregroundStyle(WPalette.ink)
                            .fixedSize()
                            .layoutPriority(2)
                        feelsTag(size: 15)
                        Image(systemName: entry.symbol)
                            .font(.system(size: 16))
                            .foregroundStyle(WPalette.gold)
                    }
                    Text(detailLine)
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.3)
                        .foregroundStyle(WPalette.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(entry.games, id: \.label) { game in
                        gameRow(game, compact: true)
                    }
                    skyRow(icon: "sunrise.fill", text: "Sunrise \(entry.sunrise)")
                    skyRow(icon: "sunset.fill", text: "Sunset \(entry.sunset)")
                    if !entry.moonName.isEmpty {
                        skyRow(icon: entry.moonSymbol, text: entry.moonName)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            rule

            // The day, from the app's calendar snapshot.
            HStack {
                Text("THE DAY")
                    .font(.system(size: 8, weight: .heavy)).tracking(1.2)
                    .foregroundStyle(WPalette.subtle)
                Spacer()
                if let desk = entry.desk {
                    Text("\(desk.openLoops) OPEN · \(desk.clearedPercent)% CLEAR")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(desk.openLoops > 0 ? WPalette.red : WPalette.muted)
                }
            }

            let events = entry.desk?.events ?? []
            if events.isEmpty {
                Text(entry.desk == nil
                     ? "Open Daymark once to connect the calendar"
                     : "Clear calendar — nothing scheduled")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WPalette.muted)
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(events.prefix(entry.markets.isEmpty ? 8 : 7).enumerated()), id: \.offset) { _, event in
                        HStack(spacing: 7) {
                            Rectangle()
                                .fill(event.start <= entry.date && entry.date < event.end ? WPalette.red : WPalette.blue)
                                .frame(width: 2.5, height: 18)
                            VStack(alignment: .leading, spacing: 0) {
                                Text("\(event.isTomorrow ? "TOMORROW " : "")\(event.start.formatted(date: .omitted, time: .shortened))")
                                    .font(.system(size: 7.5, weight: .heavy)).tracking(0.6)
                                    .foregroundStyle(event.isTomorrow ? WPalette.subtle : WPalette.red)
                                Text(event.title)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(WPalette.ink)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            // The closing markets strip — same sources as the app's desk.
            if !entry.markets.isEmpty {
                rule
                marketsRow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .textCase(.uppercase)
        .containerBackground(WPalette.paper, for: .widget)
    }

    // MARK: Lock Screen accessories

    private var circular: some View {
        Gauge(value: Double(entry.tempF ?? 0), in: 0...110) {
            Image(systemName: entry.symbol)
        } currentValueLabel: {
            Text(entry.tempF.map { "\($0)°" } ?? "—")
                .font(.system(size: 18, weight: .bold, design: .serif))
        }
        .gaugeStyle(.accessoryCircular)
        .containerBackground(.clear, for: .widget)
    }

    private var inline: some View {
        Label {
            Text("\(entry.tempF.map { "\($0)°" } ?? "—")\(feelsText.map { " \($0)" } ?? "")\(entry.high.flatMap { high in entry.low.map { " · H\(high) L\($0)" } } ?? "")")
        } icon: {
            Image(systemName: entry.symbol)
        }
        .containerBackground(.clear, for: .widget)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: entry.symbol).font(.system(size: 11))
                Text("\(entry.tempF.map { "\($0)°" } ?? "—")\(feelsText.map { " \($0)" } ?? "")")
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if let game = entry.games.first(where: \.isLive) ?? entry.games.first {
                Text("\(game.isLive ? "● " : "")\(game.text)")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            Text("\(entry.high.map { "H \($0)" } ?? "") \(entry.low.map { "L \($0)" } ?? "") · SUNSET \(entry.sunset)")
                .font(.system(size: 10, weight: .semibold))
                .opacity(0.8)
                .lineLimit(1)
        }
        .textCase(.uppercase)
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.clear, for: .widget)
    }

    // MARK: Pieces

    private var masthead: some View {
        HStack(spacing: 5) {
            HStack(alignment: .bottom, spacing: 1.5) {
                Capsule().fill(WPalette.subtle).frame(width: 2.5, height: 4)
                Capsule().fill(WPalette.subtle).frame(width: 2.5, height: 6.5)
                Capsule().fill(WPalette.red).frame(width: 2.5, height: 9)
            }
            Text("DAYMARK")
                .font(.system(size: 7.5, weight: .heavy)).tracking(1.3)
                .foregroundStyle(WPalette.subtle)
            Spacer()
            Text(entry.date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.8)
                .foregroundStyle(WPalette.red)
        }
    }

    private var rule: some View {
        Rectangle().fill(WPalette.line).frame(height: 1)
    }

    /// Feels-like beside the numeral — a thermometer glyph and the bare
    /// number, no punctuation — shown only when it meaningfully differs
    /// from the air temperature.
    @ViewBuilder
    private func feelsTag(size: CGFloat) -> some View {
        if let feels = entry.feels, let temp = entry.tempF, abs(feels - temp) >= 2 {
            HStack(spacing: 1.5) {
                Image(systemName: "thermometer.medium")
                    .font(.system(size: size * 0.72))
                    .foregroundStyle(WPalette.gold)
                Text("\(feels)°")
                    .font(.system(size: size, weight: .bold, design: .serif))
                    .foregroundStyle(WPalette.muted)
            }
            .lineLimit(1)
            .fixedSize()
        }
    }

    /// Text-only feels-like for the Lock Screen accessories.
    private var feelsText: String? {
        guard let feels = entry.feels, let temp = entry.tempF, abs(feels - temp) >= 2 else { return nil }
        return "≈\(feels)°"
    }

    /// High/low + rain line.
    private var rangeLine: String {
        var parts: [String] = []
        if let high = entry.high, let low = entry.low { parts.append("H \(high) · L \(low)") }
        if let rain = entry.rainPct, rain > 15 { parts.append("Rain \(rain)%") }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }

    private var detailLine: String { rangeLine }

    private func gameRow(_ game: GameLine, compact: Bool) -> some View {
        HStack(spacing: 5) {
            if game.isLive {
                Circle().fill(WPalette.red).frame(width: 5, height: 5)
            }
            Text(game.label)
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.8)
                .foregroundStyle(game.isLive ? WPalette.red : WPalette.subtle)
                .frame(width: compact ? 38 : 42, alignment: .leading)
            Text(game.text)
                .font(.system(size: compact ? 9.5 : 10.5, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(WPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
    }

    /// Personal numbers from the app, via the App Group.
    private func deskRow(_ desk: WidgetSnapshot) -> some View {
        HStack(spacing: 5) {
            Circle().fill(desk.openLoops > 0 ? WPalette.red : WPalette.muted).frame(width: 5, height: 5)
            Text(desk.focusTitle.map { "FOCUS · \($0)" }
                 ?? "\(desk.openLoops) OPEN · \(desk.clearedPercent)% CLEAR")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(WPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
    }

    private func skyRow(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(WPalette.gold)
            Text(text)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(WPalette.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    /// Delayed index quotes, one ledger line: label, level, direction.
    private var marketsRow: some View {
        HStack(spacing: 0) {
            ForEach(entry.markets, id: \.label) { line in
                HStack(spacing: 4) {
                    Text(line.label)
                        .font(.system(size: 7.5, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(WPalette.subtle)
                    Text(line.price, format: .number.precision(.fractionLength(0)))
                        .font(.system(size: 10.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(WPalette.ink)
                    Text("\(line.changePct >= 0 ? "▲" : "▼")\(abs(line.changePct), specifier: "%.1f")%")
                        .font(.system(size: 9, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(line.changePct >= 0 ? WPalette.up : WPalette.down)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    /// Sunset before dark; moon phase once the evening arrives.
    private var eveningRow: some View {
        HStack(spacing: 5) {
            if entry.isEvening {
                Image(systemName: entry.moonSymbol)
                    .font(.system(size: 9))
                    .foregroundStyle(WPalette.gold)
                Text(entry.moonName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(WPalette.ink)
                    .lineLimit(1)
            } else {
                Image(systemName: "sunset.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(WPalette.gold)
                Text("Sunset \(entry.sunset)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(WPalette.ink)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Widget declarations

struct AtAGlanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DaymarkAtAGlance", provider: GlanceProvider()) { entry in
            GlanceWidgetView(entry: entry)
        }
        .configurationDisplayName("At a Glance")
        .description("Durham weather, the scoreboard, sunset, and the moon.")
        .contentMarginsDisabled()
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryInline, .accessoryRectangular,
        ])
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
