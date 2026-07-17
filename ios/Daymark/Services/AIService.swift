//
//  AIService.swift
//  Daymark
//
//  Provider-agnostic AI desk. Two interchangeable backends — OpenAI
//  (chat completions) and Anthropic (messages) — behind one interface.
//  The provider and API key live in Settings (key in the Keychain,
//  never in the repo or the JSON store). Tyler runs OpenAI until his
//  credits are gone, then flips one setting to Anthropic.
//

import Foundation

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case openAI = "OpenAI"
    case anthropic = "Anthropic"
    var id: String { rawValue }

    var defaultModel: String {
        switch self {
        case .openAI: return "gpt-4o-mini"
        case .anthropic: return "claude-haiku-4-5-20251001"
        }
    }
}

enum AIError: Error {
    case notConfigured
    case badResponse(Int, String)
    case emptyReply

    /// A message worth showing the user.
    var readable: String {
        switch self {
        case .notConfigured:
            return "Add an AI key in Settings first."
        case .badResponse(let status, let detail):
            switch status {
            case 401: return "OpenAI rejected the key — recheck it in Settings."
            case 429: return detail.contains("quota")
                ? "The OpenAI account has no credits — add billing at platform.openai.com."
                : "OpenAI rate limit — wait a moment and retry."
            default: return "AI error \(status): \(detail.isEmpty ? "no detail" : String(detail.prefix(120)))"
            }
        case .emptyReply:
            return "The AI desk returned an empty reply — try again."
        }
    }
}

enum AIService {
    static let keychainKey = "daymark-ai-api-key"

    static var provider: AIProvider {
        get {
            UserDefaults.standard.string(forKey: "daymark-ai-provider")
                .flatMap(AIProvider.init(rawValue:)) ?? .openAI
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "daymark-ai-provider") }
    }

    static var apiKey: String? {
        get { Keychain.get(keychainKey) }
        set {
            if let value = newValue?.nilIfEmpty { Keychain.set(value, key: keychainKey) }
            else { Keychain.delete(keychainKey) }
        }
    }

    static var isConfigured: Bool { apiKey?.nilIfEmpty != nil }

    /// One-shot completion: system + user prompt → text.
    static func complete(system: String, user: String, maxTokens: Int = 700) async throws -> String {
        guard let key = apiKey?.nilIfEmpty else { throw AIError.notConfigured }
        switch provider {
        case .openAI: return try await openAI(key: key, system: system, user: user, maxTokens: maxTokens)
        case .anthropic: return try await anthropic(key: key, system: system, user: user, maxTokens: maxTokens)
        }
    }

    // MARK: OpenAI backend

    private static func openAI(key: String, system: String, user: String, maxTokens: Int) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": AIProvider.openAI.defaultModel,
            "max_tokens": maxTokens,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AIError.badResponse(http.statusCode, Self.errorDetail(from: data))
        }
        struct Reply: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        guard let text = reply.choices.first?.message.content?.nilIfEmpty else { throw AIError.emptyReply }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Pull the provider's human-readable error message out of an error body.
    private static func errorDetail(from data: Data) -> String {
        struct ErrorBody: Decodable {
            struct Inner: Decodable {
                let message: String?
                let type: String?
                let code: String?
            }
            let error: Inner?
        }
        guard let body = try? JSONDecoder().decode(ErrorBody.self, from: data) else {
            return String(data: data.prefix(160), encoding: .utf8) ?? ""
        }
        return [body.error?.code, body.error?.type, body.error?.message]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    // MARK: Anthropic backend

    private static func anthropic(key: String, system: String, user: String, maxTokens: Int) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": AIProvider.anthropic.defaultModel,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": user]],
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AIError.badResponse(http.statusCode, Self.errorDetail(from: data))
        }
        struct Reply: Decodable {
            struct Block: Decodable {
                let type: String
                let text: String?
            }
            let content: [Block]
        }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        let text = reply.content.compactMap { $0.type == "text" ? $0.text : nil }.joined()
        guard !text.isEmpty else { throw AIError.emptyReply }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - The AI Desk: Daymark's editorial features

