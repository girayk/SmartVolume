import XCTest
@testable import SmartVolume

final class MediaKeyTests: XCTestCase {
    func testDecodeVolumeUpDown() {
        XCTAssertEqual(MediaKeyEvent.decode(subtype: 8, data1: 0x000A00),
                       MediaKeyEvent(key: .volumeUp, isDown: true, isRepeat: false))
        XCTAssertEqual(MediaKeyEvent.decode(subtype: 8, data1: 0x010A00),
                       MediaKeyEvent(key: .volumeDown, isDown: true, isRepeat: false))
    }

    func testDecodeMuteKeyUp() {
        XCTAssertEqual(MediaKeyEvent.decode(subtype: 8, data1: 0x070B00),
                       MediaKeyEvent(key: .mute, isDown: false, isRepeat: false))
    }

    func testDecodeIgnoresOtherSubtypes() {
        XCTAssertNil(MediaKeyEvent.decode(subtype: 7, data1: 0x000A00))
    }

    func testDecodeIgnoresOtherKeys() {
        XCTAssertNil(MediaKeyEvent.decode(subtype: 8, data1: 0x100A00)) // NX_KEYTYPE_PLAY
    }

    func testRepeatFlag() {
        XCTAssertEqual(MediaKeyEvent.decode(subtype: 8, data1: 0x000A01)?.isRepeat, true)
    }
}
