import AppKit
import SwiftUI

struct RGB: Codable, Equatable, Hashable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(hex: UInt32) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    init(_ color: Color) {
        let n = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(Double(n.redComponent), Double(n.greenComponent), Double(n.blueComponent))
    }

    static let white = RGB(1, 1, 1)
    static let black = RGB(0, 0, 0)

    func cg(_ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: alpha)
    }

    func mix(_ o: RGB, _ t: Double) -> RGB {
        RGB(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t)
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
}

enum Faction: String, Codable, CaseIterable, Identifiable {
    case jedi, sith, grey
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .jedi: "Jedi"
        case .sith: "Sith & Dark Side"
        case .grey: "Grey & Other"
        }
    }
    var shortName: String {
        switch self {
        case .jedi: "Jedi"
        case .sith: "Sith"
        case .grey: "Grey"
        }
    }
}

enum HiltStyle: String, Codable, CaseIterable, Identifiable {
    case classic, ribbed, slim, curved, crossguard, shoto, jagged, angular, ornate, banded, worn, inquisitor, staff, clawed, darksaber
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .classic: "Classic"
        case .ribbed: "Ribbed"
        case .slim: "Slim"
        case .curved: "Curved"
        case .crossguard: "Crossguard"
        case .shoto: "Shoto"
        case .jagged: "Jagged"
        case .angular: "Angular"
        case .ornate: "Ornate"
        case .banded: "Banded"
        case .worn: "Worn"
        case .inquisitor: "Inquisitor"
        case .staff: "Staff"
        case .clawed: "Clawed"
        case .darksaber: "Darksaber"
        }
    }
    var length: CGFloat {
        switch self {
        case .classic: 25.5
        case .ribbed: 25
        case .slim: 27
        case .curved: 25
        case .crossguard: 22
        case .shoto: 16
        case .jagged: 25
        case .angular: 23.2
        case .ornate: 24
        case .banded: 20.2
        case .worn: 23.6
        case .inquisitor: 16
        case .staff: 33.4
        case .clawed: 25
        case .darksaber: 22.2
        }
    }
}

enum HiltFinish: String, Codable, CaseIterable, Identifiable {
    case silver, black, gunmetal, brass, bronze, white
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
    var base: RGB {
        switch self {
        case .silver: RGB(hex: 0xB8BCC4)
        case .black: RGB(hex: 0x2A2B2F)
        case .gunmetal: RGB(hex: 0x5B6068)
        case .brass: RGB(hex: 0xB8923A)
        case .bronze: RGB(hex: 0x9C6A3C)
        case .white: RGB(hex: 0xE4E2DC)
        }
    }
    var light: RGB {
        switch self {
        case .silver: RGB(hex: 0xF4F6F9)
        case .black: RGB(hex: 0x74767D)
        case .gunmetal: RGB(hex: 0xA8AEB6)
        case .brass: RGB(hex: 0xF3D98F)
        case .bronze: RGB(hex: 0xDDAA78)
        case .white: RGB(hex: 0xFFFFFF)
        }
    }
    var dark: RGB {
        switch self {
        case .silver: RGB(hex: 0x575C65)
        case .black: RGB(hex: 0x0C0C0E)
        case .gunmetal: RGB(hex: 0x272A2F)
        case .brass: RGB(hex: 0x664A14)
        case .bronze: RGB(hex: 0x4A2E17)
        case .white: RGB(hex: 0x96938B)
        }
    }
    /// Contrasting finish used for secondary hilt sections.
    var alt: HiltFinish {
        switch self {
        case .silver: .black
        case .black: .silver
        case .gunmetal: .silver
        case .brass: .black
        case .bronze: .black
        case .white: .gunmetal
        }
    }
}

enum BladeStyle: String, Codable, CaseIterable, Identifiable {
    case standard, unstable, darksaber
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .standard: "Standard"
        case .unstable: "Unstable"
        case .darksaber: "Darksaber"
        }
    }
}

struct SaberConfig: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var name: String
    var faction: Faction
    var hilt: HiltStyle
    var finish: HiltFinish
    var accent: RGB
    var blade: RGB
    var bladeStyle: BladeStyle = .standard
    var coreWhiteness: Double = 0.8
    var bladeLength: Double = 1
    var thickness: Double = 1
    var glowRadius: Double = 1
    var glowIntensity: Double = 1
    var animated: Bool = false
}

