import AppKit
import Combine
import Network
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator!
    private var presence: PresenceController!
    private var window: NSWindow?
    private var subscriptions: Set<AnyCancellable> = []
    private let pathMonitor = NWPathMonitor()
    private var lastPathStatus: NWPath.Status?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = UserDefaultsSettingsStore()
        let tokens = KeychainTokenStore()
        presence = PresenceController()
        coordinator = AppCoordinator(
            settings: settings,
            output: CoreAudioOutputWatcher(),
            keys: EventTapKeyInterceptor(),
            link: WebSocketMonitorLink(tokens: tokens),
            tokens: tokens,
            accessibility: { KeyPermission.isGranted },
            presence: presence,
            loginItem: LoginItem(),
            rediscover: { deviceID, completion in
                Task {
                    for host in await SSDPDiscovery().discover() {
                        if let info = try? await DeviceInfoClient().fetch(host: host), info.id == deviceID {
                            completion(host)
                            return
                        }
                    }
                    completion(nil)
                }
            }
        )
        NSApp.mainMenu = MainMenu.make()
        presence.onOpenSettings = { [weak self] in self?.showWindow() }

        coordinator.$linkState
            .combineLatest(coordinator.$monitorIsOutput, coordinator.$accessibilityGranted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] link, isOutput, granted in
                self?.presence.update(link: link, monitorIsOutput: isOutput, accessibilityGranted: granted)
            }
            .store(in: &subscriptions)

        coordinator.$showSettings
            .filter { $0 }
            .sink { [weak self] _ in
                self?.showWindow()
                self?.coordinator.showSettings = false
            }
            .store(in: &subscriptions)

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.coordinator.handleWake()
        }

        // A new network (Wi-Fi roam, VPN, Ethernet) invalidates the socket; reconnect right away.
        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self else { return }
                defer { self.lastPathStatus = path.status }
                if self.lastPathStatus != nil, path.status == .satisfied { self.coordinator.handleWake() }
            }
        }
        pathMonitor.start(queue: .global(qos: .utility))

        coordinator.start()
        if !coordinator.setupComplete { showWindow() }
    }

    /// Opening the app again (Dock, Finder, Spotlight) brings up Settings, which is how
    /// people reach it in Background mode.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator.handleReopen()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func showWindow() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = SmartVolumeInfo.appName
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: RootView(coordinator: coordinator))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
