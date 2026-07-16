//
//  Astronomy.swift
//  Daymark
//
//  Local astronomical computations for the Sky page: sun/moon rise & set,
//  moon phase and zodiac sign, naked-eye planet visibility, and Mercury
//  retrograde detection. Low-precision Schlyter/Meeus algorithms — accurate
//  to a few minutes, which is all a personal brief needs. No network.
//

import Foundation

// MARK: - Public results

struct SunTimes: Hashable {
    let sunrise: Date?
    let sunset: Date?
    let civilDusk: Date?
    let civilDawn: Date?
}

struct MoonInfo: Hashable {
    let moonrise: Date?
    let moonset: Date?
    let illumination: Double       // 0…1
    let phaseName: String          // "Waxing Gibbous" …
    let phaseEmojiName: String     // SF Symbol name, e.g. "moonphase.waxing.gibbous"
    let zodiacSign: String         // sign the Moon currently occupies
    let ageDays: Double            // days since new moon
}

struct PlanetSighting: Identifiable, Hashable {
    let id: String                 // planet name
    let name: String
    let rise: Date?
    let set: Date?
    let visibleTonight: Bool
    let note: String               // "Rises 10:40 PM, high after midnight"
}

struct AstroSnapshot: Hashable {
    let sun: SunTimes
    let moon: MoonInfo
    let planets: [PlanetSighting]
    let mercuryRetrograde: Bool
    let sunSign: String            // where the Sun is (season sign)
}

// MARK: - Engine

enum Astronomy {
    static let zodiacSigns = [
        "Aries", "Taurus", "Gemini", "Cancer", "Leo", "Virgo",
        "Libra", "Scorpio", "Sagittarius", "Capricorn", "Aquarius", "Pisces",
    ]

    static func snapshot(latitude: Double, longitude: Double, date: Date = Date()) -> AstroSnapshot {
        let sun = sunTimes(latitude: latitude, longitude: longitude, date: date)
        let moon = moonInfo(latitude: latitude, longitude: longitude, date: date)
        let planets = planetSightings(latitude: latitude, longitude: longitude, date: date, sun: sun)
        return AstroSnapshot(
            sun: sun,
            moon: moon,
            planets: planets,
            mercuryRetrograde: isMercuryRetrograde(date: date),
            sunSign: sign(forEclipticLongitude: solarEclipticLongitude(julianDay(date)))
        )
    }

    // MARK: Julian day

    static func julianDay(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86400.0 + 2440587.5
    }

    private static func date(fromJulian jd: Double) -> Date {
        Date(timeIntervalSince1970: (jd - 2440587.5) * 86400.0)
    }

    // MARK: Sun

    /// Solar ecliptic longitude in degrees (low precision, Meeus ch. 25).
    static func solarEclipticLongitude(_ jd: Double) -> Double {
        let t = (jd - 2451545.0) / 36525.0
        let l0 = normalized(280.46646 + 36000.76983 * t)
        let m = normalized(357.52911 + 35999.05029 * t)
        let c = (1.914602 - 0.004817 * t) * sinDeg(m)
            + (0.019993 - 0.000101 * t) * sinDeg(2 * m)
            + 0.000289 * sinDeg(3 * m)
        return normalized(l0 + c)
    }

    static func sunTimes(latitude: Double, longitude: Double, date: Date) -> SunTimes {
        SunTimes(
            sunrise: crossing(latitude: latitude, longitude: longitude, date: date, altitude: -0.833, rising: true, body: sunAltitude),
            sunset: crossing(latitude: latitude, longitude: longitude, date: date, altitude: -0.833, rising: false, body: sunAltitude),
            civilDusk: crossing(latitude: latitude, longitude: longitude, date: date, altitude: -6, rising: false, body: sunAltitude),
            civilDawn: crossing(latitude: latitude, longitude: longitude, date: date, altitude: -6, rising: true, body: sunAltitude)
        )
    }

    // MARK: Moon

    static func moonInfo(latitude: Double, longitude: Double, date: Date) -> MoonInfo {
        let jd = julianDay(date)
        let (moonLon, _, _) = moonPosition(jd)
        let sunLon = solarEclipticLongitude(jd)
        let elongation = normalized(moonLon - sunLon)
        let illumination = (1 - cosDeg(elongation)) / 2
        let age = elongation / 360 * 29.530588853

        let (phaseName, symbol) = phase(forElongation: elongation)
        return MoonInfo(
            moonrise: crossing(latitude: latitude, longitude: longitude, date: date, altitude: 0.125, rising: true, body: moonAltitude),
            moonset: crossing(latitude: latitude, longitude: longitude, date: date, altitude: 0.125, rising: false, body: moonAltitude),
            illumination: illumination,
            phaseName: phaseName,
            phaseEmojiName: symbol,
            zodiacSign: sign(forEclipticLongitude: moonLon),
            ageDays: age
        )
    }

