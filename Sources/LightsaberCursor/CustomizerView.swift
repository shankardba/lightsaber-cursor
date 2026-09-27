import ServiceManagement
import SwiftUI

// MARK: Thumbnails

final class ThumbCache {
    static let shared = ThumbCache()
    private var store: [String: NSImage] = [:]

    func image(_ key: String, make: () -> RenderedImage?) -> NSImage? {
        if let img = store[key] { return img }
        guard let r = make() else { return nil }
        let img = NSImage(cgImage: r.image, size: r.size)
        if store.count > 400 { store.removeAll() }
        store[key] = img
        return img
    }
}

struct SaberThumb: View {
    let config: SaberConfig
    var height: CGFloat = 34

    var body: some View {
        let lay = SaberRenderer.layout(config, scale: 1, tight: true)
        let scale = height / lay.size.height
        let key = "saber|\(config.hashValue)|\(height)"
        if let img = ThumbCache.shared.image(key, make: {
            SaberRenderer.render(config, SaberState(ext: 1, glow: 0, time: 0.3), scale: scale, backing: 2, tight: true)
        }) {
            Image(nsImage: img).frame(width: lay.size.width * scale, height: height)
        }
    }
}

struct HiltThumb: View {
    let config: SaberConfig
    var height: CGFloat = 30

    var body: some View {
        let key = "hilt|\(config.hilt)|\(config.finish)|\(config.accent.hashValue)|\(height)"
        if let img = ThumbCache.shared.image(key, make: { SaberRenderer.renderHiltIcon(config, height: height, backing: 2) }) {
            Image(nsImage: img)
        }
    }
}

// MARK: Root

struct CustomizerView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var engine: CursorEngine

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(settings: settings, engine: engine)
            Divider()
            TabView {
                SaberTab(settings: settings)
                    .tabItem { Label("Saber", systemImage: "wand.and.rays") }
                BehaviorTab(settings: settings, engine: engine)
                    .tabItem { Label("Behavior", systemImage: "slider.horizontal.3") }
                AutoSwitchTab(settings: settings, engine: engine)
                    .tabItem { Label("Auto-Switch", systemImage: "moon.stars") }
            }
            .padding(12)
        }
        .frame(minWidth: 960, minHeight: 640)
    }
}

struct HeaderBar: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var engine: CursorEngine

    var body: some View {
        HStack(spacing: 16) {
            Toggle("Lightsaber cursor", isOn: $settings.prefs.enabled)
                .toggleStyle(.switch)
                .font(.headline)
            Text("Showing: \(engine.activeDescription.isEmpty ? settings.prefs.saber.name : engine.activeDescription)")
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if !engine.axTrusted {
                Label("Hover glow needs Accessibility access", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("Grant…") {
                    Accessibility.prompt()
                    Accessibility.openSettings()
                }
            }
            Text("Toggle: \(HotKey.displayString)").foregroundStyle(.secondary).font(.callout.monospaced())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: Saber tab

struct SaberTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PresetList(settings: settings).frame(width: 230)
            VStack(spacing: 12) {
                SaberPreview(config: settings.prefs.saber)
                TestStrip(idleSeconds: settings.prefs.idleSeconds, retract: settings.prefs.retractWhenIdle)
            }
            .frame(maxWidth: .infinity)
            ScrollView {
                EditorPanel(settings: settings).padding(.trailing, 8)
            }
            .frame(width: 300)
        }
    }
}

