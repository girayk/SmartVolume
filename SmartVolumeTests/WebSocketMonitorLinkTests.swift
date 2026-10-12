import XCTest
@testable import SmartVolume

final class WebSocketMonitorLinkTests: XCTestCase {
    private var server: FakeSamsungServer!
    private var tokens: InMemoryTokenStore!
    private var scheduler: FakeScheduler!
    private var link: WebSocketMonitorLink!
    private var states: [LinkState] = []
    private let monitor = PairedMonitor(deviceID: "uuid:m7", host: "127.0.0.1", name: "M7")

    override func setUpWithError() throws {
        tokens = InMemoryTokenStore()
        scheduler = FakeScheduler()
        states = []
    }

    override func tearDown() {
        link?.disconnect()
        server?.stop()
    }

    private func makeLink(mode: FakeSamsungServer.Mode, tokens store: TokenStoring? = nil) throws {
        server = try FakeSamsungServer(mode: mode)
        server.start()
        link = WebSocketMonitorLink(tokens: store ?? tokens, scheme: "ws", port: server.port, clock: scheduler)
    }

    private func waitForState(_ target: LinkState, file: StaticString = #filePath, line: UInt = #line) {
        let reached = expectation(description: "state \(target)")
        reached.assertForOverFulfill = false
        link.onStateChange = { [weak self] state in
            self?.states.append(state)
            if state == target { reached.fulfill() }
        }
        if link.state == target { reached.fulfill() }
        wait(for: [reached], timeout: 5)
    }

    private func connectAndWait() {
        let reached = expectation(description: "connected")
        reached.assertForOverFulfill = false
        link.onStateChange = { [weak self] state in
            self?.states.append(state)
            if state == .connected { reached.fulfill() }
        }
        link.connect(to: monitor)
        wait(for: [reached], timeout: 5)
    }

    func testConnectSavesTokenAndBecomesConnected() throws {
        try makeLink(mode: .accept(token: "tok1"))
        connectAndWait()
        XCTAssertEqual(link.state, .connected)
        XCTAssertEqual(tokens.token(for: "uuid:m7"), "tok1")
        XCTAssertEqual(states.first, .connecting)
    }

    func testSendsClickCommand() throws {
        try makeLink(mode: .accept(token: "tok1"))
        connectAndWait()
        let received = expectation(description: "command received")
        var command: String?
        server.onReceive = { text in command = text; received.fulfill() }
        link.send(.volUp)
        wait(for: [received], timeout: 5)
        let object = try JSONSerialization.jsonObject(with: Data(command!.utf8)) as? [String: Any]
        XCTAssertEqual((object?["params"] as? [String: Any])?["DataOfCmd"] as? String, "KEY_VOLUP")
    }

    func testSendIgnoredWhenNotConnected() throws {
        try makeLink(mode: .accept(token: nil))
        server.onReceive = { _ in XCTFail("nothing should be sent") }
        link.send(.volUp)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    }

    func testUnauthorizedEventClearsToken() throws {
        try makeLink(mode: .reject)
        tokens.save("old", for: "uuid:m7")
        let reached = expectation(description: "unpaired after connecting")
        link.onStateChange = { [weak self] state in
            self?.states.append(state)
            if state == .unpaired { reached.fulfill() }
        }
        link.connect(to: monitor)
        wait(for: [reached], timeout: 5)
        XCTAssertEqual(states, [.connecting, .unpaired])
        XCTAssertNil(tokens.token(for: "uuid:m7"))
        XCTAssertFalse(scheduler.delays.contains(1), "a rejected pairing must not retry")
    }

    func testSendFailureMarksUnreachable() throws {
        try makeLink(mode: .accept(token: "tok1"))
        connectAndWait()
        server.dropConnections()
        link.send(.volUp)
        waitForState(.unreachable)
        XCTAssertEqual(link.state, .unreachable)
    }

    func testReconnectsWithBackoff() throws {
        try makeLink(mode: .accept(token: "tok1"))
        connectAndWait()
        server.dropConnections()
        waitForState(.unreachable)
        XCTAssertEqual(scheduler.delays.last, 1)

        // Running the scheduled reconnect brings the link back.
        let reconnect = scheduler.scheduled.last!
        let back = expectation(description: "reconnected")
        back.assertForOverFulfill = false
        link.onStateChange = { state in if state == .connected { back.fulfill() } }
        reconnect.block()
        wait(for: [back], timeout: 5)
    }

