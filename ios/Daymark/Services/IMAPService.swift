//
//  IMAPService.swift
//  Daymark
//
//  A minimal IMAP4rev1 client over Network.framework TLS, built for one
//  job: read unseen iCloud mail headers and mark messages seen. iCloud
//  has no public HTTP API, so this speaks the wire protocol directly to
//  imap.mail.me.com:993 with an app-specific password from the Keychain.
//
//  Scope is deliberately small: LOGIN, SELECT INBOX, UID SEARCH UNSEEN,
//  UID FETCH of header fields, UID STORE \Seen. No IDLE, no MIME body
//  parsing — headers make the priority-mail list; the Mail app remains
//  the place mail is actually read.
//

import Foundation
import Network

actor IMAPClient {
    enum IMAPError: Error {
        case connection(String)
        case badResponse(String)
        case loginFailed
    }

    private var connection: NWConnection?
    private var buffer = Data()
    private var tagCounter = 0

    // MARK: Connection

    func connect(host: String) async throws {
        let tls = NWProtocolTLS.Options()
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 15
        let parameters = NWParameters(tls: tls, tcp: tcp)
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: 993),
            using: parameters
        )
        self.connection = connection

        final class ResumeGate: @unchecked Sendable {
            private let lock = NSLock()
            private var resumed = false
            func claim() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                if resumed { return false }
                resumed = true
                return true
            }
        }
        let gate = ResumeGate()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if gate.claim() { continuation.resume() }
                case .failed(let error):
                    if gate.claim() { continuation.resume(throwing: IMAPError.connection(error.localizedDescription)) }
                case .cancelled:
                    if gate.claim() { continuation.resume(throwing: IMAPError.connection("Connection cancelled.")) }
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
        connection.stateUpdateHandler = nil
        // Server greeting: "* OK ..."
        _ = try await readLine()
    }

    func close() {
        connection?.cancel()
        connection = nil
        buffer.removeAll()
    }

    // MARK: Wire primitives

    private func send(_ line: String) async throws {
        guard let connection else { throw IMAPError.connection("Not connected.") }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: Data((line + "\r\n").utf8), completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: IMAPError.connection(error.localizedDescription)) }
                else { continuation.resume() }
            })
        }
    }

    private func receiveChunk() async throws -> Data {
        guard let connection else { throw IMAPError.connection("Not connected.") }
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: IMAPError.connection(error.localizedDescription))
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: IMAPError.connection("Server closed the connection."))
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }

    /// Read one CRLF-terminated line, transparently absorbing {n} literals
    /// into the returned string (adequate for header-field fetches).
    private func readLine() async throws -> String {
        while true {
            if let range = buffer.range(of: Data("\r\n".utf8)) {
                var lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)

                // Literal continuation: line ends with {123}
                if let line = String(data: lineData, encoding: .utf8),
                   let literalSize = trailingLiteralSize(line) {
                    var literal = Data()
                    while literal.count < literalSize {
                        if buffer.isEmpty { buffer.append(try await receiveChunk()) }
                        let take = min(literalSize - literal.count, buffer.count)
                        literal.append(buffer.prefix(take))
                        buffer.removeFirst(take)
                    }
                    lineData.append(literal)
                    // The rest of the logical line follows the literal.
                    var rest = Data()
                    while true {
                        if let restRange = buffer.range(of: Data("\r\n".utf8)) {
                            rest = buffer.subdata(in: buffer.startIndex..<restRange.lowerBound)
                            buffer.removeSubrange(buffer.startIndex..<restRange.upperBound)
                            break
                        }
                        buffer.append(try await receiveChunk())
                    }
                    lineData.append(rest)
                }
                return String(data: lineData, encoding: .utf8)
                    ?? String(data: lineData, encoding: .isoLatin1)
                    ?? ""
            }
            buffer.append(try await receiveChunk())
        }
    }

    private func trailingLiteralSize(_ line: String) -> Int? {
        guard line.hasSuffix("}"),
              let open = line.lastIndex(of: "{") else { return nil }
        return Int(line[line.index(after: open)..<line.index(before: line.endIndex)])
    }

    /// Send a tagged command; collect untagged lines until the tagged result.
    @discardableResult
    private func command(_ text: String) async throws -> [String] {
        tagCounter += 1
        let tag = String(format: "A%03d", tagCounter)
        try await send("\(tag) \(text)")
        var lines: [String] = []
        while true {
            let line = try await readLine()
            if line.hasPrefix("\(tag) ") {
                if line.hasPrefix("\(tag) OK") { return lines }
                if text.uppercased().hasPrefix("LOGIN") { throw IMAPError.loginFailed }
                throw IMAPError.badResponse(line)
            }
            lines.append(line)
        }
    }

    // MARK: Operations

    func login(user: String, password: String) async throws {
        func quote(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        try await command("LOGIN \(quote(user)) \(quote(password))")
    }

    func selectInbox() async throws {
        try await command("SELECT INBOX")
    }

    func unseenUIDs(limit: Int = 12) async throws -> [Int] {
        let lines = try await command("UID SEARCH UNSEEN")
        for line in lines where line.uppercased().hasPrefix("* SEARCH") {
            let uids = line.dropFirst("* SEARCH".count)
                .split(separator: " ")
                .compactMap { Int($0) }
            return Array(uids.suffix(limit)).reversed()   // newest first
        }
        return []
    }

    struct Header {
        var uid: Int
        var from = ""
        var subject = ""
        var date: Date?
    }

    func fetchHeaders(uids: [Int]) async throws -> [Header] {
        guard !uids.isEmpty else { return [] }
        let set = uids.map(String.init).joined(separator: ",")
        let lines = try await command("UID FETCH \(set) (BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE)])")

        var headers: [Header] = []
        var current: Header?
        for line in lines {
            if line.hasPrefix("* ") {
                if let current { headers.append(current) }
                var header = Header(uid: 0)
                if let uidRange = line.range(of: "UID "),
                   let uid = Int(line[uidRange.upperBound...].prefix { $0.isNumber }) {
                    header.uid = uid
                }
                current = header
                parseHeaderFields(String(line), into: &current!)
            } else if current != nil {
                parseHeaderFields(line, into: &current!)
            }
        }
        if let current { headers.append(current) }
        return headers.filter { $0.uid > 0 }
    }

    private func parseHeaderFields(_ blob: String, into header: inout Header) {
        for rawLine in blob.components(separatedBy: "\r\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.lowercased().hasPrefix("from:") {
                header.from = MIMEWords.decode(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            } else if line.lowercased().hasPrefix("subject:") {
                header.subject = MIMEWords.decode(String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces))
            } else if line.lowercased().hasPrefix("date:") {
                header.date = MIMEWords.parseDate(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
        }
    }

    func markSeen(uid: Int) async throws {
        try await command("UID STORE \(uid) +FLAGS (\\Seen)")
    }

    func logout() async {
        try? await command("LOGOUT")
        close()
    }
}

// MARK: - RFC 2047 encoded-words + RFC 2822 dates

enum MIMEWords {
    /// Decode "=?charset?B|Q?...?=" runs inside a header value.
    static func decode(_ value: String) -> String {
        var out = value
        while let start = out.range(of: "=?"),
              let end = out.range(of: "?=", range: start.upperBound..<out.endIndex) {
            let token = String(out[start.lowerBound..<end.upperBound])
            let inner = token.dropFirst(2).dropLast(2)
            let parts = inner.split(separator: "?", maxSplits: 2, omittingEmptySubsequences: false)
            var decoded = token
            if parts.count == 3 {
                let charset = String(parts[0]).lowercased()
                let encoding = String(parts[1]).uppercased()
                let payload = String(parts[2])
                let data: Data?
                switch encoding {
                case "B": data = Data(base64Encoded: payload)
                case "Q":
                    let q = payload.replacingOccurrences(of: "_", with: " ")
                    data = decodeQuotedPrintable(q)
                default: data = nil
                }
                if let data {
                    let stringEncoding: String.Encoding = charset.contains("8859") ? .isoLatin1 : .utf8
                    decoded = String(data: data, encoding: stringEncoding) ?? decoded
                }
            }
            out.replaceSubrange(start.lowerBound..<end.upperBound, with: decoded)
            if decoded == token { break } // avoid infinite loop on malformed input
        }
        return out
    }

    static func decodeQuotedPrintable(_ text: String) -> Data {
        var data = Data()
        var iterator = text.makeIterator()
        while let ch = iterator.next() {
            if ch == "=", let hi = iterator.next(), let lo = iterator.next(),
               let byte = UInt8("\(hi)\(lo)", radix: 16) {
                data.append(byte)
            } else {
                data.append(contentsOf: String(ch).utf8)
            }
        }
        return data
    }

    static func parseDate(_ value: String) -> Date? {
        let formats = ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            // Strip a trailing "(UTC)" style comment.
            let cleaned = value.replacingOccurrences(of: #"\s*\(.*\)$"#, with: "", options: .regularExpression)
            if let date = formatter.date(from: cleaned) { return date }
        }
        return nil
    }
}

// MARK: - The Daymark-facing service

@MainActor
final class ICloudMailService {
    static let userKey = "daymark-icloud-user"
    static let passwordKey = "daymark-icloud-password"

    static var username: String? {
        get { Keychain.get(userKey) }
        set {
            if let value = newValue?.nilIfEmpty { Keychain.set(value, key: userKey) }
            else { Keychain.delete(userKey) }
        }
    }

    static var password: String? {
        get { Keychain.get(passwordKey) }
        set {
            if let value = newValue?.nilIfEmpty { Keychain.set(value, key: passwordKey) }
            else { Keychain.delete(passwordKey) }
        }
    }

    static var isConfigured: Bool { username?.nilIfEmpty != nil && password?.nilIfEmpty != nil }

    /// Fetch unseen iCloud headers as Daymark mail messages.
    static func fetchUnseen(vips: [String], cleared: [String]) async throws -> [EmailMessage] {
        guard let user = username, let pass = password else { return [] }
        let client = IMAPClient()
        do {
            try await client.connect(host: "imap.mail.me.com")
            try await client.login(user: user, password: pass)
            try await client.selectInbox()
            let uids = try await client.unseenUIDs()
            let headers = try await client.fetchHeaders(uids: uids)
            await client.logout()

            let vipSet = Set(vips.map { $0.lowercased() })
            let clearedSet = Set(cleared)
            return headers.compactMap { header in
                let id = "icloud-\(header.uid)"
                guard !clearedSet.contains(id) else { return nil }
                let (name, email) = splitFrom(header.from)
                let lower = email.lowercased()
                let automated = ["noreply", "no-reply", "notifications", "mailer", "donotreply", "newsletter"]
                    .contains { lower.contains($0) }
                return EmailMessage(
                    id: id,
                    threadID: id,
                    fromName: name,
                    fromEmail: email,
                    subject: header.subject.nilIfEmpty ?? "(no subject)",
                    snippet: "iCloud Mail",
                    date: header.date,
                    isVIP: vipSet.contains(lower),
                    needsReply: !automated
                )
            }
        } catch {
            await client.logout()
            throw error
        }
    }

    /// Mark one iCloud message seen ("icloud-<uid>" ids).
    static func markSeen(id: String) async throws {
        guard let user = username, let pass = password,
              let uid = Int(id.replacingOccurrences(of: "icloud-", with: "")) else { return }
        let client = IMAPClient()
        try await client.connect(host: "imap.mail.me.com")
        try await client.login(user: user, password: pass)
        try await client.selectInbox()
        try await client.markSeen(uid: uid)
        await client.logout()
    }

    private static func splitFrom(_ raw: String) -> (name: String, email: String) {
        if let open = raw.lastIndex(of: "<"), let close = raw.lastIndex(of: ">"), open < close {
            let email = String(raw[raw.index(after: open)..<close])
            var name = String(raw[..<open]).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            if name.isEmpty { name = email }
            return (name, email)
        }
        return (raw, raw)
    }
}
