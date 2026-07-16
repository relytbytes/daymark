//
//  Config.swift
//  Daymark
//
//  Static configuration loaded from DaymarkConfig.plist.
//

import Foundation

enum AppConfig {
    private static let plist: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "DaymarkConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return dict
    }()

    static let ownerName: String = (plist["OwnerName"] as? String)?.nilIfEmpty ?? "Ty"

    /// The Google Sheet behind Landed (job-search-command-center). Same ID as its
    /// GOOGLE_SHEET_ID env var; read-only from Daymark.
    static let landedSheetID: String = (plist["LandedSheetID"] as? String)?.nilIfEmpty ?? ""
    static var landedConfigured: Bool { !landedSheetID.isEmpty }

    /// Google Device Access project id (console.nest.google.com) — Nest stays
    /// dormant until this is set.
    static let nestProjectID: String = (plist["NestProjectID"] as? String)?.nilIfEmpty ?? ""
    static let homeLatitude: Double = plist["HomeLatitude"] as? Double ?? 35.9940
    static let homeLongitude: Double = plist["HomeLongitude"] as? Double ?? -78.8986

    // MARK: Spotify (PKCE public client)

    static let spotifyClientID: String = (plist["SpotifyClientID"] as? String)?.nilIfEmpty ?? ""
    static let spotifyRedirectURI = "daymark://spotify-callback"
    static let spotifyCallbackScheme = "daymark"
    static var spotifyConfigured: Bool { !spotifyClientID.isEmpty }

    // MARK: Google (iOS OAuth client, PKCE, no secret)

    static let googleClientID: String = (plist["GoogleiOSClientID"] as? String)?.nilIfEmpty ?? ""
    static var googleConfigured: Bool { !googleClientID.isEmpty }

    /// Reversed-client-id scheme Google iOS clients use for their redirect.
    static var googleCallbackScheme: String {
        guard googleConfigured else { return "" }
        let prefix = googleClientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return "com.googleusercontent.apps.\(prefix)"
    }

    static var googleRedirectURI: String { "\(googleCallbackScheme):/oauth2redirect" }
}
