//
//  WeatherService.swift
//  Daymark
//
//  Durham weather from Open-Meteo (no key required).
//

import Foundation

enum WeatherService {
    static func fetch() async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(AppConfig.homeLatitude)),
            URLQueryItem(name: "longitude", value: String(AppConfig.homeLongitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "timezone", value: "America/New_York"),
            URLQueryItem(name: "forecast_days", value: "2"),
        ]
        let response = try await HTTP.json(OpenMeteoResponse.self, components.url!)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        func parse(_ s: String?) -> Date? { s.flatMap { formatter.date(from: $0) } }

        guard let sunrise = parse(response.daily.sunrise.first),
              let sunset = parse(response.daily.sunset.first)
        else { throw HTTPError.status(0) }

        // Next 12 hours from now.
        let now = Date()
        var hourly: [HourForecast] = []
        let count = response.hourly.time.count
        for i in 0..<count {
            guard let t = parse(response.hourly.time[i]), t >= now, hourly.count < 12 else { continue }
            hourly.append(HourForecast(
                time: t,
                temp: Int(response.hourly.temperature_2m[i].rounded()),
                precip: i < (response.hourly.precipitation_probability?.count ?? 0)
                    ? response.hourly.precipitation_probability![i] : 0,
                code: i < response.hourly.weather_code.count ? response.hourly.weather_code[i] : 0
            ))
        }

        return WeatherSnapshot(
            tempF: Int(response.current.temperature_2m.rounded()),
            feels: Int(response.current.apparent_temperature.rounded()),
            code: response.current.weather_code,
            high: Int((response.daily.temperature_2m_max.first ?? 0).rounded()),
            low: Int((response.daily.temperature_2m_min.first ?? 0).rounded()),
            rainPct: response.daily.precipitation_probability_max.first ?? 0,
            sunrise: sunrise,
            sunset: sunset,
            hourly: hourly
        )
    }
}

// MARK: - Open-Meteo response shapes

private struct OpenMeteoResponse: Decodable {
    let current: Current
    let hourly: Hourly
    let daily: Daily

    struct Current: Decodable {
        let temperature_2m: Double
        let apparent_temperature: Double
        let weather_code: Int
    }

    struct Hourly: Decodable {
        let time: [String]
        let temperature_2m: [Double]
        let precipitation_probability: [Int]?
        let weather_code: [Int]
    }

    struct Daily: Decodable {
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
        let precipitation_probability_max: [Int]
        let sunrise: [String]
        let sunset: [String]
    }
}
