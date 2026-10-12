import XCTest
@testable import SmartVolume

final class AppCoordinatorTests: XCTestCase {
    private var settings: InMemorySettingsStore!
    private var output: FakeOutputWatcher!
    private var keys: FakeKeys!
    private var link: FakeLink!
    private var tokens: InMemoryTokenStore!
    private var presence: FakePresence!
    private var loginItem: FakeLoginItem!
    private var accessibilityGranted = true

    private let monitor = PairedMonitor(deviceID: "uuid:m7", host: "192.168.1.20", name: "M7", outputUID: "DP-UID")
    private let monitorOutput = AudioOutput(uid: "DP-UID", name: "LS43BM70", transport: .displayPort)
    private let speakers = AudioOutput(uid: "BuiltIn", name: "MacBook Pro Speakers", transport: .builtIn)

    override func setUp() {
        settings = InMemorySettingsStore()
        output = FakeOutputWatcher()
        keys = FakeKeys()
        link = FakeLink()
        tokens = InMemoryTokenStore()
        presence = FakePresence()
        loginItem = FakeLoginItem()
        accessibilityGranted = true
    }

    private var rediscoveredHost: String?
    private var rediscoverRequests: [String] = []

    private func makeCoordinator() -> AppCoordinator {
        AppCoordinator(
            settings: settings, output: output, keys: keys, link: link, tokens: tokens,
            accessibility: { [unowned self] in self.accessibilityGranted },
            presence: presence, loginItem: loginItem,
            rediscover: { [unowned self] id, done in
                self.rediscoverRequests.append(id)
                done(self.rediscoveredHost)
            }
        )
    }

    private func startPaired() -> AppCoordinator {
        settings.pairedMonitor = monitor
        settings.setupComplete = true
        output.current = monitorOutput
        let coordinator = makeCoordinator()
        coordinator.start()
        return coordinator
    }

    func testTapEnabledOnlyWhenOutputAndConnected() {
        let coordinator = startPaired()
        XCTAssertEqual(link.connected, [monitor])
        XCTAssertFalse(keys.isEnabled, "still connecting")
        link.state = .connected
        XCTAssertTrue(keys.isEnabled)
        XCTAssertTrue(coordinator.tapActive)
        link.state = .unreachable
        XCTAssertFalse(keys.isEnabled)
    }

    func testTapDisabledWhenOutputSwitchesAway() {
        let coordinator = startPaired()
        defer { withExtendedLifetime(coordinator) {} }
        link.state = .connected
        XCTAssertTrue(keys.isEnabled)
        output.emit(speakers)
        XCTAssertFalse(keys.isEnabled)
        output.emit(nil)
        XCTAssertFalse(keys.isEnabled)
        output.emit(monitorOutput)
        XCTAssertTrue(keys.isEnabled)
    }

    func testTapDisabledWhenAccessibilityRevoked() {
        let coordinator = startPaired()
        link.state = .connected
        XCTAssertTrue(keys.isEnabled)
        accessibilityGranted = false
        coordinator.refreshAccessibility()
        XCTAssertFalse(keys.isEnabled)
    }

    func testKeysPassWhenInactive() {
        let coordinator = startPaired()
        defer { withExtendedLifetime(coordinator) {} }
        XCTAssertEqual(keys.onKey?(MediaKeyEvent(key: .volumeUp, isDown: true, isRepeat: false)), .pass)
    }

    func testSendRoutesToLink() {
        let coordinator = startPaired()
        defer { withExtendedLifetime(coordinator) {} }
        link.state = .connected
        XCTAssertEqual(keys.onKey?(MediaKeyEvent(key: .volumeUp, isDown: true, isRepeat: false)), .swallow(send: .volUp))
        keys.onSend?(.volUp)
        XCTAssertEqual(link.sent, [.volUp])
    }

    func testBackgroundRejectedWhenUnpaired() {
        let coordinator = makeCoordinator()
        coordinator.start()
        XCTAssertThrowsError(try coordinator.setPresence(.background)) { error in
            XCTAssertEqual(error as? PresenceError, .requiresPairing)
        }
        XCTAssertEqual(settings.presenceMode, .menuBar)
    }

    func testBackgroundAllowedWhenPaired() throws {
        let coordinator = startPaired()
        try coordinator.setPresence(.background)
        XCTAssertEqual(settings.presenceMode, .background)
        XCTAssertEqual(presence.applied.last, .background)
    }