enum BladeColors {
    static let swatches: [(String, RGB)] = [
        ("Blue", RGB(hex: 0x3D8BFF)),
        ("Sky", RGB(hex: 0x4DC3FF)),
        ("Green", RGB(hex: 0x39FF4F)),
        ("Lime", RGB(hex: 0x9BFF2E)),
        ("Yellow", RGB(hex: 0xFFD93B)),
        ("Orange", RGB(hex: 0xFF8A1F)),
        ("Red", RGB(hex: 0xFF2323)),
        ("Crimson", RGB(hex: 0xD40A1E)),
        ("Magenta", RGB(hex: 0xFF2E9A)),
        ("Purple", RGB(hex: 0xB44DFF)),
        ("Cyan", RGB(hex: 0x2EF2F2)),
        ("White", RGB(hex: 0xEEF4FF)),
    ]
    static let jedi: [RGB] = [
        RGB(hex: 0x3D8BFF), RGB(hex: 0x4DA6FF), RGB(hex: 0x39FF4F), RGB(hex: 0x6CFF3A),
        RGB(hex: 0xB44DFF), RGB(hex: 0xFFD93B), RGB(hex: 0x2EF2F2), RGB(hex: 0xEEF4FF),
    ]
    static let sith: [RGB] = [
        RGB(hex: 0xFF2323), RGB(hex: 0xD40A1E), RGB(hex: 0xFF4A12), RGB(hex: 0xE00A4A),
    ]
    static let grey: [RGB] = [
        RGB(hex: 0xFF8A1F), RGB(hex: 0xEEF4FF), RGB(hex: 0xFFD93B), RGB(hex: 0xFF2E9A),
    ]
}

enum Presets {
    private static func p(
        _ name: String, _ faction: Faction, _ hilt: HiltStyle, _ finish: HiltFinish,
        accent: UInt32, blade: UInt32, style: BladeStyle = .standard, animated: Bool = false,
        core: Double = 0.8, length: Double = 1, thickness: Double = 1, glow: Double = 1
    ) -> SaberConfig {
        let slug = name.lowercased().filter { $0.isLetter || $0.isNumber }
        return SaberConfig(
            id: "preset.\(slug)", name: name, faction: faction, hilt: hilt, finish: finish,
            accent: RGB(hex: accent), blade: RGB(hex: blade), bladeStyle: style,
            coreWhiteness: core, bladeLength: length, thickness: thickness,
            glowRadius: glow, glowIntensity: 1, animated: animated)
    }

    static let obiWan = p("Obi-Wan Kenobi", .jedi, .slim, .silver, accent: 0x222222, blade: 0x4DA6FF, animated: true)
    static let vader = p("Darth Vader", .sith, .ribbed, .black, accent: 0xE0332B, blade: 0xFF2323, animated: true)

