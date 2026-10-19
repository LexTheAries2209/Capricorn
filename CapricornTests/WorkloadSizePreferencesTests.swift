import XCTest
@testable import Capricorn

final class WorkloadSizePreferencesTests: XCTestCase {
    func testSizingHasNoByteCounterAndTransferRestoresMeasuredProgress() {
        var progress = DiskActivityWorkloadProgress(
            operation: .mixed, phase: .sizingFile, loopIndex: 1, completedBytes: 0,
            totalBytes: DiskActivityWorkloadFileSize.gib128.fixedBytes!, message: "Sizing workload file"
        )
        XCTAssertFalse(progress.hasMeasurableByteProgress)
        XCTAssertTrue(AppLanguage.simplifiedChinese.activityWorkloadProgressText(progress).contains("目标大小"))
        XCTAssertEqual(AppLanguage.simplifiedChinese.t("Target size"), "目标大小")
        XCTAssertEqual(
            AppLanguage.simplifiedChinese.t("Preparing the temporary file before transfer. Disk activity may occur, but byte progress is unavailable during this step."),
            "正在准备临时文件；此阶段可能产生磁盘读写，暂不提供已完成字节进度。"
        )
        for language in AppLanguage.allCases {
            let text = language.activityWorkloadProgressText(progress)
            XCTAssertFalse(text.contains(" / "))
            XCTAssertTrue(text.contains(language.t("Target size")))
            XCTAssertTrue(text.contains("128"))
        }
        progress.phase = .writing
        progress.message = "Writing workload file"
        progress.completedBytes = 1024 * 1024
        XCTAssertTrue(progress.hasMeasurableByteProgress)
        XCTAssertTrue(AppLanguage.simplifiedChinese.activityWorkloadProgressText(progress).contains(" / "))
    }

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
