//
//  AstroEvents.swift
//  Daymark
//
//  Upcoming sky events: the next full and new moons (computed by
//  scanning the phase engine), the annual meteor showers (bundled
//  peak list), and lunar eclipses visible from Durham (curated
//  catalog shortlist). No network.
//

import Foundation

struct AstroEvent: Identifiable, Hashable {
    let id: String
    let date: Date
    let title: String
    let detail: String
    let kind: Kind

    enum Kind { case moon, shower, eclipse }

    var daysAway: Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                        to: Calendar.current.startOfDay(for: date)).day ?? 0
    }
}

enum AstroEvents {
    /// The next several sky events from today, soonest first.
    static func upcoming(limit: Int = 6, from now: Date = Date()) -> [AstroEvent] {
        var events: [AstroEvent] = []

        if let full = nextPhase(target: 180, from: now) {
            events.append(AstroEvent(id: "full-\(full.timeIntervalSince1970)", date: full,
                                     title: "Full Moon", detail: "Rises around sunset", kind: .moon))
        }
        if let new = nextPhase(target: 0, from: now) {
            events.append(AstroEvent(id: "new-\(new.timeIntervalSince1970)", date: new,
                                     title: "New Moon", detail: "Darkest skies of the month", kind: .moon))
        }
        events += showers(from: now)
        events += eclipses(from: now)

        return events.sorted { $0.date < $1.date }.prefix(limit).map { $0 }
    }

    // MARK: Moon phases (scan + bisect on elongation)

    private static func elongation(_ date: Date) -> Double {
        let jd = Astronomy.julianDay(date)
        let moon = Astronomy.moonPosition(jd).lon
        let sun = Astronomy.solarEclipticLongitude(jd)
        var e = (moon - sun).truncatingRemainder(dividingBy: 360)
        if e < 0 { e += 360 }
        return e
    }

    /// Next moment elongation crosses `target` (0 = new, 180 = full).
    static func nextPhase(target: Double, from start: Date) -> Date? {
        // Signed distance to target in (-180, 180].
        func delta(_ date: Date) -> Double {
            var d = (elongation(date) - target).truncatingRemainder(dividingBy: 360)
            if d <= -180 { d += 360 }
            if d > 180 { d -= 360 }
            return d
        }
        var t = start
        var previous = delta(t)
        let step: TimeInterval = 6 * 3600
        for _ in 0..<(31 * 4) {
            let next = t.addingTimeInterval(step)
            let current = delta(next)
            // Crossing from negative to positive = elongation passing the target forward.
            if previous < 0, current >= 0 {
                var lo = t, hi = next
                for _ in 0..<20 {
                    let mid = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
                    if delta(mid) < 0 { lo = mid } else { hi = mid }
                }
                return hi
            }
            previous = current
            t = next
        }
        return nil
    }

    // MARK: Meteor showers (annual peaks; dates shift ±1 day year to year)

    private static let showerCatalog: [(month: Int, day: Int, name: String, zhr: Int, note: String)] = [
        (1, 3, "Quadrantids", 110, "Sharp overnight peak"),
        (4, 22, "Lyrids", 18, "Best after midnight"),
        (5, 5, "Eta Aquariids", 50, "Pre-dawn, Halley's debris"),
        (7, 30, "Delta Aquariids", 25, "Best from midnight south"),
        (8, 12, "Perseids", 100, "The summer classic"),
        (10, 21, "Orionids", 20, "Pre-dawn, Halley's debris"),
        (11, 17, "Leonids", 15, "Late night into dawn"),
        (12, 13, "Geminids", 150, "The year's strongest"),
        (12, 22, "Ursids", 10, "Quiet, near solstice"),
    ]

    private static func showers(from now: Date) -> [AstroEvent] {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        var events: [AstroEvent] = []
        for entry in showerCatalog {
            for candidateYear in [year, year + 1] {
                var components = DateComponents()
                components.year = candidateYear
                components.month = entry.month
                components.day = entry.day
                components.hour = 22
                guard let date = calendar.date(from: components), date >= now,
                      date.timeIntervalSince(now) < 370 * 86400 else { continue }
                events.append(AstroEvent(
                    id: "shower-\(entry.name)-\(candidateYear)",
                    date: date,
                    title: "\(entry.name) peak",
                    detail: "\(entry.note) · up to \(entry.zhr)/hr",
                    kind: .shower
                ))
                break
            }
        }
        return events
    }

    // MARK: Lunar eclipses visible from Durham (curated shortlist)

    private static let eclipseCatalog: [(y: Int, m: Int, d: Int, title: String, note: String)] = [
        (2026, 8, 28, "Partial lunar eclipse", "Visible from the Americas, evening"),
        (2028, 1, 12, "Partial lunar eclipse", "Visible from the Americas"),
        (2028, 12, 31, "Total lunar eclipse", "Visible from the Americas"),
    ]

    private static func eclipses(from now: Date) -> [AstroEvent] {
        let calendar = Calendar.current
        return eclipseCatalog.compactMap { entry in
            var components = DateComponents()
            components.year = entry.y
            components.month = entry.m
            components.day = entry.d
            components.hour = 21
            guard let date = calendar.date(from: components), date >= now else { return nil }
            return AstroEvent(id: "eclipse-\(entry.y)-\(entry.m)-\(entry.d)", date: date,
                              title: entry.title, detail: entry.note, kind: .eclipse)
        }
    }
}