    static let all: [SaberConfig] = [
        p("Anakin Skywalker", .jedi, .classic, .silver, accent: 0xE0332B, blade: 0x3D8BFF),
        obiWan,
        p("Luke Skywalker (Return of the Jedi)", .jedi, .slim, .black, accent: 0xC8CCD2, blade: 0x3CFF52),
        p("Luke Skywalker (Empire Strikes Back)", .jedi, .classic, .silver, accent: 0xE0332B, blade: 0x3A86FF),
        p("Rey Skywalker", .jedi, .banded, .bronze, accent: 0xC89B3C, blade: 0xFFD93B, length: 0.9),
        p("Aayla Secura", .jedi, .classic, .gunmetal, accent: 0x2F7BFF, blade: 0x2F7BFF, animated: true),
        p("Ahsoka Tano (Clone Wars)", .jedi, .ornate, .silver, accent: 0x1C1C1C, blade: 0x7CFF3A, animated: true),
        p("Yoda", .jedi, .shoto, .silver, accent: 0x1C1C1C, blade: 0x5CFF5C, length: 0.72),
        p("Mace Windu", .jedi, .ornate, .brass, accent: 0x2A2A2A, blade: 0xB44DFF),
        p("Qui-Gon Jinn", .jedi, .slim, .black, accent: 0xC8CCD2, blade: 0x57FF2E),
        p("Kanan Jarrus", .jedi, .slim, .gunmetal, accent: 0x8A6A40, blade: 0x3F9BFF),
        p("Ezra Bridger", .jedi, .classic, .gunmetal, accent: 0x2FAF6A, blade: 0x4CFF6B),
        p("Kit Fisto", .jedi, .slim, .silver, accent: 0x2FAF6A, blade: 0x3CFF6A),
        p("Luminara Unduli", .jedi, .curved, .silver, accent: 0x2F6F5A, blade: 0x4CFF4C),
        p("Plo Koon", .jedi, .classic, .gunmetal, accent: 0xB05A2A, blade: 0x3D8BFF),
        p("Shaak Ti", .jedi, .ornate, .silver, accent: 0xC04040, blade: 0x3FA0FF),
        p("Ki-Adi-Mundi", .jedi, .slim, .gunmetal, accent: 0x8A6A40, blade: 0x3A7FFF),
        p("Cal Kestis (Blue)", .jedi, .classic, .gunmetal, accent: 0xC06A20, blade: 0x3D9BFF, animated: true),
        p("Cal Kestis (Orange)", .jedi, .classic, .gunmetal, accent: 0xC06A20, blade: 0xFF8A1F, animated: true),
        p("Leia Organa", .jedi, .banded, .silver, accent: 0x2F7BFF, blade: 0x4D9BFF),
        p("Ben Solo", .jedi, .classic, .silver, accent: 0xE0332B, blade: 0x3D8BFF),
        p("Blue Lightsaber", .jedi, .classic, .silver, accent: 0x3D8BFF, blade: 0x3D8BFF, animated: true),

        vader,
        p("Darth Nihilus", .sith, .jagged, .black, accent: 0xB0101A, blade: 0xD40A1E, animated: true, core: 0.6),
        p("Kylo Ren", .sith, .crossguard, .gunmetal, accent: 0x3A3A3A, blade: 0xFF1A10, style: .unstable, animated: true, core: 0.65, thickness: 1.15),
        p("Count Dooku", .sith, .curved, .black, accent: 0xD9B04C, blade: 0xFF2A2A),
        p("Darth Sidious", .sith, .ornate, .silver, accent: 0xD9B04C, blade: 0xFF2323, animated: true),
        p("Marrok", .sith, .worn, .gunmetal, accent: 0xB0201A, blade: 0xFF3B1F, animated: true),
        p("Shin Hati", .sith, .angular, .black, accent: 0xC04020, blade: 0xFF5418),
        p("Darth Maul", .sith, .staff, .black, accent: 0xC8CCD2, blade: 0xFF1E1E, animated: true),
        p("Savage Opress", .sith, .staff, .gunmetal, accent: 0x9C6A3C, blade: 0xFF2A2A),
        p("Asajj Ventress", .sith, .curved, .gunmetal, accent: 0xC8CCD2, blade: 0xFF2A2A),
        p("Grand Inquisitor", .sith, .inquisitor, .black, accent: 0xE0332B, blade: 0xFF2323, animated: true),
        p("Second Sister", .sith, .inquisitor, .black, accent: 0xC8CCD2, blade: 0xFF2A2A, animated: true),
        p("Reva (Third Sister)", .sith, .inquisitor, .gunmetal, accent: 0xB0201A, blade: 0xFF1A10, animated: true),
        p("Starkiller", .sith, .worn, .gunmetal, accent: 0xE0332B, blade: 0xFF2323, animated: true),
        p("Darth Revan", .sith, .clawed, .black, accent: 0x8A2BE2, blade: 0xFF2323, animated: true),

        p("Ahsoka Tano (White)", .grey, .ornate, .white, accent: 0x2A2A2A, blade: 0xEEF4FF, animated: true),
        p("Sabine Wren (Darksaber)", .grey, .darksaber, .silver, accent: 0xC0302A, blade: 0x0A0A0C, style: .darksaber, animated: true),
        p("Din Djarin (Darksaber)", .grey, .darksaber, .gunmetal, accent: 0xC0302A, blade: 0x0A0A0C, style: .darksaber, animated: true),
        p("Baylan Skoll", .grey, .angular, .gunmetal, accent: 0xD9B04C, blade: 0xFF7A18, thickness: 1.15),
        p("Mara Jade", .grey, .slim, .silver, accent: 0xB02070, blade: 0xFF2E9A),
        p("Revan (Jedi)", .grey, .clawed, .gunmetal, accent: 0x6A4EB0, blade: 0xA24DFF, animated: true),
        p("Starkiller (Redeemed)", .grey, .worn, .gunmetal, accent: 0x2F7BFF, blade: 0x3D8BFF, animated: true),
    ]

