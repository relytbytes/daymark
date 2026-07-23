//
//  GoogleService.swift
//  Daymark
//
//  Google OAuth (iOS client, PKCE, no secret, no SDK) + Gmail priority triage.
//  Refresh token lives in the keychain; access tokens stay in memory.
//

import Foundation
import AuthenticationServices
import UIKit

enum ServiceError: LocalizedError {
    case notConfigured(String)
    case notConnected
    case auth(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let what): return "\(what) is not configured yet — see Settings."
        case .notConnected: return "Not connected."
        case .auth(let detail): return detail
        }
    }
}

/// Shared ASWebAuthenticationSession wrapper for OAuth flows.
@MainActor
final class WebAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthenticator()
    private var activeSession: ASWebAuthenticationSession?

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
                Task { @MainActor in self?.activeSession = nil }
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: ServiceError.auth(error?.localizedDescription ?? "Sign-in was cancelled."))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            activeSession = session
            session.start()
        }
    }
}

@MainActor
final class GoogleService {
    private static let refreshKey = "google.refresh"
    private var accessToken: String?
    private var accessExpiresAt = Date.distantPast

    var isConnected: Bool { Keychain.get(Self.refreshKey) != nil }

    // MARK: Connect / disconnect

    func connect() async throws {
        guard AppConfig.googleConfigured else {
            throw ServiceError.notConfigured("Google (iOS client ID)")
        }
        let verifier = PKCE.verifier()
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: AppConfig.googleClientID),
            URLQueryItem(name: "redirect_uri", value: AppConfig.googleRedirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/gmail.modify https://www.googleapis.com/auth/spreadsheets"),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        let callback = try await WebAuthenticator.shared.authenticate(
            url: components.url!,
            callbackScheme: AppConfig.googleCallbackScheme
        )
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
        else { throw ServiceError.auth("Google did not return an authorization code.") }

        let data = try await HTTP.postForm(URL(string: "https://oauth2.googleapis.com/token")!, body: [
            "client_id": AppConfig.googleClientID,
            "redirect_uri": AppConfig.googleRedirectURI,
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": verifier,
        ])
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        adopt(token)
        if let refresh = token.refresh_token {
            Keychain.set(refresh, key: Self.refreshKey)
        }
    }

    func disconnect() {
        Keychain.delete(Self.refreshKey)
        accessToken = nil
        accessExpiresAt = .distantPast
    }

    private func adopt(_ token: TokenResponse) {
        accessToken = token.access_token
        accessExpiresAt = Date().addingTimeInterval(TimeInterval(token.expires_in ?? 3600) - 120)
    }

    private func validToken() async throws -> String {
        if let accessToken, Date() < accessExpiresAt { return accessToken }
        guard let refresh = Keychain.get(Self.refreshKey) else { throw ServiceError.notConnected }
        let data = try await HTTP.postForm(URL(string: "https://oauth2.googleapis.com/token")!, body: [
            "client_id": AppConfig.googleClientID,
            "grant_type": "refresh_token",
            "refresh_token": refresh,
        ])
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        adopt(token)
        guard let access = accessToken else { throw ServiceError.auth("Google session could not be renewed.") }
        return access
    }

    // MARK: Landed pipeline (Google Sheet the job-search-command-center writes)

    /// Reads the Tracker tab of the Landed sheet: Company, Role, Source, Location,
    /// Work Type, Salary, Track, Status, Priority, Contact, Next, Notes (A2:L).
    func fetchLandedRoles(sheetID: String) async throws -> [LandedRole] {
        let token = try await validToken()
        var components = URLComponents(
            string: "https://sheets.googleapis.com/v4/spreadsheets/\(sheetID)/values/Tracker!A2:L")!
        components.queryItems = [URLQueryItem(name: "majorDimension", value: "ROWS")]
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        if let http = urlResponse as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            struct GoogleError: Decodable {
                struct Inner: Decodable { let message: String? }
                let error: Inner?
            }
            let message = (try? JSONDecoder().decode(GoogleError.self, from: data))?.error?.message ?? ""
            throw LandedFetchError(status: http.statusCode, message: message)
        }
        let response = try JSONDecoder().decode(SheetValues.self, from: data)
        return (response.values ?? []).enumerated().compactMap { index, row in
            func col(_ i: Int) -> String { i < row.count ? row[i].trimmingCharacters(in: .whitespaces) : "" }
            let company = col(0)
            guard !company.isEmpty else { return nil }
            return LandedRole(
                id: "r\(index)",
                company: company,
                role: col(1),
                location: col(3),
                salary: col(5),
                track: col(6),
                status: col(7).nilIfEmpty ?? "Interested",
                priority: col(8),
                contact: col(9),
                nextAction: col(10),
                notes: col(11)
            )
        }
    }

    /// Write one cell of the Tracker — the write-back half of the wire.
    /// Data row 0 lives on sheet row 2 (row 1 is the header).
    func updateLandedCell(sheetID: String, dataRow: Int, column: String, value: String) async throws {
        let token = try await validToken()
        let range = "Tracker!\(column)\(dataRow + 2)"
        var components = URLComponents(
            string: "https://sheets.googleapis.com/v4/spreadsheets/\(sheetID)/values/\(range)")!
        components.queryItems = [URLQueryItem(name: "valueInputOption", value: "USER_ENTERED")]
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["values": [[value]]])
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            struct GoogleError: Decodable {
                struct Inner: Decodable { let message: String? }
                let error: Inner?
            }
            let message = (try? JSONDecoder().decode(GoogleError.self, from: data))?.error?.message ?? ""
            throw LandedFetchError(status: http.statusCode, message: message)
        }
    }

    private struct SheetValues: Decodable {
        let values: [[String]]?
    }
}

