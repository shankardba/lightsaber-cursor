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

enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func prompt() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Asks the Accessibility API whether the element under the pointer is something clickable.
final class HoverDetector {
    private let queue = DispatchQueue(label: "lightsaber.hover", qos: .userInteractive)
    private let systemWide = AXUIElementCreateSystemWide()
    private var inFlight = false
    private(set) var isClickable = false

    private static let clickableRoles: Set<String> = [
        "AXButton", "AXLink", "AXMenuItem", "AXMenuBarItem", "AXCheckBox", "AXRadioButton",
        "AXPopUpButton", "AXMenuButton", "AXDisclosureTriangle", "AXDockItem", "AXComboBox",
        "AXIncrementor", "AXColorWell", "AXSlider", "AXTab", "AXSegment",
    ]
    private static let stopRoles: Set<String> = [
        "AXWindow", "AXApplication", "AXWebArea", "AXScrollArea", "AXSplitGroup", "AXTextArea",
        "AXTextField", "AXTable", "AXOutline", "AXBrowser", "AXList", "AXLayoutArea", "AXSheet",
    ]
    private static let pressActions: Set<String> = ["AXPress", "AXOpen", "AXPick"]

    init() {
        AXUIElementSetMessagingTimeout(systemWide, 0.12)
    }

    func poll() {
        guard !inFlight, let point = CGEvent(source: nil)?.location else { return }
        inFlight = true
        queue.async { [weak self] in
            guard let self else { return }
            let result = self.check(point)
            DispatchQueue.main.async {
                self.isClickable = result
                self.inFlight = false
            }
        }
    }

    func reset() { isClickable = false }

    private func check(_ p: CGPoint) -> Bool {
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(p.x), Float(p.y), &found) == .success,
              var el = found else { return false }
        for depth in 0..<5 {
            let role = string(el, kAXRoleAttribute) ?? ""
            if Self.clickableRoles.contains(role) { return true }
            if Self.stopRoles.contains(role) { return false }
            if depth < 2, role != "AXGroup", role != "AXStaticText", hasPressAction(el) { return true }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { return false }
            el = parent as! AXUIElement
        }
        return false
    }

    private func string(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }

    private func hasPressAction(_ el: AXUIElement) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyActionNames(el, &names) == .success, let list = names as? [String] else { return false }
        return list.contains { Self.pressActions.contains($0) }
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
