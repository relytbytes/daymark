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
    case badResponse(Int)
    case emptyReply
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
            throw AIError.badResponse(http.statusCode)
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
            throw AIError.badResponse(http.statusCode)
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
    Never invent facts that are not in the briefing data. Keep dates and times exactly \
    as given. Do not use em dashes excessively or bullet-point clutter; write clean prose \
    unless a list is asked for.
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

    /// The Sky Desk horoscope: grounded in the real computed transits.
    static func horoscope(transits: String) async throws -> String {
        try await AIService.complete(
            system: voice,
            user: """
            Ty is a Taurus (born April 21, 1986). Today's real computed sky:

            \(transits)

            Write today's horoscope for him: 3-4 sentences, editorial and a little \
            playful, grounded in these actual transits (moon sign, phase, retrogrades). \
            No generic filler; make it feel written for today specifically.
            """,
            maxTokens: 300
        )
    }
}
