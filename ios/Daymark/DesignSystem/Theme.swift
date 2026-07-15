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
    static let paper = Color(hex: 0xF3F0E8)
    static let paperDeep = Color(hex: 0xE7E2D7)
    static let card = Color(hex: 0xFBFAF6)
    static let ink = Color(hex: 0x181A1C)
    static let muted = Color(hex: 0x73736D)
    static let subtle = Color(hex: 0x8A897F)
    static let line = Color(hex: 0xD8D3C9)
    static let coral = Color(hex: 0xFF603D)
    static let coralSoft = Color(hex: 0xFFD8CD)
    static let blue = Color(hex: 0x3155E7)
    static let blueSoft = Color(hex: 0xDCE3FF)
    static let acid = Color(hex: 0xDFFD61)
    static let acidInk = Color(hex: 0x3A3F16)
    static let green = Color(hex: 0x3D8B68)
    static let violet = Color(hex: 0x8C66D9)
    static let gold = Color(hex: 0xD8A52B)

    /// Hairline rules, per the newspaper system.
    static let hairline = ink.opacity(0.16)
    static let hairlineSoft = ink.opacity(0.12)
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
        switch self {
        case .morning: return Palette.coral
        case .afternoon: return Palette.blue
        case .evening: return Palette.violet
        case .night: return Palette.acid
        }
    }

    var label: String {
        switch self {
        case .morning: return "Plan the day"
        case .afternoon: return "Protect the middle"
        case .evening: return "Land the day"
        case .night: return "You are done"
        }
    }

    var greetingWord: String {
        switch self {
        case .morning: return "Good morning"
        case .afternoon: return "Good afternoon"
        case .evening: return "Good evening"
        case .night: return "Winding down"
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
    /// Sharp-cornered editorial panel: card ground with a hairline ink border.
    func editorialPanel(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(Palette.card)
            .overlay(Rectangle().stroke(Palette.hairline, lineWidth: 1))
    }

    /// The ink bulletin box (dark panel used for NOW · FOCUS, box scores).
    func inkPanel(padding: CGFloat = 17) -> some View {
        self.padding(padding)
            .background(Palette.ink)
            .foregroundStyle(.white)
    }
}
