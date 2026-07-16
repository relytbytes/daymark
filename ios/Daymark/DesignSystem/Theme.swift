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
    static let paper = Color(hex: 0xFDFDFC)
    static let paperDeep = Color(hex: 0xF0EFEC)
    static let card = Color(hex: 0xFFFFFF)
    static let wash = Color(hex: 0xF8F7F5)
    static let ink = Color(hex: 0x141412)
    static let muted = Color(hex: 0x75726C)
    static let subtle = Color(hex: 0x8A877F)
    static let line = Color(hex: 0xE8E6E1)
    static let coral = Color(hex: 0xC8102E)
    static let coralSoft = Color(hex: 0xFBEDEF)
    static let blue = Color(hex: 0x1D6FE0)
    static let blueSoft = Color(hex: 0xEFF4FF)
    static let acid = Color(hex: 0xF8F7F5)      // retired slab color, now the quiet wash
    static let acidInk = Color(hex: 0x141412)
    static let green = Color(hex: 0x0E9F6E)
    static let greenSoft = Color(hex: 0xE9F7F1)
    static let down = Color(hex: 0xDC2626)      // market direction only — never brand
    static let violet = Color(hex: 0x6B4FA3)
    static let gold = Color(hex: 0xB98A1F)

    /// Hairline rules, per the newspaper system.
    static let hairline = ink.opacity(0.14)
    static let hairlineSoft = ink.opacity(0.09)
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
