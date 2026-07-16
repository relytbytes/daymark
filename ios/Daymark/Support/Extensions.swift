//
//  Extensions.swift
//  Daymark
//
//  Shared helpers: colors, dates, PKCE, strings, HTTP.
//

import SwiftUI
import CryptoKit
import Security

// MARK: - Color

extension Color {
    /// Color from 0xRRGGBB.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Dates

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    func addingDays(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: n, to: self) ?? self
    }

    /// Stable per-day key, e.g. "2026-07-15".
    var dayKey: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: self)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Key of the Monday starting this week.
    var weekKey: String {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: self) // 1 = Sunday
        let sinceMonday = (weekday + 5) % 7
        return addingDays(-sinceMonday).dayKey
    }

    var isToday: Bool { Calendar.current.isDateInToday(self) }
    var isTomorrow: Bool { Calendar.current.isDateInTomorrow(self) }

    /// "9:41" (no meridiem, editorial style).
    func clockText() -> String {
        Self.timeFormatter.string(from: self)
            .replacingOccurrences(of: " AM", with: "")
            .replacingOccurrences(of: " PM", with: "")
    }

    /// "9:41 AM"
    func timeText() -> String { Self.timeFormatter.string(from: self) }

    /// "Wed · Jul 15"
    func shortDate() -> String {
        Self.shortDateFormatter.string(from: self).replacingOccurrences(of: ",", with: " ·")
    }

    /// "WEDNESDAY · JULY 15"
    func dateline() -> String {
        Self.datelineFormatter.string(from: self).replacingOccurrences(of: ",", with: " ·").uppercased()
    }

    /// "Wednesday"
    func weekdayName() -> String { Self.weekdayFormatter.string(from: self) }

    /// "Wed"
    func weekdayText() -> String { String(Self.weekdayFormatter.string(from: self).prefix(3)) }

    /// "7p" — compact hour for dense strips.
    func clockHourText() -> String {
        let hour = Calendar.current.component(.hour, from: self)
        let display = hour % 12 == 0 ? 12 : hour % 12
        return "\(display)\(hour < 12 ? "a" : "p")"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    private static let datelineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEEE"
        return f
    }()
}

/// "now", "4m ago", "2h ago", "3d ago"
func relativeAge(_ date: Date) -> String {
    let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
    if minutes < 1 { return "now" }
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h ago" }
    return "\(hours / 24)d ago"
}

// MARK: - PKCE

enum PKCE {
    static func verifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URL()
    }

    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URL()
    }
}

extension Data {
    func base64URL() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Strings & URLs

extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// All http(s) links found in the text.
    func extractURLs() -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(startIndex..., in: self)
        return detector.matches(in: self, options: [], range: range)
            .compactMap { $0.url }
            .filter { $0.scheme == "https" || $0.scheme == "http" }
    }
}

// MARK: - HTTP

enum HTTPError: Error, LocalizedError {
    case status(Int)
    var errorDescription: String? {
        if case .status(let code) = self { return "HTTP \(code)" }
        return "Network error"
    }
}

enum HTTP {
    static func data(_ url: URL, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 20)
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw HTTPError.status(http.statusCode)
        }
        return data
    }

    static func json<T: Decodable>(_ type: T.Type, _ url: URL, headers: [String: String] = [:]) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await data(url, headers: headers))
    }

    /// POST an x-www-form-urlencoded body.
    static func postForm(_ url: URL, body: [String: String], headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = body
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw HTTPError.status(http.statusCode)
        }
        return data
    }
}