    private static func phase(forElongation e: Double) -> (String, String) {
        switch e {
        case ..<22.5: return ("New Moon", "moonphase.new.moon")
        case ..<67.5: return ("Waxing Crescent", "moonphase.waxing.crescent")
        case ..<112.5: return ("First Quarter", "moonphase.first.quarter")
        case ..<157.5: return ("Waxing Gibbous", "moonphase.waxing.gibbous")
        case ..<202.5: return ("Full Moon", "moonphase.full.moon")
        case ..<247.5: return ("Waning Gibbous", "moonphase.waning.gibbous")
        case ..<292.5: return ("Last Quarter", "moonphase.last.quarter")
        case ..<337.5: return ("Waning Crescent", "moonphase.waning.crescent")
        default: return ("New Moon", "moonphase.new.moon")
        }
    }

    static func sign(forEclipticLongitude lon: Double) -> String {
        zodiacSigns[Int(normalized(lon) / 30) % 12]
    }

    // MARK: Planets (Schlyter's simplified orbital elements)

    struct OrbitalElements {
        let n: (Double, Double)   // longitude of ascending node (deg, deg/day)
        let i: (Double, Double)   // inclination
        let w: (Double, Double)   // argument of perihelion
        let a: Double             // semi-major axis, AU
        let e: (Double, Double)   // eccentricity
        let m: (Double, Double)   // mean anomaly
    }

    static let planetElements: [String: OrbitalElements] = [
        "Mercury": OrbitalElements(n: (48.3313, 3.24587e-5), i: (7.0047, 5.0e-8), w: (29.1241, 1.01444e-5),
                                   a: 0.387098, e: (0.205635, 5.59e-10), m: (168.6562, 4.0923344368)),
        "Venus": OrbitalElements(n: (76.6799, 2.46590e-5), i: (3.3946, 2.75e-8), w: (54.8910, 1.38374e-5),
                                 a: 0.723330, e: (0.006773, -1.302e-9), m: (48.0052, 1.6021302244)),
        "Mars": OrbitalElements(n: (49.5574, 2.11081e-5), i: (1.8497, -1.78e-8), w: (286.5016, 2.92961e-5),
                                a: 1.523688, e: (0.093405, 2.516e-9), m: (18.6021, 0.5240207766)),
        "Jupiter": OrbitalElements(n: (100.4542, 2.76854e-5), i: (1.3030, -1.557e-7), w: (273.8777, 1.64505e-5),
                                   a: 5.20256, e: (0.048498, 4.469e-9), m: (19.8950, 0.0830853001)),
        "Saturn": OrbitalElements(n: (113.6634, 2.38980e-5), i: (2.4886, -1.081e-7), w: (339.3939, 2.97661e-5),
                                  a: 9.55475, e: (0.055546, -9.499e-9), m: (316.9670, 0.0334442282)),
    ]

    /// Geocentric ecliptic longitude/latitude/distance of a planet.
    static func planetPosition(_ name: String, jd: Double) -> (lon: Double, lat: Double, dist: Double)? {
        guard let el = planetElements[name] else { return nil }
        let d = jd - 2451543.5

        func heliocentric(_ el: OrbitalElements) -> (x: Double, y: Double, z: Double) {
            let n = el.n.0 + el.n.1 * d
            let i = el.i.0 + el.i.1 * d
            let w = el.w.0 + el.w.1 * d
            let e = el.e.0 + el.e.1 * d
            let m = normalized(el.m.0 + el.m.1 * d)

            // Solve Kepler
            var ecc = m + rad2deg * e * sinDeg(m) * (1 + e * cosDeg(m))
            for _ in 0..<5 {
                ecc -= (ecc - rad2deg * e * sinDeg(ecc) - m) / (1 - e * cosDeg(ecc))
            }
            let xv = el.a * (cosDeg(ecc) - e)
            let yv = el.a * (sqrt(1 - e * e) * sinDeg(ecc))
            let v = normalized(atan2Deg(yv, xv))
            let r = sqrt(xv * xv + yv * yv)

            let xh = r * (cosDeg(n) * cosDeg(v + w) - sinDeg(n) * sinDeg(v + w) * cosDeg(i))
            let yh = r * (sinDeg(n) * cosDeg(v + w) + cosDeg(n) * sinDeg(v + w) * cosDeg(i))
            let zh = r * sinDeg(v + w) * sinDeg(i)
            return (xh, yh, zh)
        }

        let p = heliocentric(el)

        // Sun's position (Earth's heliocentric, inverted)
        let ws = 282.9404 + 4.70935e-5 * d
        let es = 0.016709 - 1.151e-9 * d
        let ms = normalized(356.0470 + 0.9856002585 * d)
        var eccS = ms + rad2deg * es * sinDeg(ms) * (1 + es * cosDeg(ms))
        eccS -= (eccS - rad2deg * es * sinDeg(eccS) - ms) / (1 - es * cosDeg(eccS))
        let xvS = cosDeg(eccS) - es
        let yvS = sqrt(1 - es * es) * sinDeg(eccS)
        let vS = normalized(atan2Deg(yvS, xvS))
        let rS = sqrt(xvS * xvS + yvS * yvS)
        let lonSun = normalized(vS + ws)
        let xs = rS * cosDeg(lonSun)
        let ys = rS * sinDeg(lonSun)

        // Geocentric
        let xg = p.x + xs
        let yg = p.y + ys
        let zg = p.z
        let lon = normalized(atan2Deg(yg, xg))
        let lat = atan2Deg(zg, sqrt(xg * xg + yg * yg))
        let dist = sqrt(xg * xg + yg * yg + zg * zg)
        return (lon, lat, dist)
    }

