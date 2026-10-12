import Combine
import Foundation

public enum PresenceError: Error, Equatable {
    case requiresPairing
}

/// Wires the output watcher, key interceptor and monitor link together, and owns the app's settings.
/// Call from the main thread.
public final class AppCoordinator: ObservableObject {
    @Published public private(set) var linkState: LinkState = .unpaired
    @Published public private(set) var monitorIsOutput = false
    @Published public private(set) var currentOutput: AudioOutput?
    @Published public private(set) var accessibilityGranted = false
    @Published public private(set) var pairedMonitor: PairedMonitor?
    @Published public private(set) var presenceMode: PresenceMode
    @Published public private(set) var startAtLogin: Bool
    @Published public private(set) var setupComplete: Bool
    @Published public var showSettings = false

    private let settings: SettingsStore
    private let output: OutputWatching
    private let keys: KeyIntercepting
    private let link: MonitorLinking
    private let tokens: TokenStoring
    private let accessibility: () -> Bool
    private let presence: PresenceApplying
    private let loginItem: LoginItemControlling
    private let rediscover: (_ deviceID: String, _ completion: @escaping (String?) -> Void) -> Void
    private var permissionTimer: Timer?
    private var failedAttempts = 0
    private var rediscovering = false

    /// Consecutive unreachable attempts before looking for the monitor at a new address.
    static let attemptsBeforeRediscovery = 3

    public init(
        settings: SettingsStore,
        output: OutputWatching,
        keys: KeyIntercepting,
        link: MonitorLinking,
        tokens: TokenStoring,
        accessibility: @escaping () -> Bool,
        presence: PresenceApplying,
        loginItem: LoginItemControlling,
        rediscover: @escaping (_ deviceID: String, _ completion: @escaping (String?) -> Void) -> Void = { _, done in done(nil) }
    ) {
        self.settings = settings
        self.output = output
        self.keys = keys
        self.link = link
        self.tokens = tokens
        self.accessibility = accessibility
        self.presence = presence
        self.loginItem = loginItem
        self.rediscover = rediscover
        pairedMonitor = settings.pairedMonitor
        presenceMode = settings.presenceMode
        startAtLogin = settings.startAtLogin
        setupComplete = settings.setupComplete
    }

    deinit {
        permissionTimer?.invalidate()
    }

    public var tapActive: Bool {
        InterceptPolicy.tapShouldBeActive(monitorIsOutput: monitorIsOutput, link: linkState, accessibilityGranted: accessibilityGranted)
    }

    public func start() {
        output.onChange = { [weak self] output in self?.outputChanged(output) }
        link.onStateChange = { [weak self] state in
            self?.linkStateChanged(state)
        }
        keys.onKey = { [weak self] event in
            InterceptPolicy.action(for: event, tapActive: self?.tapActive ?? false)
        }
        keys.onSend = { [weak self] key in self?.link.send(key) }

        accessibilityGranted = accessibility()
        output.start()
        outputChanged(output.current)

        // Never start hidden without a working pairing.
        let mode = PresenceRules.allowedModes(paired: pairedMonitor != nil).contains(presenceMode) ? presenceMode : .menuBar
        presence.apply(mode)

        if let monitor = pairedMonitor {
            link.connect(to: monitor)
        }
        linkState = link.state
        updateTap()

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshAccessibility()
        }
    }

    public func refreshAccessibility() {
        let granted = accessibility()
        guard granted != accessibilityGranted else { return }
        accessibilityGranted = granted
        updateTap()
    }

    public func setPresence(_ mode: PresenceMode) throws {
        guard PresenceRules.allowedModes(paired: pairedMonitor != nil).contains(mode) else {
            throw PresenceError.requiresPairing
        }
        settings.presenceMode = mode
        presenceMode = mode
        presence.apply(mode)
    }

    public func setStartAtLogin(_ enabled: Bool) {
        settings.startAtLogin = enabled
        startAtLogin = enabled
        try? loginItem.setEnabled(enabled)
    }

    public func handleReopen() {
        showSettings = true
    }

    public func handleWake() {
        link.handleSystemWake()
    }

    /// Saves the monitor and starts pairing. Pass the host and identity found by discovery.
    public func pair(with monitor: PairedMonitor) {
        var monitor = monitor
        if let existing = pairedMonitor, existing.deviceID == monitor.deviceID, monitor.outputUID == nil {
            monitor.outputUID = existing.outputUID
        }
        savePairedMonitor(monitor)
        link.connect(to: monitor)
    }

    public func retryPairing() {
        guard let monitor = pairedMonitor else { return }
        link.connect(to: monitor)
    }

    /// Remembers the current output as the monitor's speakers, so matching no longer relies on its name.
    public func useCurrentOutputAsMonitor() {
        guard var monitor = pairedMonitor, let current = output.current else { return }
        monitor.outputUID = current.uid
        savePairedMonitor(monitor)
    }

    public func completeSetup(mode: PresenceMode) throws {
        try setPresence(mode)
        settings.setupComplete = true
        setupComplete = true
        setStartAtLogin(true)
    }

    public func forgetMonitor() {
        if let monitor = pairedMonitor { tokens.delete(for: monitor.deviceID) }
        link.disconnect()
        savePairedMonitor(nil)
        if presenceMode == .background { try? setPresence(.menuBar) }
        settings.setupComplete = false
        setupComplete = false
    }

    // MARK: - Private

    private func linkStateChanged(_ state: LinkState) {
        linkState = state
        updateTap()
        switch state {
        case .connected, .unpaired:
            failedAttempts = 0
        case .unreachable:
            failedAttempts += 1
            if failedAttempts >= Self.attemptsBeforeRediscovery { findMonitorAtNewAddress() }
        case .connecting:
            break
        }
    }

    /// The monitor may have a new IP address after a DHCP change. Look for it by its device ID.
    private func findMonitorAtNewAddress() {
        guard !rediscovering, let monitor = pairedMonitor else { return }
        rediscovering = true
        failedAttempts = 0
        rediscover(monitor.deviceID) { [weak self] host in
            DispatchQueue.main.async {
                guard let self else { return }
                self.rediscovering = false
                guard let host, var current = self.pairedMonitor,
                      current.deviceID == monitor.deviceID, current.host != host
                else { return }
                current = PairedMonitor(deviceID: current.deviceID, host: host, name: current.name, outputUID: current.outputUID)
                self.savePairedMonitor(current)
                self.link.connect(to: current)
            }
        }
    }

    private func savePairedMonitor(_ monitor: PairedMonitor?) {
        settings.pairedMonitor = monitor
        pairedMonitor = monitor
        outputChanged(output.current)
    }

    private func outputChanged(_ newOutput: AudioOutput?) {
        currentOutput = newOutput
        monitorIsOutput = OutputMatcher.isMonitor(newOutput, paired: pairedMonitor)
        updateTap()
    }

    private func updateTap() {
        let active = tapActive
        if keys.isEnabled != active { keys.setEnabled(active) }
    }
}
