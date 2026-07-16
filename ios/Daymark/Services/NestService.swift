//
//  NestService.swift
//  Daymark
//
//  Google Smart Device Management: the Nest thermostat's indoor
//  conditions join the weather desk. Requires a one-time $5 Device
//  Access registration on Google's side; until NestProjectID is set
//  in DaymarkConfig.plist this service stays dormant. Uses its own
//  OAuth grant (Google's partner-connections consent) and keeps its
//  refresh token separately in the Keychain.
//

import Foundation

private struct NestTokenResponse: Decodable {
    let access_token: String?
    let refresh_token: String?
    let expires_in: Int?
}

struct NestReading: Hashable {
    let indoorF: Int
    let humidity: Int?
    let mode: String            // HEAT / COOL / HEATCOOL / OFF
    let hvacActive: Bool        // currently heating or cooling
    let setpointF: Int?
    let roomName: String
}

@MainActor
final class NestService {
    private static let refreshKey = "nest.refresh"
    private var accessToken: String?
    private var accessExpiresAt = Date.distantPast

    var isConnected: Bool { Keychain.get(Self.refreshKey) != nil }
    static var isConfigured: Bool { !AppConfig.nestProjectID.isEmpty && AppConfig.googleConfigured }

    // MARK: Connect

    func connect() async throws {
        guard Self.isConfigured else {
            throw ServiceError.notConfigured("Nest (Device Access project ID)")
        }
        let verifier = PKCE.verifier()
        var components = URLComponents(
            string: "https://nestservices.google.com/partnerconnections/\(AppConfig.nestProjectID)/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: AppConfig.googleClientID),
            URLQueryItem(name: "redirect_uri", value: AppConfig.googleRedirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/sdm.service"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        let callback = try await WebAuthenticator.shared.authenticate(
            url: components.url!,
            callbackScheme: AppConfig.googleCallbackScheme
        )
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
        else { throw ServiceError.auth("Nest did not return an authorization code.") }

        let data = try await HTTP.postForm(URL(string: "https://oauth2.googleapis.com/token")!, body: [
            "client_id": AppConfig.googleClientID,
            "redirect_uri": AppConfig.googleRedirectURI,
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": verifier,
        ])
        let token = try JSONDecoder().decode(NestTokenResponse.self, from: data)
        accessToken = token.access_token
        accessExpiresAt = Date().addingTimeInterval(TimeInterval(token.expires_in ?? 3600) - 120)
        if let refresh = token.refresh_token {
            Keychain.set(refresh, key: Self.refreshKey)
        }
    }

    func disconnect() {
        Keychain.delete(Self.refreshKey)
        accessToken = nil
        accessExpiresAt = .distantPast
    }

    private func validToken() async throws -> String {
        if let accessToken, Date() < accessExpiresAt { return accessToken }
        guard let refresh = Keychain.get(Self.refreshKey) else { throw ServiceError.notConnected }
        let data = try await HTTP.postForm(URL(string: "https://oauth2.googleapis.com/token")!, body: [
            "client_id": AppConfig.googleClientID,
            "grant_type": "refresh_token",
            "refresh_token": refresh,
        ])
        let token = try JSONDecoder().decode(NestTokenResponse.self, from: data)
        accessToken = token.access_token
        accessExpiresAt = Date().addingTimeInterval(TimeInterval(token.expires_in ?? 3600) - 120)
        guard let access = accessToken else { throw ServiceError.auth("Nest session could not be renewed.") }
        return access
    }

    // MARK: Read the thermostat

    func thermostat() async throws -> NestReading? {
        let token = try await validToken()
        let url = URL(string:
            "https://smartdevicemanagement.googleapis.com/v1/enterprises/\(AppConfig.nestProjectID)/devices")!
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw HTTPError.status((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        struct Devices: Decodable {
            struct Device: Decodable {
                let type: String?
                let traits: [String: AnyCodableValue]?
                let parentRelations: [Parent]?
                struct Parent: Decodable { let displayName: String? }
            }
            let devices: [Device]?
        }
        let list = try JSONDecoder().decode(Devices.self, from: data)
        guard let thermostat = list.devices?.first(where: { $0.type?.contains("THERMOSTAT") == true })
        else { return nil }

        func trait(_ name: String) -> [String: AnyCodableValue]? {
            thermostat.traits?["sdm.devices.traits.\(name)"]?.object
        }
        func fahrenheit(_ celsius: Double) -> Int { Int((celsius * 9 / 5 + 32).rounded()) }

        guard let ambient = trait("Temperature")?["ambientTemperatureCelsius"]?.double else { return nil }
        let humidity = trait("Humidity")?["ambientHumidityPercent"]?.double.map { Int($0.rounded()) }
        let mode = trait("ThermostatMode")?["mode"]?.string ?? "OFF"
        let hvac = trait("ThermostatHvac")?["status"]?.string ?? "OFF"
        let setpointTrait = trait("ThermostatTemperatureSetpoint")
        let setpoint = setpointTrait?["coolCelsius"]?.double ?? setpointTrait?["heatCelsius"]?.double

        return NestReading(
            indoorF: fahrenheit(ambient),
            humidity: humidity,
            mode: mode,
            hvacActive: hvac != "OFF",
            setpointF: setpoint.map(fahrenheit),
            roomName: thermostat.parentRelations?.first?.displayName ?? "Home"
        )
    }
}

/// Minimal loosely-typed JSON value for SDM's trait bags.
struct AnyCodableValue: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let d = try? container.decode(Double.self) { value = d }
        else if let s = try? container.decode(String.self) { value = s }
        else if let b = try? container.decode(Bool.self) { value = b }
        else if let o = try? container.decode([String: AnyCodableValue].self) { value = o }
        else if let a = try? container.decode([AnyCodableValue].self) { value = a }
        else { value = NSNull() }
    }

    var double: Double? { value as? Double }
    var string: String? { value as? String }
    var object: [String: AnyCodableValue]? { value as? [String: AnyCodableValue] }
}