enum AIDesk {
    private static let voice = """
    You are the desk editor of Daymark, Ty's personal morning-paper app. Write in a \
    literate, warm, concise editorial voice — a great local columnist, not an assistant. \
    Ty is the only reader: address them directly as "you" and never refer to them in \
    the third person or by any pronoun. Never invent facts that are not in the briefing \
    data. Keep dates and times exactly as given. Do not use em dashes excessively or \
    bullet-point clutter; write clean prose unless a list is asked for.
    """

    /// Morning: propose the Essential Three + first move from real context.
    static func dailyPlan(briefing: String) async throws -> String {
        try await AIService.complete(
            system: voice,
            user: """
            Here is today's raw briefing data:

            \(briefing)

            Propose today's plan: exactly three "Essential Three" items (one line each, \
            imperative, grounded in the data above), then one "First move" — the single \
            most specific 9 AM action. Format:

            1. …
            2. …
            3. …
            First move: …
            """,
            maxTokens: 400
        )
    }

    /// Job search coach: which pipeline roles deserve attention today.
    static func jobCoach(pipeline: String) async throws -> String {
        try await AIService.complete(
            system: voice,
            user: """
            Ty's job pipeline (stage · company · role · days since last touch · next action):

            \(pipeline)

            As his job-search coach, name the 2-3 roles that most deserve attention today \
            and say exactly what to do for each (one sentence per role). Flag anything \
            going stale. Be direct.
            """,
            maxTokens: 400
        )
    }

    /// Email triage: one-line "why this matters" per priority message.
    static func mailTriage(messages: String) async throws -> String {
        try await AIService.complete(
            system: voice,
            user: """
            Priority inbox (sender · subject · snippet):

            \(messages)

            For each message, one line: why it matters and the suggested next step. \
            Format each as "Sender — action." Skip anything that needs no action.
            """,
            maxTokens: 400
        )
    }

    /// Evening: a short sports-column-style recap of the day.
    static func eveningNarrative(dayData: String) async throws -> String {
        try await AIService.complete(
            system: voice,
            user: """
            The day's ledger:

            \(dayData)

            Write a 3-4 sentence evening column about how the day actually went — honest, \
            a little wry, ending with one line about tomorrow's first move.
            """,
            maxTokens: 300
        )
    }

    /// A prep brief for the next calendar appointment, grounded in the
    /// event's real details (and the Landed pipeline when it matches).
    static func meetingPrep(details: String, isInterview: Bool) async throws -> String {
        try await AIService.complete(
            system: voice,
            user: """
            Ty's next appointment, with everything known about it:

            \(details)

            \(isInterview ? """
            Ty's background, for fit: 15+ years of hospitality and restaurant \
            operations leadership, now interviewing for operations, management, \
            and guest-experience roles. He shows best when concrete numbers and \
            war stories carry the answers.
            """ : "")
            You may draw on what you reliably know about the named company or \
            venue — its business, city, reputation, industry pressures — to make \
            this specific. Never invent people, interviewers, or role details \
            beyond the data above.

            Write the desk's prep brief with these plain-text sections:
            WHY IT MATTERS — one sharp sentence.
            GET READY — three concrete prep moves for the time remaining, each \
            naming something specific to THIS appointment (the company, the \
            place, the people). If a line could appear in any generic prep \
            guide, cut it and go more specific.
            \(isInterview
              ? "LIKELY QUESTIONS — three this specific company would plausibly ask, each with a one-line angle drawn from Ty's background.\nASK THEM — three questions that prove homework on this company."
              : "WORTH ASKING — two or three questions that make you the most prepared person in the room.")
            WATCH FOR — one risk or detail to get ahead of.
            """,
            maxTokens: 700
        )
    }

    /// Interview prep primer for a pipeline role at screen/interview stage.
    static func interviewPrep(company: String, role: String, stage: String, track: String, notes: String, headlines: String) async throws -> String {
        try await AIService.complete(
            system: voice,
            user: """
            Ty has a \(stage.lowercased()) coming up:

            Company: \(company)
            Role: \(role)
            Track: \(track.nilIfEmpty ?? "—")
            His notes: \(notes.nilIfEmpty ?? "(none)")
            Today's general headlines (mention only if relevant): \(headlines.nilIfEmpty ?? "(none)")

            Write a tight prep primer with these plain-text sections:
            THE PITCH — 2 sentences on how Ty's hospitality-operations background maps to this role.
            LIKELY QUESTIONS — 4, with a one-line angle for each.
            SMART QUESTIONS TO ASK — 4 thoughtful ones.
            WATCH FOR — one risk or gap to get ahead of.
            """,
            maxTokens: 600
        )
    }

