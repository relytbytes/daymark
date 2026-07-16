//
//  SpotifyService.swift
//  Daymark
//
//  Spotify PKCE auth (reuses the web app's public client id) + playback state,
//  recent listening, and lightweight control of the active device.
//

import Foundation

@MainActor
final class SpotifyService {
    private static let refreshKey = "spotify.refresh"
    private var accessToken: String?
    private var accessExpiresAt = Date.distantPast

    var isConnected: Bool { Keychain.get(Self.refreshKey) != nil }

    private static let scopes = [
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-read-currently-playing",
        "user-read-recently-played",
        "user-top-read",
        "playlist-read-private",
        "playlist-modify-private",
    ].joined(separator: " ")

    // MARK: Connect / disconnect

    func connect() async throws {
        guard AppConfig.spotifyConfigured else {
            throw ServiceError.notConfigured("Spotify (client ID)")
        }
        let verifier = PKCE.verifier()
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: AppConfig.spotifyClientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: AppConfig.spotifyRedirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        let callback = try await WebAuthenticator.shared.authenticate(
            url: components.url!,
            callbackScheme: AppConfig.spotifyCallbackScheme
        )
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
        else { throw ServiceError.auth("Spotify did not return an authorization code.") }

        let data = try await HTTP.postForm(URL(string: "https://accounts.spotify.com/api/token")!, body: [
            "client_id": AppConfig.spotifyClientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": AppConfig.spotifyRedirectURI,
            "code_verifier": verifier,
        ])
        try adopt(data)
    }

    func disconnect() {
        Keychain.delete(Self.refreshKey)
        accessToken = nil
        accessExpiresAt = .distantPast
    }

    private func adopt(_ data: Data) throws {
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = token.access_token
        accessExpiresAt = Date().addingTimeInterval(TimeInterval(token.expires_in ?? 3600) - 120)
        if let refresh = token.refresh_token {
            Keychain.set(refresh, key: Self.refreshKey)
        }
    }

    private func validToken() async throws -> String {
        if let accessToken, Date() < accessExpiresAt { return accessToken }
        guard let refresh = Keychain.get(Self.refreshKey) else { throw ServiceError.notConnected }
        let data = try await HTTP.postForm(URL(string: "https://accounts.spotify.com/api/token")!, body: [
            "client_id": AppConfig.spotifyClientID,
            "grant_type": "refresh_token",
            "refresh_token": refresh,
        ])
        try adopt(data)
        guard let access = accessToken else { throw ServiceError.auth("Spotify session could not be renewed.") }
        return access
    }

    // MARK: Reads

    func playback() async throws -> PlaybackInfo? {
        let token = try await validToken()
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player")!, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 204 || data.isEmpty { return nil }   // nothing active
        guard (200...299).contains(http.statusCode) else { throw HTTPError.status(http.statusCode) }
        let state = try JSONDecoder().decode(PlayerState.self, from: data)
        guard let item = state.item else { return nil }
        return PlaybackInfo(
            isPlaying: state.is_playing ?? false,
            track: item.name,
            artist: item.artists?.first?.name ?? "Spotify",
            artURL: item.album?.images?.first.flatMap { URL(string: $0.url) },
            deviceName: state.device?.name,
            progressMs: state.progress_ms,
            durationMs: item.duration_ms
        )
    }

    func recentTracks() async throws -> [RecentTrack] {
        let token = try await validToken()
        let url = URL(string: "https://api.spotify.com/v1/me/player/recently-played?limit=10")!
        let response = try await HTTP.json(RecentList.self, url, headers: ["Authorization": "Bearer \(token)"])
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        var seen = Set<String>()
        var out: [RecentTrack] = []
        for item in response.items ?? [] {
            guard let track = item.track, !seen.contains(track.id ?? track.name) else { continue }
            seen.insert(track.id ?? track.name)
            out.append(RecentTrack(
                id: (track.id ?? track.name) + (item.played_at ?? ""),
                track: track.name,
                artist: track.artists?.first?.name ?? "",
                playedAt: item.played_at.flatMap { formatter.date(from: $0) ?? fallback.date(from: $0) },
                artURL: track.album?.images?.last.flatMap { URL(string: $0.url) }
            ))
        }
        return out
    }