struct PresetList: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        List {
            ForEach(Faction.allCases) { f in
                Section(f.displayName) {
                    ForEach(Presets.all.filter { $0.faction == f }) { row($0) }
                }
            }
            if !settings.prefs.customSabers.isEmpty {
                Section("My Sabers") {
                    ForEach(settings.prefs.customSabers) { s in
                        row(s).contextMenu {
                            Button("Delete", role: .destructive) { settings.deleteCustom(s.id) }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ s: SaberConfig) -> some View {
        let selected = settings.prefs.saber.id == s.id
        return Button {
            settings.prefs.saber = s
        } label: {
            HStack(spacing: 8) {
                SaberThumb(config: s, height: 34).frame(width: 30)
                Text(s.name).lineLimit(2)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(selected ? Color.accentColor.opacity(0.22) : Color.clear)
    }
}

enum PreviewMode: String, CaseIterable, Identifiable {
    case live, extended, hover, retracted
    var id: String { rawValue }
    var title: String {
        switch self {
        case .live: "Live loop"
        case .extended: "Extended"
        case .hover: "Hover glow"
        case .retracted: "Retracted"
        }
    }

    func state(at t: Double) -> SaberState {
        switch self {
        case .extended: return SaberState(ext: 1, glow: 0, time: t)
        case .hover: return SaberState(ext: 1, glow: 1, time: t)
        case .retracted: return SaberState(ext: 0, glow: 0, time: t)
        case .live:
            let c = t.truncatingRemainder(dividingBy: 6)
            let ext: Double = c < 3.4 ? 1 : c < 3.75 ? 1 - (c - 3.4) / 0.35 : c < 5 ? 0 : c < 5.18 ? (c - 5) / 0.18 : 1
            let glow: Double = c < 1.5 ? 0 : c < 1.7 ? (c - 1.5) / 0.2 : c < 2.9 ? 1 : c < 3.1 ? 1 - (c - 2.9) / 0.2 : 0
            return SaberState(ext: ext, glow: glow, time: t)
        }
    }
}

struct SaberPreview: View {
    let config: SaberConfig
    @State private var mode: PreviewMode = .live
    @State private var lightBackground = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("", selection: $mode) {
                    ForEach(PreviewMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Toggle("Light", isOn: $lightBackground).fixedSize()
            }
            TimelineView(.animation) { tl in
                Canvas { ctx, size in
                    let st = mode.state(at: tl.date.timeIntervalSinceReferenceDate)
                    let lay = SaberRenderer.layout(config, scale: 1)
                    let s = min(size.width / lay.size.width, size.height / lay.size.height) * 0.92
                    guard let r = SaberRenderer.render(config, st, scale: s, backing: 2) else { return }
                    let origin = CGPoint(x: (size.width - r.size.width) / 2, y: (size.height - r.size.height) / 2)
                    ctx.draw(Image(decorative: r.image, scale: 2), in: CGRect(origin: origin, size: r.size))
                }
            }
            .frame(minHeight: 380)
            .background(lightBackground ? Color(white: 0.93) : Color(red: 0.04, green: 0.05, blue: 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

struct TestStrip: View {
    let idleSeconds: Double
    let retract: Bool
    @State private var checked = true

    var body: some View {
        GroupBox("Try it with your real cursor") {
            VStack(alignment: .leading, spacing: 10) {
                Text(retract
                     ? "Hover these and the blade flares. Stop moving for \(Int(idleSeconds))s and it retracts; move again to re-ignite."
                     : "Hover these and the blade flares.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    Button("Button") {}.fixedSize()
                    Button("Link") {}.buttonStyle(.link).fixedSize()
                    Toggle("Checkbox", isOn: $checked).fixedSize()
                    Menu("Menu") { Button("Item") {} }.fixedSize()
                    Text("Plain text (no glow)").fixedSize().foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: (Double) -> String = { String(format: "%.0f%%", $0 * 100) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value)).foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: $value, in: range)
        }
    }
}

struct EditorPanel: View {
    @ObservedObject var settings: AppSettings
    @State private var saveName = ""

    private var saber: Binding<SaberConfig> { $settings.prefs.saber }

    private func withHilt(_ h: HiltStyle) -> SaberConfig {
        var c = settings.prefs.saber
        c.hilt = h
        return c
    }

    private func color(_ kp: WritableKeyPath<SaberConfig, RGB>) -> Binding<Color> {
        Binding(get: { settings.prefs.saber[keyPath: kp].color },
                set: { settings.prefs.saber[keyPath: kp] = RGB($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Randomizer") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Toggle("Hilt", isOn: $settings.prefs.randomHilt)
                        Toggle("Color", isOn: $settings.prefs.randomColor)
                        Spacer()
                        Button {
                            settings.randomize()
                        } label: {
                            Label("Randomize", systemImage: "dice.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!settings.prefs.randomHilt && !settings.prefs.randomColor)
                    }
                    Picker("Side", selection: $settings.prefs.randomSide) {
                        ForEach(RandomSide.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(4)
            }

            GroupBox("Identity") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Name", text: saber.name)
                    Picker("Side", selection: saber.faction) {
                        ForEach(Faction.allCases) { Text($0.shortName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(4)
            }

            GroupBox("Hilt") {
                VStack(alignment: .leading, spacing: 10) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
                        ForEach(HiltStyle.allCases) { h in
                            let selected = settings.prefs.saber.hilt == h
                            Button {
                                settings.prefs.saber.hilt = h
                            } label: {
                                VStack(spacing: 2) {
                                    HiltThumb(config: withHilt(h), height: 22).frame(height: 24)
                                    Text(h.displayName).font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.05)))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("Finish").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(HiltFinish.allCases) { f in
                            Button {
                                settings.prefs.saber.finish = f
                            } label: {
                                Circle()
                                    .fill(LinearGradient(colors: [f.dark.color, f.light.color, f.base.color], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: 24, height: 24)
                                    .overlay(Circle().stroke(settings.prefs.saber.finish == f ? Color.accentColor : Color.gray.opacity(0.5), lineWidth: settings.prefs.saber.finish == f ? 3 : 1))
                            }
                            .buttonStyle(.plain)
                            .help(f.displayName)
                        }
                        Spacer()
                        ColorPicker("Accent", selection: color(\.accent), supportsOpacity: false)
                    }
                }
                .padding(4)
            }

            GroupBox("Blade") {
                VStack(alignment: .leading, spacing: 10) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 6), count: 9), spacing: 6) {
                        ForEach(BladeColors.swatches, id: \.0) { name, rgb in
                            Button {
                                settings.prefs.saber.blade = rgb
                                if settings.prefs.saber.bladeStyle == .darksaber { settings.prefs.saber.bladeStyle = .standard }
                            } label: {
                                Circle().fill(rgb.color).frame(width: 22, height: 22)
                                    .shadow(color: rgb.color.opacity(0.8), radius: 3)
                                    .overlay(Circle().stroke(settings.prefs.saber.blade == rgb ? Color.primary : Color.clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .help(name)
                        }
                    }
                    ColorPicker("Custom blade color", selection: color(\.blade), supportsOpacity: false)
                    Picker("Style", selection: saber.bladeStyle) {
                        ForEach(BladeStyle.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Animated shimmer (hum flicker)", isOn: saber.animated)
                    LabeledSlider(title: "Core brightness", value: saber.coreWhiteness, range: 0...1)
                    LabeledSlider(title: "Length", value: saber.bladeLength, range: 0.6...1.4)
                    LabeledSlider(title: "Thickness", value: saber.thickness, range: 0.6...1.8)
                }
                .padding(4)
            }

            GroupBox("Glow") {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledSlider(title: "Glow size", value: saber.glowRadius, range: 0.3...2)
                    LabeledSlider(title: "Glow strength", value: saber.glowIntensity, range: 0.2...1.6)
                }
                .padding(4)
            }

            GroupBox("Save") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Name for My Sabers", text: $saveName)
                        Button("Save New") {
                            settings.saveCustom(named: saveName.trimmingCharacters(in: .whitespaces))
                            saveName = ""
                        }
                    }
                    if settings.prefs.customSabers.contains(where: { $0.id == settings.prefs.saber.id }) {
                        HStack {
                            Button("Update \"\(settings.prefs.saber.name)\"") { settings.updateCustom() }
                            Button("Delete", role: .destructive) {
                                settings.deleteCustom(settings.prefs.saber.id)
                            }
                        }
                    }
                }
                .padding(4)
            }
        }
    }
}

// MARK: Behavior tab

struct BehaviorTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var engine: CursorEngine
    @State private var loginError: String?
    @State private var refresh = 0

    var body: some View {
        Form {
            Section("Cursor") {
                LabeledSlider(title: "Size", value: $settings.prefs.scale, range: 0.45...1.6)
            }
            Section("Idle retract") {
                Toggle("Retract the blade when the mouse is idle", isOn: $settings.prefs.retractWhenIdle)
                LabeledSlider(title: "Idle time before retracting", value: $settings.prefs.idleSeconds, range: 1...30,
                              format: { "\(Int($0.rounded()))s" })
                    .disabled(!settings.prefs.retractWhenIdle)
            }
            Section("Effects") {
                Toggle("Glow when hovering something clickable", isOn: $settings.prefs.hoverGlow)
                Toggle("Spark on click", isOn: $settings.prefs.clickSpark)
                Toggle("Motion trail on fast swings", isOn: $settings.prefs.motionTrail)
            }
            Section("Randomizer") {
                Toggle("Randomize hilt", isOn: $settings.prefs.randomHilt)
                Toggle("Randomize color", isOn: $settings.prefs.randomColor)
                Picker("Side", selection: $settings.prefs.randomSide) {
                    ForEach(RandomSide.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("New random saber every time the blade re-ignites after idle", isOn: $settings.prefs.randomOnIgnite)
            }
            Section("System") {
                Toggle("Launch at login", isOn: Binding(
                    get: { _ = refresh; return SMAppService.mainApp.status == .enabled },
                    set: { on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                        refresh += 1
                    }))
                if let loginError { Text(loginError).foregroundStyle(.red).font(.caption) }
                LabeledContent("Toggle shortcut", value: HotKey.displayString)
                LabeledContent("Accessibility (hover glow)") {
                    HStack {
                        Text(engine.axTrusted ? "Granted" : "Not granted")
                            .foregroundStyle(engine.axTrusted ? .green : .orange)
                        if !engine.axTrusted {
                            Button("Open Settings…") {
                                Accessibility.prompt()
                                Accessibility.openSettings()
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Auto-switch tab

struct SaberPickerMenu: View {
    let title: String
    let custom: [SaberConfig]
    let current: SaberConfig
    let onPick: (SaberConfig) -> Void

    var body: some View {
        Menu(title) {
            Button("Current saber (\(current.name))") { onPick(current) }
            Divider()
            ForEach(Faction.allCases) { f in
                Section(f.displayName) {
                    ForEach(Presets.all.filter { $0.faction == f }) { s in Button(s.name) { onPick(s) } }
                }
            }
            if !custom.isEmpty {
                Section("My Sabers") {
                    ForEach(custom) { s in Button(s.name) { onPick(s) } }
                }
            }
        }
        .fixedSize()
    }
}

struct AutoSwitchTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var engine: CursorEngine

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func hourLabel(_ h: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "h a"
        let d = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date()) ?? Date()
        return f.string(from: d)
    }

    var body: some View {
        Form {
            Section {
                Text("Priority: a per-app rule wins, then after dark, then your chosen saber. Switches retract the old blade and ignite the new one.")
                    .foregroundStyle(.secondary)
                LabeledContent("Showing now", value: engine.activeDescription)
            }
            Section("After dark") {
                Toggle("Switch sabers after dark", isOn: $settings.prefs.afterDark)
                Picker("Night is", selection: $settings.prefs.afterDarkMode) {
                    ForEach(AfterDarkMode.allCases) { Text($0.displayName).tag($0) }
                }
                if settings.prefs.afterDarkMode == .hours {
                    Picker("From", selection: $settings.prefs.nightStart) {
                        ForEach(0..<24, id: \.self) { Text(hourLabel($0)).tag($0) }
                    }
                    Picker("Until", selection: $settings.prefs.nightEnd) {
                        ForEach(0..<24, id: \.self) { Text(hourLabel($0)).tag($0) }
                    }
                }
                HStack {
                    SaberThumb(config: settings.prefs.nightSaber, height: 30)
                    Text("Night saber: \(settings.prefs.nightSaber.name)")
                    Spacer()
                    SaberPickerMenu(title: "Change…", custom: settings.prefs.customSabers, current: settings.prefs.saber) {
                        settings.prefs.nightSaber = $0
                    }
                }
                LabeledContent("It is currently", value: settings.isNight() ? "night" : "day")
            }
            Section("Per-app sabers") {
                Toggle("Use a different saber in specific apps", isOn: $settings.prefs.perApp)
                ForEach($settings.prefs.appRules) { $rule in
                    HStack {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleID) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 22, height: 22)
                        }
                        Text(rule.appName)
                        Spacer()
                        SaberThumb(config: rule.saber, height: 28)
                        Text(rule.saber.name).foregroundStyle(.secondary).lineLimit(1)
                        SaberPickerMenu(title: "Change…", custom: settings.prefs.customSabers, current: settings.prefs.saber) {
                            rule.saber = $0
                        }
                        Button(role: .destructive) {
                            settings.prefs.appRules.removeAll { $0.id == rule.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Menu("Add app…") {
                    ForEach(runningApps, id: \.processIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier!) {
                            let id = app.bundleIdentifier!
                            guard !settings.prefs.appRules.contains(where: { $0.bundleID == id }) else { return }
                            settings.prefs.appRules.append(AppRule(bundleID: id, appName: app.localizedName ?? id, saber: settings.prefs.saber))
                        }
                    }
                }
                .fixedSize()
            }
        }
        .formStyle(.grouped)
    }
}
