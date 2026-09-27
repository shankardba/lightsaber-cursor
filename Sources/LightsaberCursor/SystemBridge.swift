import AppKit
import ApplicationServices
import Carbon

/// Hiding the real pointer while another app is frontmost needs the "SetsCursorInBackground"
/// connection property; it is private WindowServer API, so it is resolved at runtime.
enum SystemCursor {
    private typealias DefaultConnection = @convention(c) () -> Int32
    private typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
    private typealias IsVisible = @convention(c) () -> Int32

    private static let handle = dlopen(nil, RTLD_NOW)
    private static let isVisibleFn: IsVisible? = {
        guard let sym = dlsym(handle, "CGCursorIsVisible") else { return nil }
        return unsafeBitCast(sym, to: IsVisible.self)
    }()

    static func enableBackgroundControl() {
        guard let a = dlsym(handle, "_CGSDefaultConnection"), let b = dlsym(handle, "CGSSetConnectionProperty") else { return }
        let conn = unsafeBitCast(a, to: DefaultConnection.self)()
        _ = unsafeBitCast(b, to: SetProperty.self)(conn, conn, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }

    static var isVisible: Bool { (isVisibleFn?() ?? 1) != 0 }

    static func ensureHidden() {
        if isVisible { CGDisplayHideCursor(CGMainDisplayID()) }
    }

    static func restore() {
        var n = 0
        while !isVisible && n < 64 {
            CGDisplayShowCursor(CGMainDisplayID())
            n += 1
        }
    }
}

/// Recognizes macOS's own window/divider resize pointers from the system-wide current cursor.
/// They're identified by size plus a hotspot at the image centre (the arrow's hotspot is at its tip).
enum SystemCursorShape {
    private static let resizeSizes: [CGSize] = [
        CGSize(width: 18, height: 28), CGSize(width: 24, height: 18), CGSize(width: 22, height: 22),
        CGSize(width: 30, height: 24), CGSize(width: 24, height: 28), CGSize(width: 24, height: 24),
    ]
    private static let debug = UserDefaults.standard.bool(forKey: "debugCursorShapes")
    private static var lastLogged = ""

    static func isResize() -> Bool {
        guard let c = NSCursor.currentSystem else { return false }
        let s = c.image.size
        let h = c.hotSpot
        guard s.width > 0, s.height > 0 else { return false }
        if debug {
            let sig = "size=\(s) hot=\(h)"
            if sig != lastLogged {
                lastLogged = sig
                NSLog("cursor shape \(sig)")
            }
        }
        let centred = abs(h.x - s.width / 2) <= max(1.5, s.width * 0.06)
            && abs(h.y - s.height / 2) <= max(1.5, s.height * 0.06)
        guard centred else { return false }
        return resizeSizes.contains { known in
            let k = s.width / known.width
            if abs(k - 1) < 0.03 {
                return abs(s.width - known.width) <= 0.5 && abs(s.height - known.height) <= 0.5
            }
            // Enlarged pointer (Accessibility → Display → Pointer size) scales every cursor uniformly.
            return k >= 1.2 && abs(s.height - known.height * k) <= s.height * 0.02
        }
    }
}

/// Password, keychain and permission prompts are drawn above every app window and can't be covered,
/// so over those the real pointer is shown instead of the saber.
enum SecureDialogs {
    private static let owners: Set<String> = [
        "SecurityAgent", "coreautha", "universalAccessAuthWarn", "UserNotificationCenter",
        "CoreServicesUIAgent", "ScreenSaverEngine", "loginwindow",
    ]
    private static let ownPID = ProcessInfo.processInfo.processIdentifier
    private static let highLayer = Int(CGWindowLevelForKey(.screenSaverWindow))

    /// `point` is in global CoreGraphics coordinates (top-left origin).
    static func cover(_ point: CGPoint) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        for w in list {
            if (w[kCGWindowOwnerPID as String] as? pid_t) == ownPID { continue }
            let owner = w[kCGWindowOwnerName as String] as? String ?? ""
            let layer = w[kCGWindowLayer as String] as? Int ?? 0
            guard owners.contains(owner) || layer >= highLayer else { continue }
            guard let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict), rect.contains(point) else { continue }
            return true
        }
        return false
    }
}

/// Global ⌃⌥⌘L toggle via Carbon hot keys (no extra permission needed).
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().action()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x4C53_4352), id: 1)
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    static let displayString = "⌃⌥⌘L"
    static func toggleShortcut(_ action: @escaping () -> Void) -> HotKey {
        HotKey(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(cmdKey | optionKey | controlKey), action: action)
    }
}
