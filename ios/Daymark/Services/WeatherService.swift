//
//  WeatherService.swift
//  Daymark
//
//  Durham weather from Open-Meteo (no key required): current conditions,
//  12-hour strip, 7-day outlook, precipitation timeline with the computed
//  "rain window" sentence, and air quality (AQI / UV / pollen).
//

import Foundation

enum WeatherService {
    static func fetch() async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(AppConfig.homeLatitude)),
            URLQueryItem(name: "longitude", value: String(AppConfig.homeLongitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,relative_humidity_2m,wind_speed_10m"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,precipitation,weather_code"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset,weather_code,uv_index_max"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "wind_speed_unit", value: "mph"),
            URLQueryItem(name: "timezone", value: "America/New_York"),
            URLQueryItem(name: "forecast_days", value: "8"),
        ]
        let response = try await HTTP.json(OpenMeteoResponse.self, components.url!)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = TimeZone(identifier: "America/New_York")
        func parse(_ s: String?) -> Date? { s.flatMap { formatter.date(from: $0) } }

        guard let sunrise = parse(response.daily.sunrise.first),
              let sunset = parse(response.daily.sunset.first)
        else { throw HTTPError.status(0) }

        // Every fetched hour (8 days); the strip takes the next 12.
        let now = Date()
        var allHours: [HourForecast] = []
        let count = response.hourly.time.count
        for i in 0..<count {
            guard let t = parse(response.hourly.time[i]) else { continue }
            allHours.append(HourForecast(
                time: t,
                temp: Int(response.hourly.temperature_2m[i].rounded()),
                precip: i < (response.hourly.precipitation_probability?.count ?? 0)
                    ? response.hourly.precipitation_probability![i] : 0,
                code: i < response.hourly.weather_code.count ? response.hourly.weather_code[i] : 0,
                precipAmount: i < (response.hourly.precipitation?.count ?? 0)
                    ? response.hourly.precipitation![i] : 0
            ))
        }
        let hourly = Array(allHours.filter { $0.time >= now }.prefix(12))

        // 7-day outlook (skip today at index 0).
        var week: [DayForecast] = []
        for i in 1..<min(response.daily.time.count, 8) {
            guard let day = dayFormatter.date(from: response.daily.time[i]) else { continue }
            week.append(DayForecast(
                date: day,
                high: Int(response.daily.temperature_2m_max[i].rounded()),
                low: Int(response.daily.temperature_2m_min[i].rounded()),
                rainPct: i < response.daily.precipitation_probability_max.count
                    ? response.daily.precipitation_probability_max[i] : 0,
                code: i < (response.daily.weather_code?.count ?? 0) ? response.daily.weather_code![i] : 0
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
            hourly: hourly,
            allHours: allHours,
            humidity: response.current.relative_humidity_2m,
            windMph: Int((response.current.wind_speed_10m ?? 0).rounded()),
            uvIndexMax: response.daily.uv_index_max?.first,
            week: week,
            rainWindow: rainWindowSentence(hourly: hourly)
        )
    }

    /// Air quality from Open-Meteo's dedicated AQ API (US AQI + pollen).
    static func fetchAirQuality() async throws -> AirQuality {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(AppConfig.homeLatitude)),
            URLQueryItem(name: "longitude", value: String(AppConfig.homeLongitude)),
            URLQueryItem(name: "current", value: "us_aqi,pm2_5,ozone,grass_pollen,ragweed_pollen,birch_pollen,oak_pollen"),
            URLQueryItem(name: "timezone", value: "America/New_York"),
        ]
        let response = try await HTTP.json(AirQualityResponse.self, components.url!)
        let c = response.current
        let pollens: [(String, Double?)] = [
            ("Grass", c.grass_pollen), ("Ragweed", c.ragweed_pollen),
            ("Birch", c.birch_pollen), ("Oak", c.oak_pollen),
        ]
        let worst = pollens.compactMap { name, value in value.map { (name, $0) } }
            .max { $0.1 < $1.1 }
        return AirQuality(
            usAQI: c.us_aqi.map { Int($0.rounded()) },
            pm25: c.pm2_5,
            ozone: c.ozone,
            topPollenName: (worst?.1 ?? 0) > 0.5 ? worst?.0 : nil,
            topPollenLevel: worst?.1 ?? 0
        )
    }

    /// The one useful sentence: when does rain start/stop in the next 12 hours?
    static func rainWindowSentence(hourly: [HourForecast]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH"
        formatter.timeZone = TimeZone(identifier: "America/New_York")

        let rainy = hourly.map { $0.precip >= 40 || $0.precipAmount >= 0.02 }
        guard let firstRain = rainy.firstIndex(of: true) else {
            return "Dry for the next 12 hours."
        }
        if firstRain == 0 {
            if let clears = rainy.dropFirst().firstIndex(of: false) {
                return "Rain now — clearing by \(formatter.string(from: hourly[clears].time))."
            }
            return "Rain continuing through the next 12 hours."
        }
        let start = hourly[firstRain].time
        if let ends = rainy[firstRain...].firstIndex(of: false) {
            return "Dry until ~\(formatter.string(from: start)) — rain clears by \(formatter.string(from: hourly[ends].time))."
        }
        return "Rain starts ~\(formatter.string(from: start))."
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
        let relative_humidity_2m: Int?
        let wind_speed_10m: Double?
    }

    struct Hourly: Decodable {
        let time: [String]
        let temperature_2m: [Double]
        let precipitation_probability: [Int]?
        let precipitation: [Double]?
        let weather_code: [Int]
    }

    struct Daily: Decodable {
        let time: [String]
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
        let precipitation_probability_max: [Int]
        let sunrise: [String]
        let sunset: [String]
        let weather_code: [Int]?
        let uv_index_max: [Double]?
    }
}

private struct AirQualityResponse: Decodable {
    let current: Current
    struct Current: Decodable {
        let us_aqi: Double?
        let pm2_5: Double?
        let ozone: Double?
        let grass_pollen: Double?
        let ragweed_pollen: Double?
        let birch_pollen: Double?
        let oak_pollen: Double?
    }
}
