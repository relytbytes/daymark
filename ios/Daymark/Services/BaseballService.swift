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
            URLQueryItem(name: "hydrate", value: "team,linescore,probablePitcher,decisions"),
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
        var current = info(from: chosen, gameDate: date(chosen))
        if current.state != "Preview", let gamePk = chosen.gamePk {
            if let notes = try? await gameNotes(gamePk: gamePk, decisions: chosen.decisions) {
                current.decisionsLine = notes.decisions
                current.topHitters = notes.hitters
            }
        }
        return (current, next.map { info(from: $0, gameDate: date($0)) })
    }

    // MARK: Game notes: decisions with records, and the bats that mattered

    private struct Boxscore: Decodable {
        struct Player: Decodable {
            struct Person: Decodable {
                let id: Int?
                let fullName: String?
            }
            struct Stats: Decodable {
                let batting: Batting?
            }
            struct Batting: Decodable {
                let hits: Int?
                let atBats: Int?
                let homeRuns: Int?
                let rbi: Int?
                let doubles: Int?
                let triples: Int?
            }
            struct SeasonStats: Decodable {
                struct Pitching: Decodable {
                    let wins: Int?
                    let losses: Int?
                    let saves: Int?
                }
                let pitching: Pitching?
            }
            let person: Person?
            let stats: Stats?
            let seasonStats: SeasonStats?
        }
        struct Side: Decodable {
            struct Meta: Decodable { let abbreviation: String? }
            let team: Meta?
            let players: [String: Player]?
        }
        struct Teams: Decodable {
            let away: Side?
            let home: Side?
        }
        let teams: Teams?
    }

    private static func gameNotes(gamePk: Int,
                                  decisions: ScheduleResponse.Decisions?)
        async throws -> (decisions: String?, hitters: [String]) {
        let url = URL(string: "https://statsapi.mlb.com/api/v1/game/\(gamePk)/boxscore")!
        let box = try await HTTP.json(Boxscore.self, url)
        let sides = [box.teams?.away, box.teams?.home].compactMap { $0 }
        let everyone = sides.flatMap { Array(($0.players ?? [:]).values) }

        func lastName(_ full: String?) -> String {
            (full ?? "").split(separator: " ").last.map(String.init) ?? (full ?? "?")
        }
        func seasonPitching(_ id: Int?) -> Boxscore.Player.SeasonStats.Pitching? {
            everyone.first { $0.person?.id == id }?.seasonStats?.pitching
        }

        // Decisions line, records as of tonight.
        var parts: [String] = []
        if let winner = decisions?.winner {
            let record = seasonPitching(winner.id)
            let tail = record.map { " \($0.wins ?? 0)''' + ENDASH + '''\($0.losses ?? 0)" } ?? ""
            parts.append("W: \(lastName(winner.fullName))\(tail)")
        }
        if let loser = decisions?.loser {
            let record = seasonPitching(loser.id)
            let tail = record.map { " \($0.wins ?? 0)''' + ENDASH + '''\($0.losses ?? 0)" } ?? ""
            parts.append("L: \(lastName(loser.fullName))\(tail)")
        }
        if let save = decisions?.save {
            let record = seasonPitching(save.id)
            let tail = record?.saves.map { " (\($0))" } ?? ""
            parts.append("SV: \(lastName(save.fullName))\(tail)")
        }
        let decisionsLine = parts.isEmpty ? nil : parts.joined(separator: " ''' + MIDDOT + ''' ")

        // Bats that mattered: multi-hit games and home runs, best first.
        var hitters: [(score: Int, line: String)] = []
        for side in sides {
            let abbr = side.team?.abbreviation ?? ""
            for player in (side.players ?? [:]).values {
                guard let batting = player.stats?.batting,
                      let hits = batting.hits, let atBats = batting.atBats, atBats > 0 else { continue }
                let homers = batting.homeRuns ?? 0
                let rbi = batting.rbi ?? 0
                guard hits >= 2 || homers >= 1 else { continue }
                var extras: [String] = []
                if homers > 0 { extras.append(homers == 1 ? "HR" : "\(homers) HR") }
                if let doubles = batting.doubles, doubles > 0 { extras.append(doubles == 1 ? "2B" : "\(doubles) 2B") }
                if let triples = batting.triples, triples > 0 { extras.append("3B") }
                if rbi > 0 { extras.append("\(rbi) RBI") }
                let line = "\(abbr) \(lastName(player.person?.fullName)) \(hits)-\(atBats)"
                    + (extras.isEmpty ? "" : ", " + extras.joined(separator: ", "))
                hitters.append((score: hits + homers * 3 + rbi, line: line))
            }
        }
        let top = hitters.sorted { $0.score > $1.score }.prefix(3).map(\.line)
        return (decisionsLine, Array(top))
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

    /// The Bulls' International League division table, with L10.
    static func bullsStandings() async throws -> [StandingRow] {
        var components = URLComponents(string: "https://statsapi.mlb.com/api/v1/standings")!
        components.queryItems = [
            URLQueryItem(name: "leagueId", value: "117"),
            URLQueryItem(name: "hydrate", value: "team,division"),
        ]
        let records = try await HTTP.json(StandingsResponse.self, components.url!).records
        guard let division = records.first(where: { record in
            record.teamRecords.contains { $0.team?.id == bullsID }
        }) else { return [] }
        return rows(from: division, limit: 10, wildCardGB: false, highlightID: bullsID)
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
                             wildCardGB: Bool, highlightID: Int = BaseballService.dbacksID) -> [StandingRow] {
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
                l10: tr.lastTen,
                isDbacks: tr.team?.id == highlightID
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
    struct Decisions: Decodable {
        struct Person: Decodable {
            let id: Int?
            let fullName: String?
        }
        let winner: Person?
        let loser: Person?
        let save: Person?
    }
    struct Game: Decodable {
        let gamePk: Int?
        let gameDate: String?
        let status: Status?
        let teams: Teams?
        let linescore: Linescore?
        let venue: Venue?
        let decisions: Decisions?
    }
    struct DateEntry: Decodable { let games: [Game] }
    let dates: [DateEntry]
}

private struct StandingsResponse: Decodable {
    struct Division: Decodable { let id: Int? }
    struct TeamRecord: Decodable {
        struct Records: Decodable {
            struct Split: Decodable {
                let wins: Int?
                let losses: Int?
                let type: String?
            }
            let splitRecords: [Split]?
        }
        let team: ScheduleResponse.TeamInfo?
        let wins: Int?
        let losses: Int?
        let winningPercentage: String?
        let gamesBack: String?
        let wildCardGamesBack: String?
        let records: Records?

        var lastTen: String {
            guard let split = records?.splitRecords?.first(where: { $0.type == "lastTen" }),
                  let wins = split.wins, let losses = split.losses else { return "—" }
            return "\(wins)–\(losses)"
        }
    }
    struct Record: Decodable {
        let division: Division?
        let teamRecords: [TeamRecord]
    }
    let records: [Record]
}
