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
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle, .fullScreenDisallowsTiling]
        sharingType = .readOnly
        animationBehavior = .none

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

    private let settings: AppSettings
    private var overlays: [OverlayWindow] = []
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var eventMonitors: [Any] = []

    /// Frame rate follows what's on screen: full speed while the pointer moves or the blade animates,
    /// 24 Hz for a flickering blade at rest (the rate its frame loop plays at), and 10 Hz when nothing changes, to save battery.
    private enum Pace: Double {
        case fast = 120, shimmer = 24, rest = 10
    }
    private var pace = Pace.fast
    private var lastRenderedMouse: CGPoint?
    private var lastRenderedWindow: OverlayWindow?
    private var trailShown = false

    private var lastTick = CACurrentMediaTime()
    private var lastMouse = NSEvent.mouseLocation
    private var lastMoveTime = CACurrentMediaTime()
    private var lastHide: CFTimeInterval = 0
    private var lastResolve: CFTimeInterval = 0
    private var lastSecureCheck: CFTimeInterval = 0
    private var lastShapeCheck: CFTimeInterval = 0
    private var overSecureDialog = false
    private var overResizeEdge = false
    /// True while macOS's own pointer is shown instead of the saber (secure dialogs, resize edges).
    private var showingSystemPointer = false
    private var soundEngine: SaberSound?
    private var lastSwing: CFTimeInterval = 0
    private var humSpeed: Double = 0
    private var humTestStart: CFTimeInterval?
    private var speed: CGFloat = 0

    private var ext: Double = 1
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
        var frame: Int
        var scale: Double
        var backing: CGFloat
    }
    private var lastKey: RenderKey?
    private var cached: RenderedImage?
    private var frontBundleID: String?

    /// A fully lit flickering blade replays a loop of frames drawn once, instead of redrawing every frame.
    /// 46 frames at 24 fps span two turns of the Inquisitor ring's three-fold symmetry, so its spin loops seamlessly.
    private static let loopFrames = 46
    private static let loopDuration = 2 * (2 * Double.pi / 3) / 2.2
    private struct LoopKey: Equatable {
        var config: SaberConfig
        var scale: Double
        var backing: CGFloat
    }
    private var loopKey: LoopKey?
    private var loop: [Int: RenderedImage] = [:]

    init(settings: AppSettings) {
        self.settings = settings
        displayed = settings.prefs.saber
        frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        settings.$prefs.map(\.enabled).removeDuplicates().sink { [weak self] on in
            DispatchQueue.main.async { on ? self?.start() : self?.stop() }
        }.store(in: &cancellables)
        settings.$prefs.map(\.soundEnabled).removeDuplicates().sink { [weak self] on in
            if !on { self?.soundEngine?.shutdown() }
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
        schedule(.fast)
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in self?.onClick() }) {
            eventMonitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] e in self?.onClick(); return e }) {
            eventMonitors.append(l)
        }
        // Movement wakes the loop from its resting rate straight away (the resting tick would notice within 0.1 s anyway).
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in self?.wake() }) {
            eventMonitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] e in self?.wake(); return e }) {
            eventMonitors.append(l)
        }
        SystemCursor.ensureHidden()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        eventMonitors.removeAll()
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        SystemCursor.restore()
        soundEngine?.shutdown()
    }

    private func schedule(_ p: Pace) {
        timer?.invalidate()
        let t = Timer(timeInterval: 1 / p.rawValue, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        // Slack lets macOS batch the resting wake-ups with other work.
        t.tolerance = p == .rest ? 0.03 : 0
        RunLoop.main.add(t, forMode: .common)
        timer = t
        pace = p
    }

    private func wake() {
        guard timer != nil, pace != .fast else { return }
        schedule(.fast)
        tick()
    }

    /// Picks the frame rate for what's happening now.
    private func updatePace(now: CFTimeInterval, settled: Bool) {
        let want: Pace
        if !settled || now - lastMoveTime < 0.6 || NSEvent.pressedMouseButtons != 0 || sparkStart != nil || humTestStart != nil {
            want = .fast
        } else if ext > 0 && !showingSystemPointer && (displayed.animated || displayed.bladeStyle == .unstable) {
            want = .shimmer
        } else {
            want = .rest
        }
        if want != pace { schedule(want) }
    }

    private func rebuildOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = NSScreen.screens.map { OverlayWindow(screen: $0) }
        overlays.forEach { $0.orderFrontRegardless() }
        lastKey = nil
    }

    private func onClick() {
        lastMoveTime = CACurrentMediaTime()
        wake()
        if settings.prefs.soundClash { playSound(.clash) }
        guard settings.prefs.clickSpark else { return }
        sparkStart = CACurrentMediaTime()
        sparkPoint = NSEvent.mouseLocation
    }

    func playSound(_ kind: SaberSound.Kind, force: Bool = false, rate: Double = 1) {
        let p = settings.prefs
        guard force || p.soundEnabled else { return }
        if soundEngine == nil { soundEngine = SaberSound() }
        soundEngine?.play(kind, volume: p.soundVolume, rate: rate)
    }

    /// Plays the motion hum sweeping from resting pitch to full-speed pitch.
    func testHum() {
        if soundEngine == nil { soundEngine = SaberSound() }
        humTestStart = CACurrentMediaTime()
    }

    /// 0 at rest, 1 at a fast flick (~3000 pt/s).
    private static func speedLevel(_ speed: CGFloat) -> Double {
        pow(min(1, max(0, Double(speed) / 3000)), 0.7)
    }

    private func updateHum(now: CFTimeInterval, dt: Double, prefs p: Prefs) {
        var level = Self.speedLevel(speed)
        var active = p.soundEnabled && p.soundHum && ext > 0.3 && !showingSystemPointer
        if let start = humTestStart {
            let u = (now - start) / 2.4
            if u >= 1 {
                humTestStart = nil
            } else {
                active = true
                level = sin(.pi * u)
            }
        }
        humSpeed += (level - humSpeed) * min(1, dt * 9)
        guard active || soundEngine != nil else { return }
        soundEngine?.updateHum(active: active, rate: 0.75 + 0.9 * humSpeed,
                               volume: p.soundVolume * (0.12 + 0.6 * humSpeed))
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
        if p.soundSwing && speed > 1600 && ext > 0.6 && now - lastSwing > 0.45 {
            lastSwing = now
            playSound(.swing, rate: 0.75 + 0.85 * min(1, Double(speed - 1600) / 3400))
        }
        lastMouse = mouse

        if now - lastSecureCheck > (pace == .fast ? 0.12 : 0.3) {
            lastSecureCheck = now
            overSecureDialog = CGEvent(source: nil).map { SecureDialogs.cover($0.location) } ?? false
        }
        // Only sample the system cursor while the pointer is moving, a button is held (a resize drag),
        // or we're already showing resize arrows.
        let active = now - lastMoveTime < 0.6 || NSEvent.pressedMouseButtons != 0 || overResizeEdge
        if p.systemResizeArrows && active && now - lastShapeCheck > 0.06 {
            lastShapeCheck = now
            overResizeEdge = SystemCursorShape.isResize()
        } else if !p.systemResizeArrows {
            overResizeEdge = false
        }
        let wantSystem = overSecureDialog || overResizeEdge
        if wantSystem != showingSystemPointer {
            showingSystemPointer = wantSystem
            if wantSystem { SystemCursor.restore() } else { lastHide = 0 }
        }
        if showingSystemPointer {
            hideAll()
            updateHum(now: now, dt: dt, prefs: p)
            updatePace(now: now, settled: true)
            return
        }
        if now - lastHide > (pace == .fast ? 0.2 : 0.5) {
            lastHide = now
            SystemCursor.ensureHidden()
            overlays.forEach { $0.orderFrontRegardless() }
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
                if p.soundIgnite { playSound(.ignite) }
                if p.randomOnIgnite && displayedReason == "base" {
                    settings.randomize()
                    displayed = settings.prefs.saber
                }
            }
            ext = min(target, ext + dt / 0.18)
        } else if ext > target {
            if ext >= 0.999 && p.soundIgnite { playSound(.retract) }
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

        updateHum(now: now, dt: dt, prefs: p)
        render(now: now, mouse: mouse, prefs: p)
        updatePace(now: now, settled: ext == target && pending == nil)
    }

    private func hideAll() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for w in overlays {
            w.saberLayer.isHidden = true
            w.sparkLayer.isHidden = true
            w.trailLayers.forEach { $0.isHidden = true }
        }
        CATransaction.commit()
        lastRenderedMouse = nil
        trailShown = false
    }

    private func render(now: CFTimeInterval, mouse: CGPoint, prefs p: Prefs) {
        guard let window = overlays.first(where: { NSMouseInRect(mouse, $0.screenFrame, false) }) ?? overlays.first else { return }
        let scale = CGFloat(p.scale)
        let cfg = displayed
        let animated = cfg.animated || cfg.bladeStyle == .unstable
        let looping = animated && ext >= 1
        let frame = !animated || ext <= 0 ? 0
            : looping ? Int(now / Self.loopDuration * Double(Self.loopFrames)) % Self.loopFrames
            : Int(now * 40)
        let key = RenderKey(config: cfg, ext: Int(ext * 120), frame: frame, scale: p.scale, backing: window.backing)
        // Nothing moved and the image is the same: leave the layers alone.
        if key == lastKey && mouse == lastRenderedMouse && window === lastRenderedWindow && sparkStart == nil && !trailShown {
            return
        }
        if key != lastKey {
            lastKey = key
            if looping {
                let lk = LoopKey(config: cfg, scale: p.scale, backing: window.backing)
                if lk != loopKey {
                    loopKey = lk
                    loop.removeAll()
                }
                if let img = loop[frame] {
                    cached = img
                } else {
                    let t = Double(frame) * Self.loopDuration / Double(Self.loopFrames)
                    cached = SaberRenderer.render(cfg, SaberState(ext: 1, time: t), scale: scale, backing: window.backing)
                    loop[frame] = cached
                }
            } else {
                cached = SaberRenderer.render(cfg, SaberState(ext: ext, time: now), scale: scale, backing: window.backing)
            }
        }
        lastRenderedMouse = mouse
        lastRenderedWindow = window

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
            if trailShown { w.trailLayers.forEach { $0.isHidden = true } }
            trailShown = false
            return
        }
        trailShown = true
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
