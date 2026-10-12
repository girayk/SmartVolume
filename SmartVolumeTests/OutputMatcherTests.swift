import XCTest
@testable import SmartVolume

final class OutputMatcherTests: XCTestCase {
    let monitor = PairedMonitor(deviceID: "uuid:1", host: "192.168.1.20", name: "M7")

    func testMatchesByUID() {
        var paired = monitor
        paired.outputUID = "DP-UID"
        XCTAssertTrue(OutputMatcher.isMonitor(AudioOutput(uid: "DP-UID", name: "LS43BM70", transport: .displayPort), paired: paired))
        XCTAssertFalse(OutputMatcher.isMonitor(AudioOutput(uid: "OTHER", name: "SAMSUNG", transport: .displayPort), paired: paired))
    }

    func testMatchesSamsungOverDisplayPortWithoutUID() {
        XCTAssertTrue(OutputMatcher.isMonitor(AudioOutput(uid: "x", name: "SAMSUNG", transport: .displayPort), paired: monitor))
        XCTAssertTrue(OutputMatcher.isMonitor(AudioOutput(uid: "x", name: "Smart M7", transport: .hdmi), paired: monitor))
    }

    func testRejectsBuiltInSpeakers() {
        XCTAssertFalse(OutputMatcher.isMonitor(AudioOutput(uid: "BuiltIn", name: "MacBook Pro Speakers", transport: .builtIn), paired: monitor))
    }

    func testRejectsSamsungNamedBluetooth() {
        XCTAssertFalse(OutputMatcher.isMonitor(AudioOutput(uid: "bt", name: "Samsung Buds", transport: .bluetooth), paired: monitor))
    }

    func testNilOutputOrUnpairedIsFalse() {
        XCTAssertFalse(OutputMatcher.isMonitor(nil, paired: monitor))
        XCTAssertFalse(OutputMatcher.isMonitor(AudioOutput(uid: "x", name: "SAMSUNG", transport: .displayPort), paired: nil))
    }

    func testDisplayNameDecodesHTMLEntities() {
        let monitor = PairedMonitor(deviceID: "uuid:1", host: "h", name: "43&quot; Smart Monitor M7")
        XCTAssertEqual(monitor.displayName, "43\" Smart Monitor M7")
        XCTAssertEqual(PairedMonitor(deviceID: "x", host: "h", name: "A &amp; B &lt;1&gt; &#39;x&#39;").displayName, "A & B <1> 'x'")
        XCTAssertEqual(PairedMonitor(deviceID: "x", host: "h", name: "[Monitor] Samsung M7").displayName, "Samsung M7")
    }
}