    static func isMercuryRetrograde(date: Date) -> Bool {
        let jd = julianDay(date)
        guard let now = planetPosition("Mercury", jd: jd),
              let later = planetPosition("Mercury", jd: jd + 1) else { return false }
        var delta = later.lon - now.lon
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta < 0
    }

    static func planetSightings(latitude: Double, longitude: Double, date: Date, sun: SunTimes) -> [PlanetSighting] {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        return planetElements.keys.sorted(by: planetOrder).compactMap { name in
            let altitudeFn: (Double, Double, Double) -> Double = { jd, lat, lon in
                planetAltitude(name: name, jd: jd, latitude: lat, longitude: lon)
            }
            let rise = crossing(latitude: latitude, longitude: longitude, date: date, altitude: 0, rising: true, body: altitudeFn)
            let set = crossing(latitude: latitude, longitude: longitude, date: date, altitude: 0, rising: false, body: altitudeFn)

            // Visible tonight = above horizon at some point between sunset and dawn.
            var visible = false
            if let dusk = sun.sunset {
                let end = sun.civilDawn ?? dusk.addingTimeInterval(10 * 3600)
                var t = dusk
                while t <= end {
                    if altitudeFn(julianDay(t), latitude, longitude) > 5 { visible = true; break }
                    t = t.addingTimeInterval(1200)
                }
            }

            var note: String
            let nightEnd = sun.civilDawn ?? date.addingTimeInterval(14 * 3600)
            if visible, let r = rise, r > Date(), let s = sun.sunset, r > s, r < nightEnd {
                note = "Rises \(formatter.string(from: r))"
            } else if visible, let s = set, s > Date(), s < nightEnd {
                note = "Up now · sets \(formatter.string(from: s))"
            } else if visible {
                note = "Up tonight"
            } else {
                note = "Not visible tonight"
            }

            return PlanetSighting(id: name, name: name, rise: rise, set: set, visibleTonight: visible, note: note)
        }
    }

    private static func planetOrder(_ a: String, _ b: String) -> Bool {
        let order = ["Mercury", "Venus", "Mars", "Jupiter", "Saturn"]
        return (order.firstIndex(of: a) ?? 9) < (order.firstIndex(of: b) ?? 9)
    }

    // MARK: Altitudes

    private static func sunAltitude(jd: Double, latitude: Double, longitude: Double) -> Double {
        let lon = solarEclipticLongitude(jd)
        return altitude(eclipticLon: lon, eclipticLat: 0, jd: jd, latitude: latitude, longitude: longitude)
    }

    private static func moonAltitude(jd: Double, latitude: Double, longitude: Double) -> Double {
        let (lon, lat, _) = moonPosition(jd)
        return altitude(eclipticLon: lon, eclipticLat: lat, jd: jd, latitude: latitude, longitude: longitude)
    }

    private static func planetAltitude(name: String, jd: Double, latitude: Double, longitude: Double) -> Double {
        guard let p = planetPosition(name, jd: jd) else { return -90 }
        return altitude(eclipticLon: p.lon, eclipticLat: p.lat, jd: jd, latitude: latitude, longitude: longitude)
    }