    func testWakeTriggersReconnect() throws {
        try makeLink(mode: .accept(token: "tok1"))
        connectAndWait()
        let newConnection = expectation(description: "new connection")
        server.onConnection = { newConnection.fulfill() }
        var seen: [LinkState] = []
        let back = expectation(description: "connected again")
        back.assertForOverFulfill = false
        link.onStateChange = { state in
            seen.append(state)
            if state == .connected { back.fulfill() }
        }
        link.handleSystemWake()
        wait(for: [newConnection, back], timeout: 5)
        XCTAssertEqual(seen.first, .connecting)
    }

    // MARK: Dead connections (review finding 1)

    func testMissingPongMarksUnreachable() throws {
        try makeLink(mode: .accept(token: "tok1"))
        connectAndWait()
        let ping = try XCTUnwrap(scheduler.scheduled.last { $0.delay == 20 })
        ping.block()
        let deadline = try XCTUnwrap(scheduler.scheduled.last { $0.delay == 5 }, "a pong deadline is armed")
        deadline.block() // the pong hasn't been processed yet
        XCTAssertEqual(link.state, .unreachable)
    }

    func testPongCancelsDeadline() throws {
        try makeLink(mode: .accept(token: "tok1"))
        connectAndWait()
        try XCTUnwrap(scheduler.scheduled.last { $0.delay == 20 }).block()
        let deadline = try XCTUnwrap(scheduler.scheduled.last { $0.delay == 5 })
        let cancelled = expectation(description: "pong cancels the deadline")
        let poll = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            if deadline.cancelled { cancelled.fulfill() }
        }
        wait(for: [cancelled], timeout: 5)
        poll.invalidate()
        XCTAssertEqual(link.state, .connected)
    }

    func testSendArmsPongDeadline() throws {
        try makeLink(mode: .accept(token: "tok1"))
        connectAndWait()
        link.send(.volUp)
        XCTAssertTrue(scheduler.scheduled.contains { $0.delay == 5 && !$0.cancelled }, "a key press probes the connection")
    }

    // MARK: Pairing without an answer (review finding 2)

    func testTimeOutEventStopsWithoutRetry() throws {
        try makeLink(mode: .timeOut)
        tokens.save("keep", for: "uuid:m7")
        let reached = expectation(description: "unpaired")
        link.onStateChange = { if $0 == .unpaired { reached.fulfill() } }
        link.connect(to: monitor)
        wait(for: [reached], timeout: 5)
        XCTAssertEqual(tokens.token(for: "uuid:m7"), "keep", "a timed-out prompt isn't a revocation")
        XCTAssertFalse(scheduler.scheduled.contains { $0.delay == 1 && !$0.cancelled }, "no automatic retry")
    }

    func testConnectDeadlineWithoutTokenStopsAsUnpaired() throws {
        try makeLink(mode: .silent)
        link.connect(to: monitor)
        let deadline = try XCTUnwrap(scheduler.scheduled.last { $0.delay == 35 }, "a connect deadline is armed")
        deadline.block()
        XCTAssertEqual(link.state, .unpaired)
        XCTAssertFalse(scheduler.scheduled.contains { $0.delay == 1 && !$0.cancelled })
    }

    func testConnectDeadlineWithTokenRetries() throws {
        try makeLink(mode: .silent)
        tokens.save("tok1", for: "uuid:m7")
        link.connect(to: monitor)
        try XCTUnwrap(scheduler.scheduled.last { $0.delay == 35 }).block()
        XCTAssertEqual(link.state, .unreachable)
        XCTAssertEqual(scheduler.scheduled.last?.delay, 1)
    }

    // MARK: Keychain reads off the main thread

    func testWakeWhileTokenLoadsWaitsForToken() throws {
        let slowTokens = DeferredTokenStore()
        slowTokens.stored = "tok1"
        try makeLink(mode: .silent, tokens: slowTokens)
        link.connect(to: monitor)
        XCTAssertEqual(link.state, .connecting)
        link.handleSystemWake()
        XCTAssertTrue(scheduler.scheduled.isEmpty, "no socket opens before the token arrives")

        slowTokens.release()
        // With a token, a missed connect deadline retries instead of stopping, so this proves the token was used.
        try XCTUnwrap(scheduler.scheduled.last { $0.delay == 35 }).block()
        XCTAssertEqual(link.state, .unreachable)
    }

    func testNoAutoReconnectWithoutToken() throws {
        try makeLink(mode: .accept(token: nil))
        connectAndWait()
        XCTAssertNil(tokens.token(for: "uuid:m7"))
        server.dropConnections()
        waitForState(.unpaired)
        XCTAssertFalse(scheduler.scheduled.contains { $0.delay == 1 && !$0.cancelled }, "never raise a new Allow prompt on its own")
    }
}
