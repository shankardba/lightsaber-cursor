import AppKit
import Combine
import QuartzCore

private let noActions: [String: CAAction] = [
    "position": NSNull(), "bounds": NSNull(), "frame": NSNull(), "contents": NSNull(),
    "opacity": NSNull(), "path": NSNull(), "hidden": NSNull(), "fillColor": NSNull(),
    "shadowColor": NSNull(), "shadowRadius": NSNull(), "contentsScale": NSNull(),
]

final class OverlayWindow: NSWindow {
    static let trailCount = 8
    let screenFrame: NSRect
    let saberLayer = CALayer()
    let sparkLayer = CALayer()
    let trailLayers: [CAShapeLayer]

    init(screen: NSScreen) {
        screenFrame = screen.frame
        trailLayers = (0..<Self.trailCount).map { _ in CAShapeLayer() }
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.cursorWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        let root = CALayer()
        root.actions = noActions
        view.layer = root
        view.wantsLayer = true
        contentView = view

        let backing = screen.backingScaleFactor
        for t in trailLayers {
            t.actions = noActions
            t.shadowOffset = .zero
            t.shadowOpacity = 0.9
            t.isHidden = true
            root.addSublayer(t)
        }
        for l in [saberLayer, sparkLayer] {
            l.actions = noActions
            l.contentsScale = backing
            l.isHidden = true
            root.addSublayer(l)
        }
    }

    var backing: CGFloat { screen?.backingScaleFactor ?? 2 }
}

final class CursorEngine: ObservableObject {
    @Published private(set) var activeDescription = ""
    @Published private(set) var axTrusted = Accessibility.isTrusted

    private let settings: AppSettings
    private let hover = HoverDetector()
    private var overlays: [OverlayWindow] = []
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var clickMonitors: [Any] = []

    private var lastTick = CACurrentMediaTime()
    private var lastMouse = NSEvent.mouseLocation
    private var lastMoveTime = CACurrentMediaTime()
    private var lastHoverPoll: CFTimeInterval = 0
    private var lastHide: CFTimeInterval = 0
    private var lastResolve: CFTimeInterval = 0
    private var lastTrustCheck: CFTimeInterval = 0
    private var speed: CGFloat = 0

    private var ext: Double = 1
    private var glow: Double = 0
    private var displayed: SaberConfig
    private var displayedReason = "base"
    private var pending: (SaberConfig, String)?
    private var wasRetracted = false

    private var sparkStart: CFTimeInterval?
    private var sparkPoint: CGPoint = .zero
    private var history: [(t: CFTimeInterval, emitter: CGPoint, tip: CGPoint)] = []

    private struct RenderKey: Equatable {
        var config: SaberConfig
        var ext: Int
        var glow: Int
        var frame: Int
        var scale: Double
        var backing: CGFloat
    }
    private var lastKey: RenderKey?
    private var cached: RenderedImage?
    private var frontBundleID: String?

