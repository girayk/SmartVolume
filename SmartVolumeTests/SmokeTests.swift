import XCTest
@testable import SmartVolume

final class SmokeTests: XCTestCase {
    func testPackageBuilds() {
        XCTAssertFalse(SmartVolumeInfo.version.isEmpty)
    }
}
