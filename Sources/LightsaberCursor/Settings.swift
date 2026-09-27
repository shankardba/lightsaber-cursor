import AppKit
import Combine

enum AfterDarkMode: String, Codable, CaseIterable, Identifiable {
    case systemAppearance, hours
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .systemAppearance: "Follow macOS Dark Mode"
        case .hours: "Set hours"
        }
    }
}

struct AppRule: Codable, Equatable, Identifiable {
    var id = UUID()
    var bundleID: String
    var appName: String
    var saber: SaberConfig
}

struct Prefs: Codable, Equatable {
    var enabled = true
    var saber: SaberConfig = Presets.defaultSaber
    var customSabers: [SaberConfig] = []
    var scale: Double = 0.8

    var retractWhenIdle = true
    var idleSeconds: Double = 4
    var hoverGlow = true
    var clickSpark = true
    var motionTrail = true

    var afterDark = false
    var afterDarkMode: AfterDarkMode = .systemAppearance
    var nightStart = 19
    var nightEnd = 7
    var nightSaber: SaberConfig = Presets.vader

    var perApp = false
    var appRules: [AppRule] = []

    var randomHilt = true
    var randomColor = true
    var randomSide: RandomSide = .any
    var randomOnIgnite = false
}

final class AppSettings: ObservableObject {
    private static let key = "prefs.v1"

    @Published var prefs: Prefs {
        didSet { if prefs != oldValue { save() } }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let p = try? JSONDecoder().decode(Prefs.self, from: data) {
            prefs = p
        } else {
            prefs = Prefs()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    var allSabers: [SaberConfig] { Presets.all + prefs.customSabers }

    func randomize() {
        prefs.saber = Randomizer.make(from: prefs.saber, hilt: prefs.randomHilt, color: prefs.randomColor, side: prefs.randomSide)
    }

    func saveCustom(named name: String) {
        var c = prefs.saber
        c.name = name.isEmpty ? c.name : name
        c.id = "custom.\(UUID().uuidString)"
        prefs.customSabers.append(c)
        prefs.saber = c
    }

    func updateCustom() {
        guard let i = prefs.customSabers.firstIndex(where: { $0.id == prefs.saber.id }) else { return }
        prefs.customSabers[i] = prefs.saber
    }

    func deleteCustom(_ id: String) {
        prefs.customSabers.removeAll { $0.id == id }
    }

    func isNight(_ date: Date = Date()) -> Bool {
        switch prefs.afterDarkMode {
        case .systemAppearance:
            return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        case .hours:
            let h = Calendar.current.component(.hour, from: date)
            let s = prefs.nightStart
            let e = prefs.nightEnd
            if s == e { return false }
            return s > e ? (h >= s || h < e) : (h >= s && h < e)
        }
    }
}
