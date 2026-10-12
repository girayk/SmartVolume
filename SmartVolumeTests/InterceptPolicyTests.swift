import XCTest
@testable import SmartVolume

final class InterceptPolicyTests: XCTestCase {
    func testTapInactiveWhenLinkNotConnected() {
        for state in [LinkState.unpaired, .connecting, .unreachable] {
            XCTAssertFalse(InterceptPolicy.tapShouldBeActive(monitorIsOutput: true, link: state, accessibilityGranted: true), "\(state)")
        }
    }

    func testTapInactiveWhenNotOutput() {
        XCTAssertFalse(InterceptPolicy.tapShouldBeActive(monitorIsOutput: false, link: .connected, accessibilityGranted: true))
    }

    func testTapInactiveWithoutAccessibility() {
        XCTAssertFalse(InterceptPolicy.tapShouldBeActive(monitorIsOutput: true, link: .connected, accessibilityGranted: false))
    }

    func testTapActiveOnlyWhenAllTrue() {
        XCTAssertTrue(InterceptPolicy.tapShouldBeActive(monitorIsOutput: true, link: .connected, accessibilityGranted: true))
    }

    func testVolumeKeysSendCommands() {
        XCTAssertEqual(InterceptPolicy.action(for: .init(key: .volumeUp, isDown: true, isRepeat: false), tapActive: true), .swallow(send: .volUp))
        XCTAssertEqual(InterceptPolicy.action(for: .init(key: .volumeDown, isDown: true, isRepeat: false), tapActive: true), .swallow(send: .volDown))
        XCTAssertEqual(InterceptPolicy.action(for: .init(key: .mute, isDown: true, isRepeat: false), tapActive: true), .swallow(send: .mute))
    }

    func testHeldVolumeRepeats() {
        XCTAssertEqual(InterceptPolicy.action(for: .init(key: .volumeUp, isDown: true, isRepeat: true), tapActive: true), .swallow(send: .volUp))
    }

    func testMuteRepeatSendsNothing() {
        XCTAssertEqual(InterceptPolicy.action(for: .init(key: .mute, isDown: true, isRepeat: true), tapActive: true), .swallow(send: nil))
    }

    func testKeyUpIsSwallowedSilently() {
        XCTAssertEqual(InterceptPolicy.action(for: .init(key: .volumeUp, isDown: false, isRepeat: false), tapActive: true), .swallow(send: nil))
    }

    func testPassWhenInactive() {
        XCTAssertEqual(InterceptPolicy.action(for: .init(key: .volumeUp, isDown: true, isRepeat: false), tapActive: false), .pass)
    }

    func testTapReenableOnlyWhenActive() {
        XCTAssertTrue(InterceptPolicy.shouldReenableAfterSystemDisable(tapShouldBeActive: true))
        XCTAssertFalse(InterceptPolicy.shouldReenableAfterSystemDisable(tapShouldBeActive: false))
    }
}