    /// Moon geocentric ecliptic position (Schlyter, ~1° accuracy).
    static func moonPosition(_ jd: Double) -> (lon: Double, lat: Double, dist: Double) {
        let d = jd - 2451543.5
        let n = normalized(125.1228 - 0.0529538083 * d)
        let i = 5.1454
        let w = normalized(318.0634 + 0.1643573223 * d)
        let a = 60.2666 // Earth radii
        let e = 0.054900
        let m = normalized(115.3654 + 13.0649929509 * d)

        var ecc = m + rad2deg * e * sinDeg(m) * (1 + e * cosDeg(m))
        for _ in 0..<5 {
            ecc -= (ecc - rad2deg * e * sinDeg(ecc) - m) / (1 - e * cosDeg(ecc))
        }
        let xv = a * (cosDeg(ecc) - e)
        let yv = a * (sqrt(1 - e * e) * sinDeg(ecc))
        let v = normalized(atan2Deg(yv, xv))
        let r = sqrt(xv * xv + yv * yv)

        let xh = r * (cosDeg(n) * cosDeg(v + w) - sinDeg(n) * sinDeg(v + w) * cosDeg(i))
        let yh = r * (sinDeg(n) * cosDeg(v + w) + cosDeg(n) * sinDeg(v + w) * cosDeg(i))
        let zh = r * sinDeg(v + w) * sinDeg(i)

        var lon = normalized(atan2Deg(yh, xh))
        let lat = atan2Deg(zh, sqrt(xh * xh + yh * yh))

        // Major perturbations (keeps phase + sign placement honest)
        let ms = normalized(356.0470 + 0.9856002585 * d)
        let ws = 282.9404 + 4.70935e-5 * d
        let ls = normalized(ms + ws)
        let lm = normalized(m + w + n)
        let dm = normalized(lm - ls)          // elongation
        let f = normalized(lm - n)
        lon += -1.274 * sinDeg(m - 2 * dm)
            + 0.658 * sinDeg(2 * dm)
            - 0.186 * sinDeg(ms)
            - 0.059 * sinDeg(2 * m - 2 * dm)
            - 0.057 * sinDeg(m - 2 * dm + ms)
            + 0.053 * sinDeg(m + 2 * dm)
            + 0.046 * sinDeg(2 * dm - ms)
            + 0.041 * sinDeg(m - ms)
            - 0.035 * sinDeg(dm)
            - 0.031 * sinDeg(m + ms)
        _ = f
        return (normalized(lon), lat, r)
    }

    /// Ecliptic → horizontal altitude for an observer.
    private static func altitude(eclipticLon: Double, eclipticLat: Double, jd: Double, latitude: Double, longitude: Double) -> Double {
        let obliquity = 23.4393 - 3.563e-7 * (jd - 2451543.5)
        // ecliptic -> equatorial
        let x = cosDeg(eclipticLon) * cosDeg(eclipticLat)
        let y = sinDeg(eclipticLon) * cosDeg(eclipticLat)
        let z = sinDeg(eclipticLat)
        let xe = x
        let ye = y * cosDeg(obliquity) - z * sinDeg(obliquity)
        let ze = y * sinDeg(obliquity) + z * cosDeg(obliquity)
        let ra = normalized(atan2Deg(ye, xe))
        let dec = atan2Deg(ze, sqrt(xe * xe + ye * ye))

        // local sidereal time
        let d = jd - 2451545.0
        let gmst = normalized(280.46061837 + 360.98564736629 * d)
        let lst = normalized(gmst + longitude)
        let ha = normalized(lst - ra)

        let sinAlt = sinDeg(latitude) * sinDeg(dec) + cosDeg(latitude) * cosDeg(dec) * cosDeg(ha)
        return asin(max(-1, min(1, sinAlt))) * rad2deg
    }

    /// Find the time the body crosses `altitude` (rising or setting) within ±18h, by 4-minute scan + bisection.
    private static func crossing(
        latitude: Double, longitude: Double, date: Date, altitude target: Double, rising: Bool,
        body: (Double, Double, Double) -> Double
    ) -> Date? {
        let start = Calendar.current.startOfDay(for: date)
        let step = 240.0 // 4 minutes
        var prev = body(julianDay(start), latitude, longitude) - target
        var t = start.addingTimeInterval(step)
        let end = start.addingTimeInterval(36 * 3600)

        while t <= end {
            let cur = body(julianDay(t), latitude, longitude) - target
            let crossed = rising ? (prev < 0 && cur >= 0) : (prev > 0 && cur <= 0)
            if crossed, t > date.addingTimeInterval(-12 * 3600) {
                // bisect
                var lo = t.addingTimeInterval(-step), hi = t
                for _ in 0..<12 {
                    let mid = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
                    let v = body(julianDay(mid), latitude, longitude) - target
                    if (rising && v < 0) || (!rising && v > 0) { lo = mid } else { hi = mid }
                }
                if hi >= date.addingTimeInterval(-6 * 3600) { return hi }
            }
            prev = cur
            t = t.addingTimeInterval(step)
        }
        return nil
    }

    // MARK: Math helpers

    private static let rad2deg = 180.0 / Double.pi
    private static func sinDeg(_ x: Double) -> Double { sin(x / rad2deg) }
    private static func cosDeg(_ x: Double) -> Double { cos(x / rad2deg) }
    private static func atan2Deg(_ y: Double, _ x: Double) -> Double { atan2(y, x) * rad2deg }
    private static func normalized(_ deg: Double) -> Double {
        var d = deg.truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        return d
    }
}