    /// A follow-up email draft for a role that needs a nudge.
    static func followUpDraft(company: String, role: String, stage: String, contact: String, daysSinceTouch: Int) async throws -> String {
        try await AIService.complete(
            system: voice,
            user: """
            Draft a follow-up email from Ty Shelton about this application:

            Company: \(company) · Role: \(role) · Stage: \(stage)
            Contact: \(contact.nilIfEmpty ?? "(unknown — generic greeting)")
            Days since last movement: \(daysSinceTouch)

            3-5 sentences, professional and warm, reaffirming interest and fit without
            groveling. Start with a subject line on its own first line as "Subject: …".
            No placeholders like [Name] — if the contact is unknown, write around it.
            """,
            maxTokens: 350
        )
    }

    /// A tarot reading woven from the actual drawn cards and the asker's question.
    static func tarotReading(question: String, cards: [(position: String, name: String, meaning: String)]) async throws -> String {
        let spread = cards.map { "\($0.position): \($0.name) — \($0.meaning)" }.joined(separator: "\n")
        return try await AIService.complete(
            system: voice,
            user: """
            Ty asked the cards: "\(question.nilIfEmpty ?? "What do I need to know today?")"

            The spread drawn (these are the real cards — read THESE, do not invent others):
            \(spread)

            Write the reading, speaking directly to Ty as "you": one short paragraph
            per card tying its meaning to the question, then a closing line that draws
            the three together into one piece of practical counsel. Warm, grounded,
            no doom, no hedging disclaimers.
            """,
            maxTokens: 550
        )
    }

    /// The Veraya sprint ledger: a running record of what the checkmarks
    /// and notes actually mean, rewritten as the sprint moves.
    static func sprintLedger(state: String, percent: Int, previous: String) async throws -> String {
        try await AIService.complete(
            system: voice,
            user: """
            The Veraya sprint board right now (\(percent)% complete):

            \(state)

            \(previous.isEmpty ? "" : "The previous ledger entry, for continuity:\n\(previous)\n")
            Rewrite the sprint ledger: one short paragraph recording what has
            actually been decided or proven so far (drawn from the done items
            and the notes — quote the substance of the notes, don't just say
            notes exist), then one line starting "Next proof:" naming the most
            specific next move. This is the record to look back at, so keep
            every concrete detail from the notes.
            """,
            maxTokens: 350
        )
    }

    /// A deeper unfolding of the daily oracle card.
    static func oracleReading(card: String, message: String) async throws -> String {
        try await AIService.complete(
            system: voice,
            user: """
            Today's oracle card for Ty is "\(card)". Its keynote line: "\(message)"

            Write the deeper reading in two short paragraphs. First, unfold the
            card's symbolism — what this image asks of a person, beyond the
            keynote. Second, ground it in an ordinary day: where it might show
            up in work, the job search, the body, or the home, and one concrete
            way to honor it before the day ends. Warm, specific, no doom, no
            hedging disclaimers.
            """,
            maxTokens: 400
        )
    }

    /// A short guided meditation composed for today.
    static func meditation(theme: String) async throws -> String {
        try await AIService.complete(
            system: voice,
            user: """
            Compose a short guided meditation for Ty — about 150 words, second person,
            present tense, slow cadence with line breaks between beats. Today's thread:
            \(theme)

            Open with settling the body, move through three or four breaths of imagery
            drawn from the thread, end with one sentence he can carry into the day.
            No preamble, no title — just the meditation itself.
            """,
            maxTokens: 350
        )
    }

    /// The Sky Desk horoscope: grounded in the real computed transits.
    static func horoscope(transits: String) async throws -> String {
        try await AIService.complete(
            system: voice,
            user: """
            Ty is a Taurus (born April 21, 1986). Today's real computed sky:

            \(transits)

            Write today's horoscope, addressed directly to Ty as "you": 3-4 sentences, \
            editorial and a little playful, grounded in these actual transits (moon \
            sign, phase, retrogrades). No generic filler; make it feel written for \
            today specifically.
            """,
            maxTokens: 300
        )
    }
}
