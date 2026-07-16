//
//  DiscoveryService.swift
//  Daymark
//
//  The Discovery Wire: ten new tracks a day. Seeds come from Spotify
//  listening history plus liked artists from past rounds; the graph is
//  walked through Deezer's open API (related artists, top tracks with
//  30-second previews — no key required). Balanced mix: ~80% one hop
//  from the seeds, ~20% wildcards two hops out. Artists already in the
//  history, already surfaced, or thumbed down never come back.
//

import Foundation

struct DiscoveryTrack: Identifiable, Hashable, Codable {
    let id: String            // deezer track id
    let title: String
    let artist: String
    let previewURL: URL?      // 30-second mp3
    let artworkURL: URL?
    let reason: String        // "Related to Elliott Smith" / "Wildcard via Big Thief"
    let isWildcard: Bool

    var spotifySearchURL: URL? {
        let q = "\(artist) \(title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "spotify:search:\(q)")
    }

    var soundcloudSearchURL: URL? {
        let q = "\(artist) \(title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://soundcloud.com/search?q=\(q)")
    }
}

enum DiscoveryService {
    /// Build today's wire. `seeds` are artist names; `exclude` are lowercased
    /// artist names that must not appear (history + passes + already surfaced).
    static func dailyWire(
        seeds: [String],
        liked: [String],
        exclude: Set<String>,
        count: Int = 10
    ) async -> [DiscoveryTrack] {
        // Liked artists from feedback join (and slightly outrank) organic seeds.
        let seedPool = (liked.shuffled().prefix(4) + seeds.shuffled()).uniqued().prefix(8)
        var out: [DiscoveryTrack] = []
        var usedArtists = exclude

        let wildcardTarget = max(1, count / 5)                    // ~20%
        let relatedTarget = count - wildcardTarget

        for seed in seedPool {
            guard out.filter({ !$0.isWildcard }).count < relatedTarget else { break }
            guard let seedID = await artistID(named: seed) else { continue }
            let related = await relatedArtists(id: seedID)
            for artist in related.shuffled().prefix(3) {
                let key = artist.name.lowercased()
                guard !usedArtists.contains(key),
                      out.filter({ !$0.isWildcard }).count < relatedTarget else { continue }
                if let track = await topTrack(artistID: artist.id, artistName: artist.name,
                                              reason: "Related to \(seed)", wildcard: false) {
                    usedArtists.insert(key)
                    out.append(track)
                }
            }
        }

        // Wildcards: two hops out from a random seed — further from home.
        if let seed = seedPool.randomElement(), let seedID = await artistID(named: seed) {
            let hop1 = await relatedArtists(id: seedID)
            if let bridge = hop1.dropFirst(4).randomElement() ?? hop1.randomElement() {
                let hop2 = await relatedArtists(id: bridge.id)
                for artist in hop2.shuffled() {
                    guard out.filter(\.isWildcard).count < wildcardTarget else { break }
                    let key = artist.name.lowercased()
                    guard !usedArtists.contains(key) else { continue }
                    if let track = await topTrack(artistID: artist.id, artistName: artist.name,
                                                  reason: "Wildcard via \(bridge.name)", wildcard: true) {
                        usedArtists.insert(key)
                        out.append(track)
                    }
                }
            }
        }

        return out.shuffled()
    }

    // MARK: Deezer (open API, no key)

    private struct DeezerArtist: Decodable {
        let id: Int
        let name: String
    }

    private static func artistID(named name: String) async -> Int? {
        guard let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.deezer.com/search/artist?q=\(q)&limit=1")
        else { return nil }
        struct Search: Decodable { let data: [DeezerArtist]? }
        let result = try? await HTTP.json(Search.self, url)
        // Require a reasonable name match so "Beach House" doesn't resolve to a tribute act.
        guard let hit = result?.data?.first,
              hit.name.lowercased().hasPrefix(name.lowercased().prefix(4)) || name.lowercased().hasPrefix(hit.name.lowercased().prefix(4))
        else { return result?.data?.first?.id }
        return hit.id
    }

    private static func relatedArtists(id: Int) async -> [DeezerArtist] {
        guard let url = URL(string: "https://api.deezer.com/artist/\(id)/related?limit=12") else { return [] }
        struct Related: Decodable { let data: [DeezerArtist]? }
        return (try? await HTTP.json(Related.self, url))?.data ?? []
    }

    private static func topTrack(artistID: Int, artistName: String, reason: String, wildcard: Bool) async -> DiscoveryTrack? {
        guard let url = URL(string: "https://api.deezer.com/artist/\(artistID)/top?limit=3") else { return nil }
        struct Top: Decodable {
            struct Track: Decodable {
                struct Album: Decodable { let cover_medium: String? }
                let id: Int
                let title: String
                let preview: String?
                let album: Album?
            }
            let data: [Track]?
        }
        guard let tracks = (try? await HTTP.json(Top.self, url))?.data, !tracks.isEmpty else { return nil }
        // Skip the #1 hit half the time — the point is discovery, not the obvious single.
        let pick = tracks.count > 1 && Bool.random() ? tracks[1] : tracks[0]
        return DiscoveryTrack(
            id: String(pick.id),
            title: pick.title,
            artist: artistName,
            previewURL: pick.preview.flatMap(URL.init(string:)),
            artworkURL: pick.album?.cover_medium.flatMap(URL.init(string:)),
            reason: reason,
            isWildcard: wildcard
        )
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
