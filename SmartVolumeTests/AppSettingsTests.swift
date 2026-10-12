import XCTest
@testable import SmartVolume

final class AppSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "SmartVolumeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDefaultsMenuBarAndStartAtLoginTrue() {
        let store = UserDefaultsSettingsStore(defaults: defaults)
        XCTAssertEqual(store.presenceMode, .menuBar)
        XCTAssertTrue(store.startAtLogin)
        XCTAssertFalse(store.setupComplete)
        XCTAssertNil(store.pairedMonitor)
    }

    func testValuesPersist() {
        let store = UserDefaultsSettingsStore(defaults: defaults)
        store.presenceMode = .background
        store.startAtLogin = false
        store.setupComplete = true
        let reloaded = UserDefaultsSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.presenceMode, .background)
        XCTAssertFalse(reloaded.startAtLogin)
        XCTAssertTrue(reloaded.setupComplete)
    }

    func testPairedMonitorRoundTrip() {
        let store = UserDefaultsSettingsStore(defaults: defaults)
        let monitor = PairedMonitor(deviceID: "uuid:1", host: "10.0.0.5", name: "M7", outputUID: "DP-UID")
        store.pairedMonitor = monitor
        XCTAssertEqual(UserDefaultsSettingsStore(defaults: defaults).pairedMonitor, monitor)
        store.pairedMonitor = nil
        XCTAssertNil(store.pairedMonitor)
    }

    func testBackgroundNotAllowedUnpaired() {
        XCTAssertEqual(PresenceRules.allowedModes(paired: false), [.dock, .menuBar])
        XCTAssertEqual(PresenceRules.allowedModes(paired: true), [.dock, .menuBar, .background])
    }
}