    func testPresenceAppliedOnStart() {
        settings.presenceMode = .dock
        makeCoordinator().start()
        XCTAssertEqual(presence.applied, [.dock])
    }

    func testStoredBackgroundWithoutPairingFallsBackToMenuBar() {
        settings.presenceMode = .background
        makeCoordinator().start()
        XCTAssertEqual(presence.applied, [.menuBar])
    }

    func testReopenShowsSettings() {
        let coordinator = startPaired()
        try? coordinator.setPresence(.background)
        coordinator.handleReopen()
        XCTAssertTrue(coordinator.showSettings)
    }

    func testWakeForwardsToLink() {
        let coordinator = startPaired()
        coordinator.handleWake()
        XCTAssertEqual(link.wakes, 1)
    }

    func testStartAtLoginAppliedAfterSetup() throws {
        let coordinator = makeCoordinator()
        coordinator.start()
        coordinator.pair(with: PairedMonitor(deviceID: "uuid:m7", host: "192.168.1.20", name: "M7"))
        try coordinator.completeSetup(mode: .background)
        XCTAssertTrue(settings.setupComplete)
        XCTAssertTrue(settings.startAtLogin)
        XCTAssertEqual(loginItem.enabled, true)
        XCTAssertEqual(settings.presenceMode, .background)
    }

    func testUseCurrentOutputRecordsUID() {
        let coordinator = makeCoordinator()
        coordinator.start()
        coordinator.pair(with: PairedMonitor(deviceID: "uuid:m7", host: "192.168.1.20", name: "[Monitor] Samsung M7 (43)"))
        output.emit(AudioOutput(uid: "DP-NEW", name: "LS43BM70", transport: .displayPort))
        XCTAssertFalse(coordinator.monitorIsOutput, "name doesn't match yet")
        coordinator.useCurrentOutputAsMonitor()
        XCTAssertEqual(settings.pairedMonitor?.outputUID, "DP-NEW")
        XCTAssertTrue(coordinator.monitorIsOutput)
    }

    func testForgetMonitorResetsEverything() {
        let coordinator = startPaired()
        tokens.save("tok", for: "uuid:m7")
        try? coordinator.setPresence(.background)
        link.state = .connected
        coordinator.forgetMonitor()
        XCTAssertNil(settings.pairedMonitor)
        XCTAssertNil(tokens.token(for: "uuid:m7"))
        XCTAssertEqual(settings.presenceMode, .menuBar)
        XCTAssertFalse(settings.setupComplete)
        XCTAssertFalse(keys.isEnabled)
    }

    // MARK: New IP address (review finding 3)

    func testRediscoversMonitorAfterRepeatedFailures() {
        let coordinator = startPaired()
        rediscoveredHost = "192.168.1.77"
        link.state = .unreachable
        link.state = .connecting
        link.state = .unreachable
        XCTAssertTrue(rediscoverRequests.isEmpty, "two failures aren't enough")
        link.state = .connecting
        link.state = .unreachable
        XCTAssertEqual(rediscoverRequests, ["uuid:m7"])

        let moved = expectation(description: "reconnects at the new address")
        DispatchQueue.main.async { moved.fulfill() }
        wait(for: [moved], timeout: 2)
        XCTAssertEqual(settings.pairedMonitor?.host, "192.168.1.77")
        XCTAssertEqual(settings.pairedMonitor?.outputUID, "DP-UID", "keeps the pinned output")
        XCTAssertEqual(link.connected.last?.host, "192.168.1.77")
        XCTAssertEqual(coordinator.pairedMonitor?.host, "192.168.1.77")
    }

    func testConnectedResetsFailureCount() {
        _ = startPairedRetained()
        link.state = .unreachable
        link.state = .unreachable
        link.state = .connected
        link.state = .unreachable
        link.state = .unreachable
        XCTAssertTrue(rediscoverRequests.isEmpty)
    }

    func testSameAddressDoesNotReconnect() {
        _ = startPairedRetained()
        rediscoveredHost = "192.168.1.20"
        let before = link.connected.count
        (0..<3).forEach { _ in link.state = .unreachable }
        let done = expectation(description: "main queue drained")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(link.connected.count, before)
    }

    private var retained: AppCoordinator?

    private func startPairedRetained() -> AppCoordinator {
        let coordinator = startPaired()
        retained = coordinator
        return coordinator
    }
}
