import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let cam = PixyController()
    let feed = CameraFeed()
    private var statusItem: NSStatusItem!
    private var panel: PanelController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = AppDelegate.menuIcon(connected: false)
            button.target = self
            button.action = #selector(togglePanel)
        }
        panel = PanelController(cam: cam, feed: feed)
        cam.$connected
            .receive(on: RunLoop.main)
            .sink { [weak self] on in
                self?.statusItem.button?.image = AppDelegate.menuIcon(connected: on)
            }
            .store(in: &bag)
    }

    private var bag = Set<AnyCancellable>()

    /// Reabrir o app (Finder, Dock, login) abre o painel em vez de qualquer janela.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let button = statusItem.button, !panel.isVisible { panel.show(relativeTo: button) }
        return false
    }

    /// Ícone template da barra de menu (Resources/MenuIcon*.png), com fallback para SF Symbols.
    static func menuIcon(connected: Bool) -> NSImage? {
        let name = connected ? "MenuIcon" : "MenuIconOff"
        let img = Bundle.main.image(forResource: name)
            ?? NSImage(systemSymbolName: connected ? "video.fill" : "video.slash", accessibilityDescription: "PixyBar")
        img?.isTemplate = true
        img?.size = NSSize(width: 18, height: 18)
        return img
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        panel.toggle(relativeTo: button)
    }
}

import Combine
