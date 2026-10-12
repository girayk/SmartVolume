import XCTest
@testable import SmartVolume

final class EventTapKeyInterceptorTests: XCTestCase {
    func testHandleSwallowsAndSends() {
        let interceptor = EventTapKeyInterceptor()
        var sent: [RemoteKey] = []
        interceptor.onKey = { InterceptPolicy.action(for: $0, tapActive: true) }
        interceptor.onSend = { sent.append($0) }
        XCTAssertTrue(interceptor.handle(subtype: 8, data1: 0x000A00))
        XCTAssertEqual(sent, [.volUp])
    }

    func testHandlePassesWhenOnKeyReturnsPass() {
        let interceptor = EventTapKeyInterceptor()
        var sent: [RemoteKey] = []
        interceptor.onKey = { _ in .pass }
        interceptor.onSend = { sent.append($0) }
        XCTAssertFalse(interceptor.handle(subtype: 8, data1: 0x000A00))
        XCTAssertTrue(sent.isEmpty)
    }

    func testHandlePassesNonVolumeKeys() {
        let interceptor = EventTapKeyInterceptor()
        interceptor.onKey = { _ in .swallow(send: nil) }
        XCTAssertFalse(interceptor.handle(subtype: 8, data1: 0x100A00))
    }

    func testDisabledByTimeoutReenablesOnlyWhenEnabled() {
        let interceptor = EventTapKeyInterceptor()
        var calls: [Bool] = []
        interceptor.tapEnabler = { calls.append($0) }

        interceptor.handleSystemDisable()
        XCTAssertEqual(calls, [], "a tap that should be off stays off")

        interceptor.setEnabled(false)
        calls.removeAll()
        interceptor.handleSystemDisable()
        XCTAssertEqual(calls, [])
    }

    func testDisabledByTimeoutReenablesWhenActive() {
        let interceptor = EventTapKeyInterceptor()
        var calls: [Bool] = []
        interceptor.tapEnabler = { calls.append($0) }
        // Mark enabled without creating a real tap (no Accessibility permission on CI).
        interceptor.markEnabledForTesting()
        interceptor.handleSystemDisable()
        XCTAssertEqual(calls, [true])
    }

    func testTapOnlyListens() {
        XCTAssertEqual(EventTapKeyInterceptor.tapOptions, .listenOnly, "a sandboxed app can only listen")
        XCTAssertEqual(KeyPermission.settingsName, "Input Monitoring")
    }
}
