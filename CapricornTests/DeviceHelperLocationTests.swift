// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import Capricorn

final class DeviceHelperLocationTests: XCTestCase {
    func testPermanentLocalLocationsAreNotRestrictedToApplications() {
        for path in ["/Applications/Capricorn.app", "/Applications/Utilities/Capricorn.app",
                     "/Users/example/Applications/Capricorn.app", "/Users/example/Desktop/Capricorn.app",
                     "/Users/example/Tools/Capricorn.app"] {
            XCTAssertNoThrow(try DeviceHelperLocation.validate(path: path, isLocal: true, isReadOnly: false, isRemovable: false))
        }
    }

    func testTemporaryTranslocatedReadOnlyAndUnavailableVolumesAreRejected() {
        for path in ["/tmp/Capricorn.app", "/private/tmp/test/Capricorn.app",
                     "/var/folders/abc/Capricorn.app", "/private/var/folders/abc/Capricorn.app",
                     "/somewhere/AppTranslocation/abc/d/Capricorn.app", "/Applications/Capricorn"] {
            XCTAssertThrowsError(try DeviceHelperLocation.validate(path: path, isLocal: true, isReadOnly: false, isRemovable: false))
        }
        let path = "/Volumes/Test/Capricorn.app"
        XCTAssertThrowsError(try DeviceHelperLocation.validate(path: path, isLocal: true, isReadOnly: true, isRemovable: false))
        XCTAssertThrowsError(try DeviceHelperLocation.validate(path: path, isLocal: false, isReadOnly: false, isRemovable: false))
        XCTAssertThrowsError(try DeviceHelperLocation.validate(path: path, isLocal: true, isReadOnly: false, isRemovable: true))
    }
}
