import XCTest
@testable import SmartVolume

final class SamsungRemoteTests: XCTestCase {
    func testURLWithoutToken() {
        XCTAssertEqual(SamsungRemote.url(host: "192.168.1.20", appName: "SmartVolume", token: nil).absoluteString,
                       "wss://192.168.1.20:8002/api/v2/channels/samsung.remote.control?name=U21hcnRWb2x1bWU=")
    }

    func testURLWithToken() {
        XCTAssertTrue(SamsungRemote.url(host: "192.168.1.20", appName: "SmartVolume", token: "abc").absoluteString.hasSuffix("&token=abc"))
    }

    func testURLCustomSchemeAndPort() {
        XCTAssertTrue(SamsungRemote.url(host: "127.0.0.1", appName: "SmartVolume", token: nil, scheme: "ws", port: 9000).absoluteString.hasPrefix("ws://127.0.0.1:9000/"))
    }

    func testClickCommandJSON() throws {
        let object = try JSONSerialization.jsonObject(with: SamsungRemote.clickCommand(.volUp)) as? [String: Any]
        XCTAssertEqual(object?["method"] as? String, "ms.remote.control")
        let params = object?["params"] as? [String: String]
        XCTAssertEqual(params, ["Cmd": "Click", "DataOfCmd": "KEY_VOLUP", "Option": "false", "TypeOfRemote": "SendRemoteKey"])
    }

    func testParseConnectWithToken() {
        XCTAssertEqual(SamsungRemote.parse(#"{"event":"ms.channel.connect","data":{"token":"12345678"}}"#), .connected(token: "12345678"))
    }

    func testParseConnectWithoutToken() {
        XCTAssertEqual(SamsungRemote.parse(#"{"event":"ms.channel.connect","data":{"clients":[]}}"#), .connected(token: nil))
    }

    func testParseUnauthorized() {
        XCTAssertEqual(SamsungRemote.parse(#"{"event":"ms.channel.unauthorized"}"#), .unauthorized)
    }

    func testParseTimeOut() {
        XCTAssertEqual(SamsungRemote.parse(#"{"event":"ms.channel.timeOut"}"#), .timedOut)
    }

    func testParseGarbage() {
        XCTAssertEqual(SamsungRemote.parse("not json"), .other)
        XCTAssertEqual(SamsungRemote.parse(#"{"event":"ms.channel.clientConnect"}"#), .other)
    }
}

final class BackoffTests: XCTestCase {
    func testBackoffSequenceAndCap() {
        var backoff = Backoff()
        XCTAssertEqual((0..<8).map { _ in backoff.next() }, [1, 2, 4, 8, 16, 30, 30, 30])
    }

    func testBackoffReset() {
        var backoff = Backoff()
        _ = backoff.next(); _ = backoff.next()
        backoff.reset()
        XCTAssertEqual(backoff.next(), 1)
    }
}
