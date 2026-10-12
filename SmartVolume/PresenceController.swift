import AppKit

/// Shows SmartVolume in the Dock, the menu bar, or nowhere.
final class PresenceController: NSObject, PresenceApplying {
    var onOpenSettings: (() -> Void)?

    private var statusItem: NSStatusItem?
    private let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var lastStatus: (symbol: String, text: String) = ("speaker.wave.2", "Starting…")

    func apply(_ mode: PresenceMode) {
        switch mode {
        case .dock:
            NSApp.setActivationPolicy(.regular)
            removeStatusItem()
        case .menuBar:
            NSApp.setActivationPolicy(.accessory)
            addStatusItem()
        case .background:
            NSApp.setActivationPolicy(.accessory)
            removeStatusItem()
        }
    }

    func update(link: LinkState, monitorIsOutput: Bool, accessibilityGranted: Bool) {
        if !accessibilityGranted {
            lastStatus = ("exclamationmark.triangle", "Needs \(KeyPermission.settingsName) permission")
        } else {
            switch link {
            case .unpaired: lastStatus = ("speaker.slash", "Monitor not paired")
            case .connecting: lastStatus = ("speaker.wave.2", "Connecting to monitor…")
            case .unreachable: lastStatus = ("exclamationmark.triangle", "Monitor unreachable, using Mac volume")
            case .connected:
                lastStatus = monitorIsOutput
                    ? ("speaker.wave.3.fill", "Controlling monitor volume")
                    : ("speaker.wave.2", "Monitor connected, not the sound output")
            }
        }
        renderStatus()
    }

    private func addStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem(title: "Quit SmartVolume", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
        renderStatus()
    }

    private func removeStatusItem() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    private func renderStatus() {
        stateItem.title = lastStatus.text
        statusItem?.button?.image = NSImage(systemSymbolName: lastStatus.symbol, accessibilityDescription: lastStatus.text)
        statusItem?.button?.toolTip = "SmartVolume: \(lastStatus.text)"
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }
}