    static let defaultSaber = obiWan
}

enum RandomSide: String, Codable, CaseIterable, Identifiable {
    case any, jedi, sith
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .any: "Any"
        case .jedi: "Jedi"
        case .sith: "Sith"
        }
    }
}

enum Randomizer {
    static func make(from base: SaberConfig, hilt: Bool, color: Bool, side: RandomSide) -> SaberConfig {
        var c = base
        let faction: Faction
        switch side {
        case .jedi: faction = .jedi
        case .sith: faction = .sith
        case .any:
            let r = Double.random(in: 0..<1)
            faction = r < 0.4 ? .sith : (r < 0.52 ? .grey : .jedi)
        }
        if color {
            let palette = faction == .sith ? BladeColors.sith : (faction == .grey ? BladeColors.grey : BladeColors.jedi)
            let jitter = palette.randomElement()!.mix(palette.randomElement()!, Double.random(in: 0...0.25))
            c.blade = jitter
            c.bladeStyle = .standard
            if faction == .sith && Double.random(in: 0..<1) < 0.22 { c.bladeStyle = .unstable }
            if Double.random(in: 0..<1) < (faction == .grey ? 0.3 : 0.12) {
                c.bladeStyle = .darksaber
                c.blade = RGB(hex: 0x0A0A0C)
            }
            c.coreWhiteness = Double.random(in: 0.55...0.9)
            c.glowRadius = Double.random(in: 0.75...1.3)
            c.glowIntensity = Double.random(in: 0.85...1.2)
            c.animated = Bool.random()
        }
        if hilt {
            let sithHilts: [HiltStyle] = [.ribbed, .jagged, .curved, .crossguard, .angular, .worn, .ornate, .inquisitor, .staff, .clawed, .darksaber]
            let jediHilts: [HiltStyle] = [.classic, .slim, .shoto, .ornate, .banded, .worn, .angular, .curved, .clawed, .darksaber]
            c.hilt = (faction == .sith ? sithHilts : jediHilts).randomElement()!
            let finishes: [HiltFinish] = faction == .sith
                ? [.black, .black, .gunmetal, .silver, .brass]
                : HiltFinish.allCases
            c.finish = finishes.randomElement()!
            c.accent = [RGB(hex: 0xE0332B), RGB(hex: 0xD9B04C), RGB(hex: 0x1C1C1C), RGB(hex: 0xC8CCD2), RGB(hex: 0x2F7BFF), RGB(hex: 0x8A6A40)].randomElement()!
        }
        c.bladeLength = 1
        c.thickness = 1
        if hilt || color { c.faction = faction }
        c.name = name(for: c.faction)
        c.id = "random.\(UUID().uuidString)"
        return c
    }

    static func name(for faction: Faction) -> String {
        let a = ["Vor", "Kal", "Nyx", "Mal", "Sar", "Zan", "Tyr", "Dre", "Vex", "Mor", "Bael", "Xal"]
        let b = ["ius", "ax", "ora", "eth", "is", "ok", "anna", "yr", "os", "ul"]
        let first = ["Kel", "Aria", "Tavi", "Oren", "Lysa", "Bren", "Mira", "Dax", "Sela", "Jorin", "Vela", "Cade"]
        let last = ["Tavos", "Raan", "Kestar", "Ollin", "Venn", "Sarno", "Dray", "Ithor", "Marek", "Solen"]
        switch faction {
        case .sith: return "Darth " + a.randomElement()! + b.randomElement()!
        case .jedi: return "Jedi " + first.randomElement()! + " " + last.randomElement()!
        case .grey: return first.randomElement()! + " the Grey"
        }
    }
}
