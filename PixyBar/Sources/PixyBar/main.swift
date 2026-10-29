import AppKit

if CommandLine.arguments.contains("--selftest") {
    Task { @MainActor in
        let code = await SelfTest.run()
        exit(code)
    }
    RunLoop.main.run()
} else {
    // App AppKit puro: sem cenas SwiftUI, logo sem janela "Ajustes" fantasma ao reabrir.
    let app = NSApplication.shared
    let delegate = MainActor.assumeIsolated { AppDelegate() }
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
