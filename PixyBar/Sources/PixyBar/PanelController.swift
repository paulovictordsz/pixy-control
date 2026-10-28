import AppKit
import SwiftUI

/// Painel flutuante próprio (sem moldura, fundo transparente) para o conteúdo ter cantos arredondados
/// de verdade. Fecha ao clicar fora ou com Esc; recebe teclado sem roubar o foco do app em uso.
@MainActor
final class PanelController {
    private let panel: KeyablePanel
    private let host: NSHostingController<AnyView>
    private let cam: PixyController
    private let feed: CameraFeed
    private var outsideClickMonitor: Any?
    private var keyMonitor: Any?

    init(cam: PixyController, feed: CameraFeed) {
        self.cam = cam
        self.feed = feed
        host = NSHostingController(rootView: AnyView(MenuView().environmentObject(cam).environmentObject(feed)))
        host.sizingOptions = [.preferredContentSize]
        panel = KeyablePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentViewController = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
    }

    var isVisible: Bool { panel.isVisible }

    func toggle(relativeTo button: NSStatusBarButton) {
        if panel.isVisible { hide() } else { show(relativeTo: button) }
    }

    func show(relativeTo button: NSStatusBarButton) {
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize
        panel.setContentSize(size)
        if let bw = button.window {
            let b = bw.convertToScreen(button.convert(button.bounds, to: nil))
            var origin = NSPoint(x: b.midX - size.width / 2, y: b.minY - size.height - 6)
            if let screen = bw.screen ?? NSScreen.main {
                let vf = screen.visibleFrame
                origin.x = min(max(origin.x, vf.minX + 8), vf.maxX - size.width - 8)
            }
            panel.setFrameOrigin(origin)
        }
        panel.makeKeyAndOrderFront(nil)
        feed.start()
        Task { await cam.refresh() }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            guard let self, self.panel.isKeyWindow else { return ev }
            return self.handle(key: ev) ? nil : ev
        }
    }

    func hide() {
        panel.orderOut(nil)
        feed.stop()
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m); outsideClickMonitor = nil }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    /// Atalhos do painel. Devolve true se consumiu a tecla.
    private func handle(key ev: NSEvent) -> Bool {
        let cmd = ev.modifierFlags.contains(.command)
        let step = cam.step
        switch ev.keyCode {
        case 53: hide(); return true                                   // esc
        case 123: Task { await cam.nudge(pan: -step) }; return true     // ←
        case 124: Task { await cam.nudge(pan: step) }; return true      // →
        case 126: Task { await cam.nudge(tilt: step) }; return true     // ↑
        case 125: Task { await cam.nudge(tilt: -step) }; return true    // ↓
        default: break
        }
        guard let ch = ev.charactersIgnoringModifiers?.lowercased() else { return false }
        switch (ch, cmd) {
        case ("0", false): Task { await cam.center() }; return true
        case ("1", false), ("2", false), ("3", false): Task { await cam.goPreset(Int(ch)! - 1) }; return true
        case ("1", true), ("2", true), ("3", true): cam.savePreset(Int(ch)! - 1); return true
        case ("t", false): Task { await cam.setTracking(!cam.tracking) }; return true
        case ("p", false): Task { await cam.setPrivacy(!cam.privacy) }; return true
        case ("r", true): Task { await cam.refresh() }; return true
        case ("q", true): NSApp.terminate(nil); return true
        default: return false
        }
    }
}

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
