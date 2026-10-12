import CoreAudio
import XCTest
@testable import SmartVolume

final class CoreAudioOutputWatcherTests: XCTestCase {
    func testTransportMapping() {
        XCTAssertEqual(CoreAudioOutputWatcher.transport(from: kAudioDeviceTransportTypeDisplayPort), .displayPort)
        XCTAssertEqual(CoreAudioOutputWatcher.transport(from: kAudioDeviceTransportTypeHDMI), .hdmi)
        XCTAssertEqual(CoreAudioOutputWatcher.transport(from: kAudioDeviceTransportTypeBuiltIn), .builtIn)
        XCTAssertEqual(CoreAudioOutputWatcher.transport(from: kAudioDeviceTransportTypeBluetooth), .bluetooth)
        XCTAssertEqual(CoreAudioOutputWatcher.transport(from: 0), .other)
    }

    func testCurrentOutputReadable() throws {
        let watcher = CoreAudioOutputWatcher()
        watcher.start()
        guard let output = watcher.current else { throw XCTSkip("no audio output on this machine") }
        XCTAssertFalse(output.uid.isEmpty)
    }
}

final class KeychainTokenStoreTests: XCTestCase {
    private let service = "com.scormy.smartvolume.tests.\(UUID().uuidString)"

    override func tearDown() {
        KeychainTokenStore(service: service).delete(for: "uuid:m7")
    }

    func testSaveReadDeleteToken() {
        let store = KeychainTokenStore(service: service)
        XCTAssertNil(read(store))
        store.save("abc", for: "uuid:m7")
        XCTAssertEqual(read(store), "abc")
        store.save("def", for: "uuid:m7")
        XCTAssertEqual(read(store), "def")
        store.delete(for: "uuid:m7")
        XCTAssertNil(read(store))
    }

    func testReadCallsBackOnMainThread() {
        let done = expectation(description: "read")
        KeychainTokenStore(service: service).token(for: "uuid:m7") { _ in
            XCTAssertTrue(Thread.isMainThread)
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
    }

    private func read(_ store: KeychainTokenStore) -> String? {
        let done = expectation(description: "read")
        var token: String?
        store.token(for: "uuid:m7") { token = $0; done.fulfill() }
        wait(for: [done], timeout: 2)
        return token
    }
}

final class DeviceInfoClientTests: XCTestCase {
    func testParseDeviceInfoSample() {
        let json = #"""
        {"device":{"id":"uuid:0b1c2d3e-aaaa-bbbb-cccc-111122223333","name":"[Monitor] Samsung M7 (43)","modelName":"LS43BM702UUXEN","type":"Samsung SmartTV"},"isSupport":"{}","name":"[Monitor] Samsung M7 (43)","type":"Samsung SmartTV","version":"2.0.25"}
        """#
        XCTAssertEqual(DeviceInfoClient.parse(Data(json.utf8)),
                       DeviceInfo(id: "uuid:0b1c2d3e-aaaa-bbbb-cccc-111122223333", name: "Samsung M7 (43)", model: "LS43BM702UUXEN"))
    }

    func testParseDecodesEntitiesInName() {
        let json = #"{"device":{"id":"uuid:1","name":"43&quot; Smart Monitor M7","modelName":"LS43"}}"#
        XCTAssertEqual(DeviceInfoClient.parse(Data(json.utf8))?.name, "43\" Smart Monitor M7")
    }

    func testParseRejectsMissingDevice() {
        XCTAssertNil(DeviceInfoClient.parse(Data(#"{"name":"x"}"#.utf8)))
    }
}

final class SSDPDiscoveryTests: XCTestCase {
    func testParseLocationHost() {
        let response = "HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nLOCATION: http://192.168.1.20:9197/dmr\r\nST: urn:samsung.com:device:RemoteControlReceiver:1\r\n\r\n"
        XCTAssertEqual(SSDPDiscovery.parseLocationHost(response), "192.168.1.20")
    }

    func testParseLocationLowercaseHeader() {
        XCTAssertEqual(SSDPDiscovery.parseLocationHost("HTTP/1.1 200 OK\r\nLocation: http://10.0.0.7:7676/smp_2_\r\n"), "10.0.0.7")
    }

    func testParseLocationMissing() {
        XCTAssertNil(SSDPDiscovery.parseLocationHost("HTTP/1.1 200 OK\r\nST: x\r\n"))
    }

    func testSearchMessageHasST() {
        XCTAssertTrue(SSDPDiscovery.searchMessage.contains("ST: urn:samsung.com:device:RemoteControlReceiver:1\r\n"))
        XCTAssertTrue(SSDPDiscovery.searchMessage.hasSuffix("\r\n\r\n"))
    }
}
