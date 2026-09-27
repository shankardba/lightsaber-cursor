import AppKit

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--render-sheet"), i + 1 < args.count {
    ContactSheet.render(to: args[i + 1])
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
