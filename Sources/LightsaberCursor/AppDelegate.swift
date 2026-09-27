import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    private(set) var engine: CursorEngine!
    private var statusMenu: StatusMenuController!
    private var hotKey: HotKey?
    private var customizer: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        engine = CursorEngine(settings: settings)
        statusMenu = StatusMenuController(settings: settings, engine: engine) { [weak self] in self?.showCustomizer() }
        hotKey = HotKey.toggleShortcut { [weak self] in self?.settings.prefs.enabled.toggle() }
        if settings.prefs.enabled { engine.start() }

        let firstLaunchKey = "hasLaunched"
        if !UserDefaults.standard.bool(forKey: firstLaunchKey) {
            UserDefaults.standard.set(true, forKey: firstLaunchKey)
            showCustomizer()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showCustomizer()
        return true
    }

    func showCustomizer() {
        if customizer == nil {
            let host = NSHostingController(rootView: CustomizerView(settings: settings, engine: engine))
            let w = NSWindow(contentViewController: host)
            w.title = "Lightsaber Cursor"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 980, height: 680))
            w.isReleasedWhenClosed = false
            w.center()
            customizer = w
        }
        NSApp.activate(ignoringOtherApps: true)
        customizer?.makeKeyAndOrderFront(nil)
    }
}

final class StatusMenuController: NSObject, NSMenuDelegate {
    private static let autosaveName = "LightsaberCursorStatusItem"

    /// New status items land at the far left of the status area, which sits under the notch on MacBooks;
    /// seed a position (points from the right screen edge) near Control Center once. ⌘-drag still overrides it.
    private static func seedPosition() {
        let d = UserDefaults.standard
        let flag = "statusItemPositionSeeded.v2"
        guard !d.bool(forKey: flag) else { return }
        d.set(true, forKey: flag)
        // Between Now Playing (455) and Focus (395) so it stays right of the notch.
        d.set(Double(425), forKey: "NSStatusItem Preferred Position \(autosaveName)")
    }

    private let item: NSStatusItem = {
        StatusMenuController.seedPosition()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = StatusMenuController.autosaveName
        item.isVisible = true
        return item
    }()
    private let settings: AppSettings
    private let engine: CursorEngine
    private let openCustomizer: () -> Void

    init(settings: AppSettings, engine: CursorEngine, openCustomizer: @escaping () -> Void) {
        self.settings = settings
        self.engine = engine
        self.openCustomizer = openCustomizer
        super.init()
        item.button?.image = Self.icon()
        item.button?.toolTip = "Lightsaber Cursor"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    static func icon() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let blade = NSBezierPath()
            blade.lineWidth = 1.8
            blade.lineCapStyle = .round
            blade.move(to: NSPoint(x: 7.2, y: 7.2))
            blade.line(to: NSPoint(x: 15.5, y: 15.5))
            NSColor.black.setStroke()
            blade.stroke()
            let hilt = NSBezierPath()
            hilt.lineWidth = 3.4
            hilt.lineCapStyle = .butt
            hilt.move(to: NSPoint(x: 2.2, y: 2.2))
            hilt.line(to: NSPoint(x: 6.6, y: 6.6))
            hilt.stroke()
            let guardBar = NSBezierPath()
            guardBar.lineWidth = 1.2
            guardBar.move(to: NSPoint(x: 4.6, y: 8.2))
            guardBar.line(to: NSPoint(x: 8.2, y: 4.6))
            guardBar.stroke()
            return true
        }
        img.isTemplate = true
        return img
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let p = settings.prefs

        let toggle = NSMenuItem(title: "Lightsaber Cursor", action: #selector(toggleEnabled), keyEquivalent: "l")
        toggle.keyEquivalentModifierMask = [.control, .option, .command]
        toggle.state = p.enabled ? .on : .off
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())

        let now = NSMenuItem(title: "Now: \(engine.activeDescription.isEmpty ? p.saber.name : engine.activeDescription)", action: nil, keyEquivalent: "")
        now.isEnabled = false
        menu.addItem(now)

        let presets = NSMenuItem(title: "Sabers", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for f in Faction.allCases {
            sub.addItem(NSMenuItem.sectionHeader(title: f.displayName))
            for s in Presets.all where s.faction == f { sub.addItem(saberItem(s, current: p.saber.id)) }
        }
        if !p.customSabers.isEmpty {
            sub.addItem(NSMenuItem.sectionHeader(title: "My Sabers"))
            for s in p.customSabers { sub.addItem(saberItem(s, current: p.saber.id)) }
        }
        presets.submenu = sub
        menu.addItem(presets)
        menu.addItem(action("Randomize", #selector(randomize), key: "r"))
        menu.addItem(.separator())

        menu.addItem(check("Retract When Idle", p.retractWhenIdle, #selector(toggleRetract)))
        menu.addItem(check("Click Spark", p.clickSpark, #selector(toggleSpark)))
        menu.addItem(check("Motion Trail", p.motionTrail, #selector(toggleTrail)))
        menu.addItem(check("After-Dark Switch", p.afterDark, #selector(toggleAfterDark)))
        menu.addItem(check("Per-App Sabers", p.perApp, #selector(togglePerApp)))
        menu.addItem(check("Randomize on Re-ignite", p.randomOnIgnite, #selector(toggleRandomIgnite)))
        menu.addItem(check("Sounds", p.soundEnabled, #selector(toggleSounds)))
        menu.addItem(.separator())

        menu.addItem(action("Customize…", #selector(customize), key: ","))
        menu.addItem(.separator())
        menu.addItem(action("Quit Lightsaber Cursor", #selector(quit), key: "q"))
    }

    private func saberItem(_ s: SaberConfig, current: String) -> NSMenuItem {
        let mi = NSMenuItem(title: s.name, action: #selector(pickSaber(_:)), keyEquivalent: "")
        mi.target = self
        mi.representedObject = s.id
        mi.state = s.id == current ? .on : .off
        let dot = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { r in
            (s.bladeStyle == .darksaber ? NSColor.black : NSColor(cgColor: s.blade.cg()) ?? .white).setFill()
            NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)).fill()
            NSColor.gray.setStroke()
            NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)).stroke()
            return true
        }
        mi.image = dot
        return mi
    }

    private func action(_ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        mi.target = self
        return mi
    }

    private func check(_ title: String, _ on: Bool, _ sel: Selector) -> NSMenuItem {
        let mi = action(title, sel)
        mi.state = on ? .on : .off
        return mi
    }

    @objc private func toggleEnabled() { settings.prefs.enabled.toggle() }
    @objc private func randomize() { settings.randomize() }
    @objc private func toggleRetract() { settings.prefs.retractWhenIdle.toggle() }
    @objc private func toggleSpark() { settings.prefs.clickSpark.toggle() }
    @objc private func toggleTrail() { settings.prefs.motionTrail.toggle() }
    @objc private func toggleAfterDark() { settings.prefs.afterDark.toggle() }
    @objc private func togglePerApp() { settings.prefs.perApp.toggle() }
    @objc private func toggleRandomIgnite() { settings.prefs.randomOnIgnite.toggle() }
    @objc private func toggleSounds() { settings.prefs.soundEnabled.toggle() }
    @objc private func customize() { openCustomizer() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func pickSaber(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let s = settings.allSabers.first(where: { $0.id == id }) else { return }
        settings.prefs.saber = s
    }
}
