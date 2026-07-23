//
//  BaseballService.swift
//  Daymark
//
//  Official MLB Stats API: Diamondbacks schedule, NL West / wild card,
//  and the Durham Bulls (MiLB, sportId 11). No key required.
//

import Foundation

enum BaseballService {
    static let dbacksID = 109
    static let bullsID = 234

    static func dbacksGame() async throws -> (current: GameInfo?, next: GameInfo?) {
        try await game(teamID: dbacksID, sportID: 1)
    }

    static func bullsGame() async throws -> (current: GameInfo?, next: GameInfo?) {
        try await game(teamID: bullsID, sportID: 11)
    }

    private static func game(teamID: Int, sportID: Int) async throws -> (current: GameInfo?, next: GameInfo?) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        let start = formatter.string(from: Date().addingDays(-1))
        let end = formatter.string(from: Date().addingDays(7))

        var components = URLComponents(string: "https://statsapi.mlb.com/api/v1/schedule")!
        components.queryItems = [
            URLQueryItem(name: "sportId", value: String(sportID)),
            URLQueryItem(name: "teamId", value: String(teamID)),
            URLQueryItem(name: "startDate", value: start),
            URLQueryItem(name: "endDate", value: end),
            URLQueryItem(name: "hydrate", value: "team,linescore,probablePitcher"),
        ]
        let response = try await HTTP.json(ScheduleResponse.self, components.url!)
        let games = response.dates.flatMap { $0.games }
        guard !games.isEmpty else { return (nil, nil) }

        let iso = ISO8601DateFormatter()
        func date(_ g: ScheduleResponse.Game) -> Date? { g.gameDate.flatMap { iso.date(from: $0) } }

        let live = games.first { $0.status?.abstractGameState == "Live" }
        let upcoming = games
            .filter { ($0.status?.abstractGameState ?? "") == "Preview" }
            .sorted { (date($0) ?? .distantFuture) < (date($1) ?? .distantFuture) }
            .first
        let recentFinal = games
            .filter { ($0.status?.abstractGameState ?? "") == "Final" }
            .sorted { (date($0) ?? .distantPast) > (date($1) ?? .distantPast) }
            .first { g in
                guard let d = date(g) else { return false }
                return Date().timeIntervalSince(d) < 20 * 3600
            }