/// A Landed sheet failure the UI can explain instead of shrugging.
struct LandedFetchError: Error {
    let status: Int
    let message: String

    var readable: String {
        switch status {
        case 403:
            return "Google denied Sheets access — disconnect and reconnect Google in Settings to grant the spreadsheet permission."
        case 404:
            return "Sheet not found — the Landed sheet ID looks wrong, or this Google account can't open it."
        case 400:
            return "The sheet has no 'Tracker' tab — check the tab name in the Landed spreadsheet."
        default:
            return "Landed sheet error \(status)\(message.isEmpty ? "" : ": \(message)")"
        }
    }
}

extension GoogleService {

    // MARK: Gmail

    func fetchPriorityMail(vips: [String], cleared: [String]) async throws -> [EmailMessage] {
        let token = try await validToken()
        let query = "in:inbox is:unread -category:promotions -category:social"
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: "15"),
        ]
        let list = try await HTTP.json(MessageList.self, components.url!,
                                       headers: ["Authorization": "Bearer \(token)"])
        let ids = (list.messages ?? []).map(\.id).filter { !cleared.contains($0) }
        guard !ids.isEmpty else { return [] }

        let vipSet = Set(vips.map { $0.lowercased() })
        var messages: [EmailMessage] = []
        try await withThrowingTaskGroup(of: EmailMessage?.self) { group in
            for id in ids.prefix(10) {
                group.addTask { [token] in
                    try? await Self.fetchMessage(id: id, token: token, vips: vipSet)
                }
            }
            for try await message in group {
                if let message { messages.append(message) }
            }
        }
        return messages.sorted { lhs, rhs in
            if lhs.isVIP != rhs.isVIP { return lhs.isVIP }
            return (lhs.date ?? .distantPast) > (rhs.date ?? .distantPast)
        }
    }

    private static func fetchMessage(id: String, token: String, vips: Set<String>) async throws -> EmailMessage {
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "metadata"),
            URLQueryItem(name: "metadataHeaders", value: "From"),
            URLQueryItem(name: "metadataHeaders", value: "Subject"),
        ]
        let detail = try await HTTP.json(MessageDetail.self, components.url!,
                                         headers: ["Authorization": "Bearer \(token)"])
        var fromName = "Unknown sender"
        var fromEmail = ""
        var subject = "(no subject)"
        for header in detail.payload?.headers ?? [] {
            if header.name.caseInsensitiveCompare("From") == .orderedSame {
                (fromName, fromEmail) = parseFrom(header.value)
            } else if header.name.caseInsensitiveCompare("Subject") == .orderedSame {
                subject = header.value.nilIfEmpty ?? subject
            }
        }
        let snippet = decodeEntities(detail.snippet ?? "")
        let date = detail.internalDate.flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0 / 1000) }
        let lowerEmail = fromEmail.lowercased()
        let automated = ["noreply", "no-reply", "notifications", "mailer", "donotreply", "newsletter"]
            .contains { lowerEmail.contains($0) }
        return EmailMessage(
            id: detail.id,
            threadID: detail.threadId ?? detail.id,
            fromName: fromName,
            fromEmail: fromEmail,
            subject: subject,
            snippet: snippet,
            date: date,
            isVIP: vips.contains(lowerEmail),
            needsReply: !automated && (snippet.contains("?") || subject.lowercased().hasPrefix("re:"))
        )
    }

    func markRead(id: String) async throws {
        let token = try await validToken()
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)/modify")!
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["removeLabelIds": ["UNREAD"]])
        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw HTTPError.status(http.statusCode)
        }
    }

    // MARK: parsing helpers

    private static func parseFrom(_ raw: String) -> (String, String) {
        if let open = raw.lastIndex(of: "<"), let close = raw.lastIndex(of: ">"), open < close {
            let email = String(raw[raw.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
            var name = String(raw[..<open]).trimmingCharacters(in: .whitespaces)
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return (name.nilIfEmpty ?? email, email)
        }
        let email = raw.trimmingCharacters(in: .whitespaces)
        return (email, email)
    }

    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}

// MARK: - Wire shapes

private struct TokenResponse: Decodable {
    let access_token: String
    let expires_in: Int?
    let refresh_token: String?
}

private struct MessageList: Decodable {
    struct Ref: Decodable { let id: String }
    let messages: [Ref]?
}

private struct MessageDetail: Decodable {
    struct Payload: Decodable {
        struct Header: Decodable {
            let name: String
            let value: String
        }
        let headers: [Header]?
    }
    let id: String
    let threadId: String?
    let snippet: String?
    let internalDate: String?
    let payload: Payload?
}