    /// Start playback of a playlist/album context on the active device.
    func playContext(_ raw: String) async throws {
        // Accept a full open.spotify.com link or a spotify: URI.
        var uri = raw.trimmingCharacters(in: .whitespaces)
        if let url = URL(string: uri), url.host?.contains("spotify.com") == true {
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.count >= 2 { uri = "spotify:\(parts[parts.count - 2]):\(parts[parts.count - 1])" }
        }
        let token = try await validToken()
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/play")!, timeoutInterval: 15)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["context_uri": uri])
        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw HTTPError.status(http.statusCode)
        }
    }

    // MARK: Daymark Discoveries playlist

    private static let discoveriesName = "Daymark Discoveries"

    /// Find or create the Discoveries playlist; returns its id.
    private func discoveriesPlaylistID() async throws -> String {
        if let cached = UserDefaults.standard.string(forKey: "daymark-discoveries-playlist") {
            return cached
        }
        let token = try await validToken()
        struct Playlists: Decodable {
            struct Item: Decodable {
                let id: String
                let name: String
            }
            let items: [Item]?
        }
        let list = try await HTTP.json(Playlists.self,
            URL(string: "https://api.spotify.com/v1/me/playlists?limit=50")!,
            headers: ["Authorization": "Bearer \(token)"])
        if let existing = list.items?.first(where: { $0.name == Self.discoveriesName }) {
            UserDefaults.standard.set(existing.id, forKey: "daymark-discoveries-playlist")
            return existing.id
        }

        struct Me: Decodable { let id: String }
        let me = try await HTTP.json(Me.self, URL(string: "https://api.spotify.com/v1/me")!,
                                     headers: ["Authorization": "Bearer \(token)"])
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/users/\(me.id)/playlists")!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": Self.discoveriesName,
            "public": false,
            "description": "Thumbs-ups from Daymark's Discovery Wire.",
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw HTTPError.status((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        struct Created: Decodable { let id: String }
        let created = try JSONDecoder().decode(Created.self, from: data)
        UserDefaults.standard.set(created.id, forKey: "daymark-discoveries-playlist")
        return created.id
    }

    /// Search the track on Spotify and add it to Daymark Discoveries.
    func addToDiscoveries(title: String, artist: String) async throws -> Bool {
        let token = try await validToken()
        let query = "track:\(title) artist:\(artist)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        struct Search: Decodable {
            struct Tracks: Decodable {
                struct Item: Decodable { let uri: String }
                let items: [Item]?
            }
            let tracks: Tracks?
        }
        let found = try await HTTP.json(Search.self,
            URL(string: "https://api.spotify.com/v1/search?type=track&limit=1&q=\(query)")!,
            headers: ["Authorization": "Bearer \(token)"])
        guard let uri = found.tracks?.items?.first?.uri else { return false }

        let playlist = try await discoveriesPlaylistID()
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/playlists/\(playlist)/tracks")!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["uris": [uri]])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw HTTPError.status((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return true
    }

    // MARK: Discovery Wire playlist (the whole daily batch, replaced in place)

    private static let wireName = "Daymark Discovery Wire"

    /// Find or create the Discovery Wire playlist; returns its id.
    private func wirePlaylistID() async throws -> String {
        if let cached = UserDefaults.standard.string(forKey: "daymark-wire-playlist") {
            return cached
        }
        let token = try await validToken()
        struct Playlists: Decodable {
            struct Item: Decodable {
                let id: String
                let name: String
            }
            let items: [Item]?
        }
        let list = try await HTTP.json(Playlists.self,
            URL(string: "https://api.spotify.com/v1/me/playlists?limit=50")!,
            headers: ["Authorization": "Bearer \(token)"])
        if let existing = list.items?.first(where: { $0.name == Self.wireName }) {
            UserDefaults.standard.set(existing.id, forKey: "daymark-wire-playlist")
            return existing.id
        }
        struct Me: Decodable { let id: String }
        let me = try await HTTP.json(Me.self, URL(string: "https://api.spotify.com/v1/me")!,
                                     headers: ["Authorization": "Bearer \(token)"])
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/users/\(me.id)/playlists")!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": Self.wireName,
            "public": false,
            "description": "Today's Discovery Wire — regenerated daily by Daymark.",
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw HTTPError.status((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        struct Created: Decodable { let id: String }
        let created = try JSONDecoder().decode(Created.self, from: data)
        UserDefaults.standard.set(created.id, forKey: "daymark-wire-playlist")
        return created.id
    }

    /// Match one discovery track to a Spotify URI.
    private func searchTrackURI(title: String, artist: String, token: String) async -> String? {
        let query = "track:\(title) artist:\(artist)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        struct Search: Decodable {
            struct Tracks: Decodable {
                struct Item: Decodable { let uri: String }
                let items: [Item]?
            }
            let tracks: Tracks?
        }
        let found = try? await HTTP.json(Search.self,
            URL(string: "https://api.spotify.com/v1/search?type=track&limit=1&q=\(query)")!,
            headers: ["Authorization": "Bearer \(token)"])
        return found?.tracks?.items?.first?.uri
    }

    /// Replace the Discovery Wire playlist with today's batch, keeping the
    /// wire's order. Returns how many tracks matched on Spotify.
    func syncDiscoveryWirePlaylist(tracks: [(title: String, artist: String)]) async throws -> Int {
        guard !tracks.isEmpty else { return 0 }
        let token = try await validToken()

        var uris: [String?] = Array(repeating: nil, count: tracks.count)
        await withTaskGroup(of: (Int, String?).self) { group in
            for (index, track) in tracks.enumerated() {
                group.addTask {
                    (index, await self.searchTrackURI(title: track.title, artist: track.artist, token: token))
                }
            }
            for await (index, uri) in group { uris[index] = uri }
        }
        let matched = uris.compactMap { $0 }
        guard !matched.isEmpty else { return 0 }

        let playlist = try await wirePlaylistID()
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/playlists/\(playlist)/tracks")!, timeoutInterval: 20)
        request.httpMethod = "PUT"      // replaces the playlist contents
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["uris": matched])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw HTTPError.status((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return matched.count
    }

    /// Top artist names across a medium listening window — discovery seeds.
    func topArtists(limit: Int = 15) async throws -> [String] {
        let token = try await validToken()
        let url = URL(string: "https://api.spotify.com/v1/me/top/artists?time_range=medium_term&limit=\(limit)")!
        struct TopArtists: Decodable {
            struct Artist: Decodable { let name: String }
            let items: [Artist]?
        }
        let response = try await HTTP.json(TopArtists.self, url, headers: ["Authorization": "Bearer \(token)"])
        return (response.items ?? []).map(\.name)
    }

    // MARK: Controls (best effort against the active device)

    enum Control { case play, pause, next, previous }

    func send(_ control: Control) async throws {
        let token = try await validToken()
        let (path, method): (String, String)
        switch control {
        case .play: (path, method) = ("me/player/play", "PUT")
        case .pause: (path, method) = ("me/player/pause", "PUT")
        case .next: (path, method) = ("me/player/next", "POST")
        case .previous: (path, method) = ("me/player/previous", "POST")
        }
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/\(path)")!, timeoutInterval: 15)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode), http.statusCode != 204 {
            // 404 = no active device; surface a friendly error
            if http.statusCode == 404 {
                throw ServiceError.auth("No active Spotify device — start playback on a device first.")
            }
            throw HTTPError.status(http.statusCode)
        }
    }
}

// MARK: - Wire shapes

private struct TokenResponse: Decodable {
    let access_token: String
    let expires_in: Int?
    let refresh_token: String?
}

private struct PlayerState: Decodable {
    struct Device: Decodable { let name: String? }
    struct Item: Decodable {
        struct Artist: Decodable { let name: String }
        struct Album: Decodable {
            struct Image: Decodable { let url: String }
            let images: [Image]?
        }
        let id: String?
        let name: String
        let duration_ms: Int?
        let artists: [Artist]?
        let album: Album?
    }
    let is_playing: Bool?
    let progress_ms: Int?
    let device: Device?
    let item: Item?
}

private struct RecentList: Decodable {
    struct Entry: Decodable {
        let played_at: String?
        let track: PlayerState.Item?
    }
    let items: [Entry]?
}
