//
//  Theme.swift
//  Daymark
//
//  The Daymark editorial design language: warm paper, ink, one coral accent,
//  Fraunces display serif + Newsreader deck italic (system serif fallback).
//

import SwiftUI
import UIKit
import CoreText

// MARK: - Palette

enum Palette {
    // The Daily × Scoreboard system: white ground, ink, one disciplined red.
    // Red always means "now" — live dots, NOW markers, leave-by, the focus spine.
    // Every color carries a night-edition variant; the scheme flips with
    // the sun (or the Appearance setting), and these adapt automatically.
    static let paper = Color(light: 0xFDFDFC, dark: 0x131311)
    static let paperDeep = Color(light: 0xF0EFEC, dark: 0x26251F)
    static let card = Color(light: 0xFFFFFF, dark: 0x1D1C19)
    static let wash = Color(light: 0xF8F7F5, dark: 0x21201C)
    static let ink = Color(light: 0x141412, dark: 0xEDEBE4)
    static let muted = Color(light: 0x75726C, dark: 0xA5A297)
    static let subtle = Color(light: 0x8A877F, dark: 0x807D73)
    static let line = Color(light: 0xE8E6E1, dark: 0x2F2E29)
    static let coral = Color(light: 0xC8102E, dark: 0xE53B54)
    static let coralSoft = Color(light: 0xFBEDEF, dark: 0x3A1B21)
    static let blue = Color(light: 0x1D6FE0, dark: 0x5E9CF0)
    static let blueSoft = Color(light: 0xEFF4FF, dark: 0x1B2536)
    static let acid = Color(light: 0xF8F7F5, dark: 0x21201C)   // retired slab color, now the quiet wash
    static let acidInk = Color(light: 0x141412, dark: 0xEDEBE4)
    static let green = Color(light: 0x0E9F6E, dark: 0x30BF8B)
    static let greenSoft = Color(light: 0xE9F7F1, dark: 0x152E25)
    static let down = Color(light: 0xDC2626, dark: 0xF25C5C)   // market direction only — never brand
    static let violet = Color(light: 0x6B4FA3, dark: 0x9C7FD6)
    static let gold = Color(light: 0xB98A1F, dark: 0xD4A83E)

    /// Hairline rules, per the newspaper system.
    static let hairline = ink.opacity(0.14)
    static let hairlineSoft = ink.opacity(0.09)
}

extension Color {
    /// A trait-adaptive color: one hex for the day paper, one for the
    /// night edition.
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { trait in
            UIColor(Color(hex: trait.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

// MARK: - Day phase

enum DayPhase: String, CaseIterable {
    case morning, afternoon, evening, night

    static func current(_ date: Date = Date()) -> DayPhase {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<21: return .evening
        default: return .night
        }
    }

    var accent: Color {
        // One disciplined red across every phase — red is the brand and the "now."
        Palette.coral
    }

    var label: String {
        switch self {
        case .morning: return "Morning edition"
        case .afternoon: return "Midday edition"
        case .evening: return "Evening edition"
        case .night: return "Late edition"
        }
    }

    var greetingWord: String {
        switch self {
        case .morning: return "Good morning"
        case .afternoon: return "Good afternoon"
        case .evening: return "Good evening"
        case .night: return "Good evening"
        }
    }

    var sectionTag: String {
        switch self {
        case .morning: return "Morning Brief"
        case .afternoon: return "Midday Edition"
        case .evening: return "Evening Edition"
        case .night: return "The Late Edition"
        }
    }

    var isEndOfDay: Bool { self == .evening || self == .night }
}

// MARK: - Type system

enum DS {
    // Resolved once; nil when the bundled variable fonts are unavailable,
    // in which case everything falls back to the system serif (New York).
    private static let fraunces = resolve(familyPrefix: "Fraunces", italic: false)
    private static let frauncesItalic = resolve(familyPrefix: "Fraunces", italic: true)
    private static let newsreader = resolve(familyPrefix: "Newsreader", italic: false)
    private static let newsreaderItalic = resolve(familyPrefix: "Newsreader", italic: true)

    /// Display serif (mastheads, headlines). weight in variable-axis units (400 = regular).
    static func display(_ size: CGFloat, weight: Double = 400, italic: Bool = false) -> Font {
        if let name = italic ? frauncesItalic : fraunces {
            return Font(variable(
                name: name, size: size,
                axes: [
                    "wght": weight,
                    "opsz": min(max(Double(size), 9), 144),
                    "SOFT": 0,
                    "WONK": 0,
                ]
            ))
        }
        var font = Font.system(size: size, weight: systemWeight(weight), design: .serif)
        if italic { font = font.italic() }
        return font
    }

    /// Editorial deck / running serif (Newsreader).
    static func deck(_ size: CGFloat, weight: Double = 400, italic: Bool = true) -> Font {
        if let name = italic ? newsreaderItalic : newsreader {
            return Font(variable(
                name: name, size: size,
                axes: ["wght": weight, "opsz": min(max(Double(size), 6), 72)]
            ))
        }
        var font = Font.system(size: size, weight: systemWeight(weight), design: .serif)
        if italic { font = font.italic() }
        return font
    }

    /// Sans caption/kicker face (system, matching the prototype's system-ui usage).
    static func kicker(_ size: CGFloat = 10) -> Font { .system(size: size, weight: .heavy) }
    static func label(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    // MARK: private

    private static func systemWeight(_ axis: Double) -> Font.Weight {
        switch axis {
        case ..<350: return .light
        case ..<450: return .regular
        case ..<550: return .medium
        case ..<650: return .semibold
        case ..<750: return .bold
        default: return .black
        }
    }

    private static func variable(name: String, size: CGFloat, axes: [String: Double]) -> CTFont {
        var variations: [NSNumber: NSNumber] = [:]
        for (tag, value) in axes {
            var code: UInt32 = 0
            for byte in tag.utf8 { code = (code << 8) | UInt32(byte) }
            variations[NSNumber(value: code)] = NSNumber(value: value)
        }
        let attributes: [CFString: Any] = [
            kCTFontNameAttribute: name,
            kCTFontVariationAttribute: variations,
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    private static func resolve(familyPrefix: String, italic: Bool) -> String? {
        for family in UIFont.familyNames where family.hasPrefix(familyPrefix) {
            let names = UIFont.fontNames(forFamilyName: family)
            if let match = names.first(where: { $0.lowercased().contains("italic") == italic }) {
                return match
            }
        }
        return nil
    }
}

// MARK: - Text style helpers

extension Text {
    /// Coral/muted smallcaps kicker line.
    func kickerStyle(_ color: Color = Palette.coral, size: CGFloat = 10, tracking: CGFloat = 1.4) -> some View {
        self.font(DS.kicker(size)).tracking(tracking).foregroundStyle(color)
    }
}

extension View {
    /// Elevated editorial card: white ground, hairline border, soft lift.
    func editorialPanel(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line, lineWidth: 1))
            .shadow(color: Palette.ink.opacity(0.05), radius: 8, y: 3)
            .shadow(color: Palette.ink.opacity(0.03), radius: 1, y: 1)
    }

    /// The bulletin panel (NOW · FOCUS, evening review): quiet wash with a red spine.
    func inkPanel(padding: CGFloat = 17) -> some View {
        self.padding(padding)
            .foregroundStyle(Palette.ink)
            .background(Palette.wash)
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: 0,
                bottomTrailingRadius: 12, topTrailingRadius: 12))
            .overlay(alignment: .leading) {
                Rectangle().fill(Palette.coral).frame(width: 3)
            }
    }
}
