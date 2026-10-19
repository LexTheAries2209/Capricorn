import XCTest
@testable import Capricorn

final class WorkloadSizePreferencesTests: XCTestCase {
    func testNewDrivesDefaultTo128GiBAndChoicesPersistIndependently() throws {
        var first = CapricornTests.fixtureDrive()
        first.serialNumber = "WORKLOAD-FIRST"
        var second = first
        second.serialNumber = "WORKLOAD-SECOND"
        var preferences = DiskActivityWorkloadSizePreferences()
        XCTAssertEqual(preferences.selection(for: first), .gib128)
        preferences.setSelection(.gib256, for: first)
        preferences.setSelection(.gib32, for: second)
        let suite = "Capricorn.WorkloadSizeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(preferences.encoded(), forKey: DiskActivityWorkloadSizePreferences.defaultsKey)
        let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
        let restored = DiskActivityWorkloadSizePreferences.decode(reopened.string(forKey: DiskActivityWorkloadSizePreferences.defaultsKey) ?? "")
        XCTAssertEqual(restored.selection(for: first), .gib256)
        XCTAssertEqual(restored.selection(for: second), .gib32)
        first.bsdName = "disk99"
        XCTAssertEqual(restored.selection(for: first), .gib256)
    }

    func testInsufficientSpaceUsesSmallerFixedSizeWithoutChangingMemory() {
        let drive = CapricornTests.fixtureDrive()
        let preferences = DiskActivityWorkloadSizePreferences()
        let margin = DiskActivityWorkloadStorageValidator.safetyMarginBytes
        let capacity = DiskActivityWorkloadFileSize.gib64.fixedBytes! + margin
        XCTAssertEqual(preferences.availableSelection(for: drive, operation: .write, availableCapacity: capacity), .gib64)
        XCTAssertEqual(preferences.availableSelection(for: drive, operation: .mixed, availableCapacity: capacity), .gib32)
        XCTAssertEqual(preferences.selection(for: drive), .gib128)
        XCTAssertEqual(preferences.availableSelection(for: drive, operation: .write, availableCapacity: 1024 * 1024 * 1024 * 1024), .gib128)
    }

    func testFullDiskRequiresExplicitChoiceAndMissingCapacityDoesNotOverrideIt() {
        let drive = CapricornTests.fixtureDrive()
        var preferences = DiskActivityWorkloadSizePreferences()
        XCTAssertEqual(preferences.availableSelection(for: drive, operation: .write, availableCapacity: nil), .gib128)
        preferences.setSelection(.fullDisk95, for: drive)
        let restored = DiskActivityWorkloadSizePreferences.decode(preferences.encoded())
        XCTAssertEqual(restored.selection(for: drive), .fullDisk95)
    }

    func testCorruptPreferencesIgnoreLegacyGlobalFullDiskSetting() throws {
        let drive = CapricornTests.fixtureDrive()
        XCTAssertEqual(DiskActivityWorkloadSizePreferences.decode("invalid").selection(for: drive), .gib128)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "Capricorn.WorkloadLegacyTests.\(UUID().uuidString)"))
        defaults.set("fullDisk95", forKey: "diskActivityWorkloadFileSize")
        XCTAssertEqual(
            DiskActivityWorkloadSizePreferences.decode(defaults.string(forKey: DiskActivityWorkloadSizePreferences.defaultsKey) ?? "").selection(for: drive),
            .gib128
        )
    }
}