    init(settings: AppSettings) {
        self.settings = settings
        displayed = settings.prefs.saber
        frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        settings.$prefs.map(\.enabled).removeDuplicates().sink { [weak self] on in
            DispatchQueue.main.async { on ? self?.start() : self?.stop() }
        }.store(in: &cancellables)

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.timer != nil else { return }
            self.rebuildOverlays()
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.frontBundleID = app?.bundleIdentifier
            self?.lastResolve = 0
        }
        SystemCursor.enableBackgroundControl()
    }

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        rebuildOverlays()
        lastMoveTime = CACurrentMediaTime()
        ext = 0
        let t = Timer(timeInterval: 1.0 / 120.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in self?.onClick() }) {
            clickMonitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.onClick(); return e }) {
            clickMonitors.append(l)
        }
        SystemCursor.ensureHidden()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        clickMonitors.forEach { NSEvent.removeMonitor($0) }
        clickMonitors.removeAll()
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        hover.reset()
        SystemCursor.restore()
    }

    private func rebuildOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = NSScreen.screens.map { OverlayWindow(screen: $0) }
        overlays.forEach { $0.orderFrontRegardless() }
        lastKey = nil
    }

    private func onClick() {
        lastMoveTime = CACurrentMediaTime()
        guard settings.prefs.clickSpark else { return }
        sparkStart = CACurrentMediaTime()
        sparkPoint = NSEvent.mouseLocation
    }

    // MARK: Active saber resolution (per-app > after dark > base)

    private func resolve() -> (SaberConfig, String, String) {
        let p = settings.prefs
        if p.perApp, let b = frontBundleID, let rule = p.appRules.first(where: { $0.bundleID == b }) {
            return (rule.saber, "app:\(b)", "\(rule.saber.name) (rule for \(rule.appName))")
        }
        if p.afterDark && settings.isNight() {
            return (p.nightSaber, "night", "\(p.nightSaber.name) (after dark)")
        }
        return (p.saber, "base", p.saber.name)
    }

    private func updateActive(now: CFTimeInterval) {
        let (cfg, reason, desc) = resolve()
        if desc != activeDescription { activeDescription = desc }
        if reason != displayedReason {
            if ext > 0.05 {
                pending = (cfg, reason)
            } else {
                displayed = cfg
                displayedReason = reason
            }
        } else if pending == nil, cfg != displayed {
            displayed = cfg
        }
    }

    // MARK: Frame loop

    @objc private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.05, max(1.0 / 240.0, now - lastTick))
        lastTick = now
        let p = settings.prefs

        let mouse = NSEvent.mouseLocation
        let dist = hypot(mouse.x - lastMouse.x, mouse.y - lastMouse.y)
        let moved = dist > 0.01
        if moved { lastMoveTime = now }
        speed += (dist / CGFloat(dt) - speed) * 0.35
        lastMouse = mouse

        if now - lastTrustCheck > 2 {
            lastTrustCheck = now
            let t = Accessibility.isTrusted
            if t != axTrusted { axTrusted = t }
        }
        if p.hoverGlow && axTrusted {
            let interval = moved ? 0.06 : 0.35
            if now - lastHoverPoll > interval {
                lastHoverPoll = now
                hover.poll()
            }
        }
        if now - lastHide > 0.2 {
            lastHide = now
            SystemCursor.ensureHidden()
        }
        if now - lastResolve > 0.5 || pending == nil && settings.prefs.saber != displayed && displayedReason == "base" {
            lastResolve = now
            updateActive(now: now)
        }

        let idle = p.retractWhenIdle && now - lastMoveTime > p.idleSeconds
        let target: Double = (idle || pending != nil) ? 0 : 1
        if ext < target {
            if wasRetracted {
                wasRetracted = false
                if p.randomOnIgnite && displayedReason == "base" {
                    settings.randomize()
                    displayed = settings.prefs.saber
                }
            }
            ext = min(target, ext + dt / 0.18)
        } else if ext > target {
            ext = max(target, ext - dt / (pending != nil ? 0.14 : 0.35))
        }
        if ext <= 0.001 {
            wasRetracted = true
            if let (cfg, reason) = pending {
                displayed = cfg
                displayedReason = reason
                pending = nil
            }
        }

        let glowTarget: Double = (p.hoverGlow && axTrusted && hover.isClickable && ext > 0.5) ? 1 : 0
        glow += (glowTarget - glow) * min(1, dt * 14)

        render(now: now, mouse: mouse, prefs: p)
    }

    private func render(now: CFTimeInterval, mouse: CGPoint, prefs p: Prefs) {
        guard let window = overlays.first(where: { NSMouseInRect(mouse, $0.screenFrame, false) }) ?? overlays.first else { return }
        let scale = CGFloat(p.scale)
        let cfg = displayed
        let animated = cfg.animated || cfg.bladeStyle == .unstable
        let key = RenderKey(config: cfg, ext: Int(ext * 120), glow: Int(glow * 60),
                            frame: animated && ext > 0 ? Int(now * 40) : 0, scale: p.scale, backing: window.backing)
        if key != lastKey {
            lastKey = key
            cached = SaberRenderer.render(cfg, SaberState(ext: ext, glow: glow, time: now), scale: scale, backing: window.backing)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for w in overlays where w !== window {
            w.saberLayer.isHidden = true
            w.sparkLayer.isHidden = true
            w.trailLayers.forEach { $0.isHidden = true }
        }
        let local = CGPoint(x: mouse.x - window.screenFrame.minX, y: mouse.y - window.screenFrame.minY)
        if let r = cached {
            window.saberLayer.contents = r.image
            window.saberLayer.contentsScale = window.backing
            window.saberLayer.frame = CGRect(x: local.x - r.anchor.x, y: local.y - r.anchor.y, width: r.size.width, height: r.size.height)
            window.saberLayer.isHidden = false
        }
        renderSpark(window, now: now, scale: scale, cfg: cfg)
        renderTrail(window, now: now, mouse: mouse, scale: scale, cfg: cfg, enabled: p.motionTrail)
        CATransaction.commit()
    }

    private func renderSpark(_ w: OverlayWindow, now: CFTimeInterval, scale: CGFloat, cfg: SaberConfig) {
        guard let start = sparkStart else {
            w.sparkLayer.isHidden = true
            return
        }
        let prog = (now - start) / 0.32
        if prog >= 1 {
            sparkStart = nil
            w.sparkLayer.isHidden = true
            return
        }
        let color = cfg.bladeStyle == .darksaber ? RGB(0.9, 0.94, 1) : cfg.blade
        guard let r = SaberRenderer.renderSpark(progress: prog, color: color, scale: scale, backing: w.backing) else { return }
        let local = CGPoint(x: sparkPoint.x - w.screenFrame.minX, y: sparkPoint.y - w.screenFrame.minY)
        w.sparkLayer.contents = r.image
        w.sparkLayer.frame = CGRect(x: local.x - r.anchor.x, y: local.y - r.anchor.y, width: r.size.width, height: r.size.height)
        w.sparkLayer.isHidden = false
    }

    private func renderTrail(_ w: OverlayWindow, now: CFTimeInterval, mouse: CGPoint, scale: CGFloat, cfg: SaberConfig, enabled: Bool) {
        let window: CFTimeInterval = 0.09
        let L = SaberRenderer.bladeLength(cfg) * scale
        let d = SaberRenderer.direction
        let emitter = CGPoint(x: mouse.x - d.dx * L, y: mouse.y - d.dy * L)
        let e = SaberRenderer.smooth(ext)
        let tip = CGPoint(x: emitter.x + d.dx * L * e, y: emitter.y + d.dy * L * e)
        history.append((now, emitter, tip))
        history.removeAll { now - $0.t > window }

        let strength = min(1, max(0, (speed - 350) / 1600))
        guard enabled, ext > 0.6, strength > 0.01, history.count >= 2 else {
            w.trailLayers.forEach { $0.isHidden = true }
            return
        }
        let color = cfg.bladeStyle == .darksaber ? RGB(0.9, 0.94, 1) : cfg.blade
        let off = CGPoint(x: w.screenFrame.minX, y: w.screenFrame.minY)
        let n = history.count
        for (i, layer) in w.trailLayers.enumerated() {
            let a = n - 2 - i
            guard a >= 0 else {
                layer.isHidden = true
                continue
            }
            let s0 = history[a]
            let s1 = history[a + 1]
            let path = CGMutablePath()
            path.addLines(between: [s0.emitter, s0.tip, s1.tip, s1.emitter].map { CGPoint(x: $0.x - off.x, y: $0.y - off.y) })
            path.closeSubpath()
            let age = CGFloat((now - s0.t) / window)
            layer.path = path
            layer.fillColor = color.cg(0.5)
            layer.shadowColor = color.cg()
            layer.shadowRadius = 5 * scale
            layer.opacity = Float(max(0, (1 - age) * 0.6 * strength))
            layer.isHidden = false
        }
    }
}