        // A just-finished game outranks tomorrow's: that's when the box
        // score matters. Upcoming takes over ~20h after first pitch.
        guard let chosen = live ?? recentFinal ?? upcoming else { return (nil, nil) }
        // Up next: the first future game that isn't the one being shown.
        let next = games
            .filter { ($0.status?.abstractGameState ?? "") == "Preview" && $0.gamePk != chosen.gamePk }
            .sorted { (date($0) ?? .distantFuture) < (date($1) ?? .distantFuture) }
            .first
        return (info(from: chosen, gameDate: date(chosen)),
                next.map { info(from: $0, gameDate: date($0)) })
    }

    private static func info(from game: ScheduleResponse.Game, gameDate: Date?) -> GameInfo {
        let state = game.status?.abstractGameState ?? "Preview"
        var detail: String
        switch state {
        case "Live":
            let inning = game.linescore?.currentInning.map { "Inning \($0)" } ?? "In progress"
            let half = game.linescore?.inningState ?? ""
            let outs = game.linescore?.outs.map { " · \($0) out" } ?? ""
            detail = half.isEmpty ? "\(inning)\(outs)" : "\(half) \(game.linescore?.currentInning ?? 0)\(outs)"
        case "Final":
            detail = "Final"
        default:
            if let d = gameDate {
                detail = d.isToday ? "Today · \(d.timeText())" : "\(d.shortDate()) · \(d.timeText())"
            } else {
                detail = "Scheduled"
            }
        }
        func team(_ t: ScheduleResponse.TeamEntry?) -> TeamScore {
            TeamScore(
                name: t?.team?.teamName ?? t?.team?.name ?? "—",
                abbr: t?.team?.abbreviation ?? "",
                score: t?.score,
                teamID: t?.team?.id
            )
        }
        let innings = (game.linescore?.innings ?? []).compactMap { inning -> InningScore? in
            guard let number = inning.num else { return nil }
            return InningScore(number: number, away: inning.away?.runs, home: inning.home?.runs)
        }
        func rhe(_ side: ScheduleResponse.Linescore.Totals.Side?) -> TeamRHE? {
            guard let side else { return nil }
            return TeamRHE(runs: side.runs, hits: side.hits, errors: side.errors)
        }
        return GameInfo(
            id: game.gamePk ?? 0,
            date: gameDate,
            state: state,
            detail: detail,
            home: team(game.teams?.home),
            away: team(game.teams?.away),
            venue: game.venue?.name,
            innings: innings,
            awayRHE: rhe(game.linescore?.teams?.away),
            homeRHE: rhe(game.linescore?.teams?.home),
            awayPitcher: game.teams?.away?.probablePitcher?.fullName,
            homePitcher: game.teams?.home?.probablePitcher?.fullName
        )
    }

    // MARK: Standings

    static func standings() async throws -> (division: [StandingRow], wildcard: [StandingRow]) {
        async let divisionData = fetchStandings(type: "regularSeason")
        async let wildcardData = fetchStandings(type: "wildCard")
        let (division, wildcard) = try await (divisionData, wildcardData)

        let nlWest = division
            .first { $0.division?.id == 203 }
            .map { rows(from: $0, wildCardGB: false) } ?? []
        let wc = wildcard.first.map { rows(from: $0, limit: 8, wildCardGB: true) } ?? []
        return (nlWest, wc)
    }

    private static func fetchStandings(type: String) async throws -> [StandingsResponse.Record] {
        var components = URLComponents(string: "https://statsapi.mlb.com/api/v1/standings")!
        components.queryItems = [
            URLQueryItem(name: "leagueId", value: "104"),
            URLQueryItem(name: "standingsTypes", value: type),
            URLQueryItem(name: "hydrate", value: "team,division"),
        ]
        return try await HTTP.json(StandingsResponse.self, components.url!).records
    }

    private static func rows(from record: StandingsResponse.Record, limit: Int = 5,
                             wildCardGB: Bool) -> [StandingRow] {
        record.teamRecords.prefix(limit).map { tr in
            StandingRow(
                id: String(tr.team?.id ?? 0),
                name: tr.team?.teamName ?? tr.team?.name ?? "—",
                wins: tr.wins ?? 0,
                losses: tr.losses ?? 0,
                pct: tr.winningPercentage ?? "—",
                // Division view shows division deficit; wild card view
                // shows the wild-card deficit. Mixing them put wild-card
                // numbers under the NL West toggle.
                gamesBack: (wildCardGB ? tr.wildCardGamesBack : tr.gamesBack) ?? "—",
                isDbacks: tr.team?.id == dbacksID
            )
        }
    }
}

// MARK: - Wire shapes

private struct ScheduleResponse: Decodable {
    struct TeamInfo: Decodable {
        let id: Int?
        let name: String?
        let teamName: String?
        let abbreviation: String?
    }
    struct TeamEntry: Decodable {
        struct Pitcher: Decodable { let fullName: String? }
        let probablePitcher: Pitcher?
        let team: TeamInfo?
        let score: Int?
    }
    struct Teams: Decodable {
        let away: TeamEntry?
        let home: TeamEntry?
    }
    struct Status: Decodable {
        let abstractGameState: String?
        let detailedState: String?
    }
    struct Linescore: Decodable {
        struct Inning: Decodable {
            struct Half: Decodable { let runs: Int? }
            let num: Int?
            let away: Half?
            let home: Half?
        }
        struct Totals: Decodable {
            struct Side: Decodable {
                let runs: Int?
                let hits: Int?
                let errors: Int?
            }
            let away: Side?
            let home: Side?
        }
        let currentInning: Int?
        let inningState: String?
        let outs: Int?
        let innings: [Inning]?
        let teams: Totals?
    }
    struct Venue: Decodable { let name: String? }
    struct Game: Decodable {
        let gamePk: Int?
        let gameDate: String?
        let status: Status?
        let teams: Teams?
        let linescore: Linescore?
        let venue: Venue?
    }
    struct DateEntry: Decodable { let games: [Game] }
    let dates: [DateEntry]
}

private struct StandingsResponse: Decodable {
    struct Division: Decodable { let id: Int? }
    struct TeamRecord: Decodable {
        let team: ScheduleResponse.TeamInfo?
        let wins: Int?
        let losses: Int?
        let winningPercentage: String?
        let gamesBack: String?
        let wildCardGamesBack: String?
    }
    struct Record: Decodable {
        let division: Division?
        let teamRecords: [TeamRecord]
    }
    let records: [Record]
}
