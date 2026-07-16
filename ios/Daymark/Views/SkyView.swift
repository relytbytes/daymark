//
//  SkyView.swift
//  Daymark
//
//  The dedicated weather + night sky page: 7-day outlook, precipitation
//  timeline, air quality, sun & moon almanac, tonight's planets, and the
//  astrology desk (computed transits; the AI horoscope joins when the
//  AI layer is configured).
//

import SwiftUI

struct SkyView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    domeSection
                    if let weather = app.weather {
                        conditionsBoard(weather)
                        precipSection(weather)
                        weekSection(weather)
                    }
                    airSection
                    radarSection
                    almanacSection
                    planetsSection
                    astrologySection
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .background(Palette.paper)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.ink)
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("THE SKY DESK · DURHAM")
                .kickerStyle(Palette.coral, size: 10, tracking: 1.5)
                .padding(.bottom, 8)
            Text("Above the Bull City.")
                .font(DS.display(34))
                .foregroundStyle(Palette.ink)
            InkRule().padding(.top, 12)
        }
        .padding(.top, 10)
    }

    // MARK: The Dome

    private var domeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionRuleHeader(title: "The Dome")
                LivePill(text: "Live")
            }
            .padding(.bottom, 8)
            Text("The sky over Durham right now. Pinch to zoom, drag to pan, tap a star.")
                .font(DS.label(11, weight: .semibold))
                .foregroundStyle(Palette.muted)
                .padding(.bottom, 10)
            DomeView()
        }
        .padding(.top, 20)
    }

    // MARK: Current conditions

    private func conditionsBoard(_ weather: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 14) {
                Text("\(weather.tempF)°")
                    .font(DS.display(58))
                    .foregroundStyle(Palette.ink)
                VStack(alignment: .leading, spacing: 3) {
                    Text(weather.description)
                        .font(DS.label(13, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Text("Feels \(weather.feels)° · H \(weather.high) · L \(weather.low)")
                        .font(DS.label(11, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
            }
            .padding(.bottom, 12)

            HStack(spacing: 0) {
                statCell("WIND", "\(weather.windMph) mph")
                divider
                statCell("HUMIDITY", weather.humidity.map { "\($0)%" } ?? "—")
                divider
                statCell("UV MAX", weather.uvIndexMax.map { String(format: "%.0f", $0) } ?? "—")
                divider
                statCell("RAIN", "\(weather.rainPct)%")
            }
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .top) { Hairline() }
            .overlay(alignment: .bottom) { Hairline() }
        }
        .padding(.top, 20)
    }

    private var divider: some View {
        Rectangle().fill(Palette.hairlineSoft).frame(width: 1).padding(.vertical, 6)
    }

    private func statCell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(label).kickerStyle(Palette.subtle, size: 7.5, tracking: 1.0)
            Text(value)
                .font(DS.display(16))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    // MARK: Precipitation timeline

    private func precipSection(_ weather: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(title: "The Rain Window")
                .padding(.bottom, 10)

            Text(weather.rainWindow)
                .font(DS.deck(15))
                .foregroundStyle(Palette.ink)
                .padding(.bottom, 12)

            // 12-hour precip probability strip
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(weather.hourly) { hour in
                    VStack(spacing: 4) {
                        Rectangle()
                            .fill(hour.precip >= 40 ? Palette.blue : Palette.blueSoft)
                            .frame(height: max(4, CGFloat(hour.precip) * 0.56))
                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3))
                        Text(hour.time.clockHourText())
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundStyle(Palette.subtle)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 76, alignment: .bottom)
        }
        .padding(.top, 24)
    }

    // MARK: 7-day

    private func weekSection(_ weather: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(title: "The Week Ahead")
                .padding(.bottom, 6)
            ForEach(weather.week) { day in
                VStack(spacing: 0) {
                    Hairline()
                    HStack(spacing: 10) {
                        Text(day.date.weekdayText())
                            .font(DS.label(13, weight: .bold))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 44, alignment: .leading)
                        Image(systemName: day.symbol)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.gold)
                            .frame(width: 24)
                        Text(day.rainPct > 20 ? "\(day.rainPct)%" : " ")
                            .font(DS.label(10, weight: .bold))
                            .foregroundStyle(Palette.blue)
                            .frame(width: 34, alignment: .leading)
                        Spacer()
                        tempRange(day, weekLow: weather.week.map(\.low).min() ?? day.low,
                                  weekHigh: weather.week.map(\.high).max() ?? day.high)
                        Text("\(day.low)°–\(day.high)°")
                            .font(DS.label(12, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.ink)
                            .frame(width: 66, alignment: .trailing)
                    }
                    .padding(.vertical, 9)
                }
            }
            Hairline()
        }
        .padding(.top, 24)
    }

    private func tempRange(_ day: DayForecast, weekLow: Int, weekHigh: Int) -> some View {
        GeometryReader { geo in
            let span = max(1, CGFloat(weekHigh - weekLow))
            let x0 = CGFloat(day.low - weekLow) / span * geo.size.width
            let x1 = CGFloat(day.high - weekLow) / span * geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.paperDeep).frame(height: 4)
                Capsule()
                    .fill(LinearGradient(colors: [Palette.gold.opacity(0.55), Palette.coral.opacity(0.8)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, x1 - x0), height: 4)
                    .offset(x: x0)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(width: 72, height: 16)
    }

    // MARK: Air quality

    @ViewBuilder
    private var airSection: some View {
        if let air = app.airQuality {
            VStack(alignment: .leading, spacing: 0) {
                SectionRuleHeader(title: "The Air")
                    .padding(.bottom, 10)
                HStack(spacing: 0) {
                    VStack(spacing: 4) {
                        Text("AQI").kickerStyle(Palette.subtle, size: 7.5, tracking: 1.0)
                        Text(air.usAQI.map(String.init) ?? "—")
                            .font(DS.display(20))
                            .foregroundStyle((air.usAQI ?? 0) > 100 ? Palette.coral : Palette.ink)
                        Text(air.aqiLabel)
                            .font(DS.label(8.5, weight: .bold))
                            .foregroundStyle(Palette.muted)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    divider
                    VStack(spacing: 4) {
                        Text("PM2.5").kickerStyle(Palette.subtle, size: 7.5, tracking: 1.0)
                        Text(air.pm25.map { String(format: "%.0f", $0) } ?? "—")
                            .font(DS.display(20))
                            .foregroundStyle(Palette.ink)
                        Text("µg/m³")
                            .font(DS.label(8.5, weight: .bold))
                            .foregroundStyle(Palette.muted)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    divider
                    VStack(spacing: 4) {
                        Text("POLLEN").kickerStyle(Palette.subtle, size: 7.5, tracking: 1.0)
                        Text(air.topPollenName ?? "Low")
                            .font(DS.display(20))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .foregroundStyle(Palette.ink)
                        Text(air.pollenLabel)
                            .font(DS.label(8.5, weight: .bold))
                            .foregroundStyle(Palette.muted)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .fixedSize(horizontal: false, vertical: true)
                .overlay(alignment: .top) { Hairline() }
                .overlay(alignment: .bottom) { Hairline() }
            }
            .padding(.top, 24)
        }
    }

    // MARK: Radar

    private var radarSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionRuleHeader(title: "Radar")
                .padding(.bottom, 10)
            RadarWebView()
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line, lineWidth: 1))
            Text("LIVE RADAR · RAINVIEWER")
                .kickerStyle(Palette.subtle, size: 7, tracking: 1.2)
                .padding(.top, 6)
        }
        .padding(.top, 24)
    }

    // MARK: Sun & moon almanac

    @ViewBuilder
    private var almanacSection: some View {
        if let astro = app.astro {
            VStack(alignment: .leading, spacing: 0) {
                SectionRuleHeader(title: "Sun & Moon")
                    .padding(.bottom, 12)

                HStack(spacing: 12) {
                    Image(systemName: astro.moon.phaseEmojiName)
                        .font(.system(size: 40))
                        .foregroundStyle(Palette.gold)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(astro.moon.phaseName)
                            .font(DS.deck(18, weight: 500, italic: false))
                            .foregroundStyle(Palette.ink)
                        Text("\(Int((astro.moon.illumination * 100).rounded()))% lit · day \(Int(astro.moon.ageDays.rounded())) · Moon in \(astro.moon.zodiacSign)")
                            .font(DS.label(11, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                    }
                    Spacer()
                }
                .editorialPanel(padding: 14)
                .padding(.bottom, 12)

                almanacRow("Sunrise", astro.sun.sunrise, symbol: "sunrise.fill")
                almanacRow("Sunset", astro.sun.sunset, symbol: "sunset.fill")
                almanacRow("Moonrise", astro.moon.moonrise, symbol: "moon.fill")
                almanacRow("Moonset", astro.moon.moonset, symbol: "moon.zzz.fill")
                Hairline()
            }
            .padding(.top, 24)
        }
    }

    private func almanacRow(_ label: String, _ date: Date?, symbol: String) -> some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.gold)
                    .frame(width: 24)
                Text(label)
                    .font(DS.label(13, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(date?.timeText() ?? "—")
                    .font(DS.display(15))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
            }
            .padding(.vertical, 9)
        }
    }

    // MARK: Tonight's planets

    @ViewBuilder
    private var planetsSection: some View {
        if let astro = app.astro {
            VStack(alignment: .leading, spacing: 0) {
                SectionRuleHeader(title: "Tonight's Sky")
                    .padding(.bottom, 6)
                ForEach(astro.planets) { planet in
                    VStack(spacing: 0) {
                        Hairline()
                        HStack(spacing: 10) {
                            Circle()
                                .fill(planet.visibleTonight ? Palette.coral : Palette.paperDeep)
                                .frame(width: 7, height: 7)
                            Text(planet.name)
                                .font(DS.label(13, weight: planet.visibleTonight ? .bold : .medium))
                                .foregroundStyle(planet.visibleTonight ? Palette.ink : Palette.muted)
                            Spacer()
                            Text(planet.note)
                                .font(DS.label(11, weight: .semibold))
                                .foregroundStyle(planet.visibleTonight ? Palette.ink : Palette.subtle)
                        }
                        .padding(.vertical, 9)
                    }
                }
                Hairline()
            }
            .padding(.top, 24)
        }
    }

    // MARK: Astrology desk

    @ViewBuilder
    private var astrologySection: some View {
        if let astro = app.astro {
            VStack(alignment: .leading, spacing: 0) {
                SectionRuleHeader(title: "The Astrology Desk")
                    .padding(.bottom, 12)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("TAURUS · APRIL 21")
                            .kickerStyle(Palette.coral, size: 9, tracking: 1.4)
                        Spacer()
                        if astro.mercuryRetrograde {
                            StatusChip(text: "Mercury Rx", foreground: Palette.coral, background: Palette.coralSoft)
                        }
                    }
                    Text("Sun in \(astro.sunSign) · Moon in \(astro.moon.zodiacSign)\(astro.mercuryRetrograde ? " · Mercury retrograde" : "")")
                        .font(DS.label(12, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(app.aiHoroscope ?? dailyHoroscopePlaceholder(astro))
                        .font(DS.deck(14))
                        .foregroundStyle(app.aiHoroscope == nil ? Palette.muted : Palette.ink)
                        .lineSpacing(3)
                    if AIService.isConfigured {
                        Button {
                            app.runHoroscope()
                        } label: {
                            if app.aiBusy.contains("horoscope") {
                                ProgressView().controlSize(.small)
                            } else {
                                Text(app.aiHoroscope == nil ? "WRITE TODAY'S HOROSCOPE" : "REWRITE")
                                    .kickerStyle(Palette.ink, size: 9, tracking: 1.2)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(app.aiBusy.contains("horoscope"))
                    }
                }
                .inkPanel(padding: 15)
            }
            .padding(.top, 24)
        }
    }

    /// Computed-transit reading until the AI horoscope desk comes online.
    private func dailyHoroscopePlaceholder(_ astro: AstroSnapshot) -> String {
        var lines: [String] = []
        if astro.moon.zodiacSign == "Taurus" {
            lines.append("The Moon is in your sign — energy runs closer to the surface than usual.")
        } else {
            lines.append("With the Moon in \(astro.moon.zodiacSign), the day favors \(moonMood(astro.moon.zodiacSign)).")
        }
        if astro.mercuryRetrograde {
            lines.append("Mercury is retrograde: reread before sending, confirm times, and be patient with logistics.")
        }
        return lines.joined(separator: " ")
    }

    private func moonMood(_ sign: String) -> String {
        switch sign {
        case "Aries": return "quick starts over long deliberation"
        case "Gemini": return "conversation, errands, and short-form work"
        case "Cancer": return "home matters and close company"
        case "Leo": return "visible work — share what you've made"
        case "Virgo": return "details, lists, and cleanup"
        case "Libra": return "negotiation and balance"
        case "Scorpio": return "focus and finishing what's unresolved"
        case "Sagittarius": return "planning beyond this week"
        case "Capricorn": return "steady, structural progress"
        case "Aquarius": return "the unconventional route"
        case "Pisces": return "rest and creative drift"
        default: return "steady, grounded effort"
        }
    }
}
