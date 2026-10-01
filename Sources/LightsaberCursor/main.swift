import AppKit
import ServiceManagement

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--render-sheet"), i + 1 < args.count {
    ContactSheet.render(to: args[i + 1])
    exit(0)
}

if let i = args.firstIndex(of: "--render-preset"), i + 2 < args.count {
    ContactSheet.renderPreset(named: args[i + 1], to: args[i + 2])
    exit(0)
}

// Used by scripts/setup.sh: `--login-item off` when starting fresh.
if let i = args.firstIndex(of: "--login-item"), i + 1 < args.count {
    if args[i + 1] == "on" {
        try? SMAppService.mainApp.register()
    } else {
        try? SMAppService.mainApp.unregister()
    }
    exit(0)
}

if let i = args.firstIndex(of: "--export-sounds"), i + 1 < args.count {
    SaberSound().export(to: args[i + 1])
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
