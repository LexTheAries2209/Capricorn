import XCTest
@testable import DiskSpeedTest

final class DITTests: XCTestCase {
    func testDiskutilParserMapsAPFSVolumesToPhysicalDisk() throws {
        let list = try DiskutilPlistParser.parseList(Self.diskutilListFixture.data(using: .utf8)!)
        XCTAssertTrue(list.wholeDiskIDs.contains("disk0"))
        XCTAssertEqual(list.volumesByPhysicalDisk["disk0"]?.first?.mountPoint, "/System/Volumes/Data")

        let drive = try XCTUnwrap(DiskutilPlistParser.parseDevice(
            infoData: Self.disk0InfoFixture.data(using: .utf8)!,
            volumes: list.volumesByPhysicalDisk["disk0"] ?? [],
            showVirtual: false
        ))

        XCTAssertEqual(drive.bsdName, "disk0")
        XCTAssertEqual(drive.displayName, "APPLE SSD AP1024Z")
        XCTAssertEqual(drive.nativeSmartKeys["PERCENTAGE_USED"], 2)
        XCTAssertEqual(drive.benchmarkMountPoint, "/System/Volumes/Data")
    }

    func testSmartctlNVMeParserExtractsHealthFields() {
        let drive = Self.fixtureDrive()
        let snapshot = SmartctlParser.parseSnapshot(Self.smartctlNVMeFixture.data(using: .utf8)!, drive: drive, providerName: "smartctl", exitStatus: 0)

        XCTAssertEqual(snapshot.health, .good)
        XCTAssertEqual(snapshot.temperatureCelsius, 35)
        XCTAssertEqual(snapshot.lifeRemainingPercent, 98)
        XCTAssertEqual(snapshot.mediaErrors, 0)
        XCTAssertTrue(snapshot.attributes.contains(where: { $0.name == "Available Spare" }))
    }

    func testSmartctlOpenErrorBecomesUnavailable() {
        let snapshot = SmartctlParser.parseSnapshot(Self.smartctlOpenErrorFixture.data(using: .utf8)!, drive: Self.fixtureDrive(), providerName: "smartctl", exitStatus: 2)

        XCTAssertEqual(snapshot.health, .unavailable)
        XCTAssertEqual(snapshot.providerStatuses.first?.state, .limited)
        XCTAssertTrue(snapshot.summary.contains("IOCreatePlugInInterfaceForService failed"))
    }

    func testSmartAttributeColumnsHideNormalizedValuesForNVMe() {
        let attributes = [
            SmartAttribute(id: "nvme.available_spare", name: "Available Spare", rawValue: "100", current: nil, worst: nil, threshold: nil, status: .good, source: "smartctl"),
            SmartAttribute(id: "nvme.percentage_used", name: "Percentage Used", rawValue: "2", current: nil, worst: nil, threshold: nil, status: .good, source: "smartctl")
        ]

        XCTAssertFalse(SmartAttributeTableColumns.showsNormalizedColumns(for: attributes))
    }

    func testSmartAttributeColumnsShowNormalizedValuesForATA() {
        let attributes = [
            SmartAttribute(id: "0x05", name: "Reallocated Sectors Count", rawValue: "4", current: 100, worst: 100, threshold: 10, status: .warning, source: "smartctl")
        ]

        XCTAssertTrue(SmartAttributeTableColumns.showsNormalizedColumns(for: attributes))
    }

    func testSmartAttributeDisplayMapsKnownFieldToChineseExplanation() {
        let attribute = SmartAttribute(id: "nvme.available_spare", name: "Available Spare", rawValue: "100", current: nil, worst: nil, threshold: nil, status: .good, source: "smartctl")

        let display = AppLanguage.simplifiedChinese.smartAttributeDisplay(attribute)

        XCTAssertEqual(display.title, "可用备用空间")
        XCTAssertTrue(display.subtitle.contains("备用块"))
        XCTAssertTrue(display.help.contains("Available Spare"))
    }

    func testSmartAttributeDisplayKeepsUnknownFieldName() {
        let attribute = SmartAttribute(id: "vendor.foo", name: "Vendor Foo", rawValue: "7", current: nil, worst: nil, threshold: nil, status: .good, source: "Fixture")

        let display = AppLanguage.simplifiedChinese.smartAttributeDisplay(attribute)

        XCTAssertEqual(display.title, "Vendor Foo")
        XCTAssertTrue(display.subtitle.contains("扩展 SMART 字段"))
    }

    func testHealthEvaluatorFlagsCriticalATAAttributes() {
        let drive = Self.fixtureDrive()
        let snapshot = SmartSnapshot(
            driveID: drive.id,
            capturedAt: Date(),
            health: .good,
            summary: "",
            providerStatuses: [ProviderStatus(name: "Fixture", state: .available, message: "OK")],
            attributes: [
                SmartAttribute(id: "0x05", name: "Reallocated Sectors Count", rawValue: "4", current: 100, worst: 100, threshold: 10, status: .warning, source: "Fixture")
            ],
            temperatureCelsius: 32,
            lifeRemainingPercent: 88,
            powerOnHours: 100,
            powerCycleCount: 2,
            mediaErrors: 0,
            unsafeShutdowns: 0,
            smartStatusRaw: "Passed",
            selfTestStatus: nil
        )

        XCTAssertEqual(DriveHealthEvaluator().evaluate(drive: drive, snapshot: snapshot), .warning)
    }

    func testExternalDetectorFindsSATDriverPath() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let driver = root.appendingPathComponent("SATSMARTDriver.kext")
        try FileManager.default.createDirectory(at: driver, withIntermediateDirectories: true)

        let status = ExternalDriveSupportDetector(driverPaths: [driver.path]).detect()
        XCTAssertTrue(status.satDriverInstalled)
        XCTAssertEqual(status.driverPaths, [driver.path])
    }

    func testBenchmarkProfileConfigurationAppliesRunSizeAndDataPattern() {
        let fileSize: Int64 = 4 * 1_024 * 1_024 * 1_024
        let profile = BenchmarkProfile.default.configured(runs: 5, fileSizeBytes: fileSize, dataPattern: .zeroFill)

        XCTAssertEqual(profile.runs, 5)
        XCTAssertEqual(profile.testFileSizeBytes, fileSize)
        XCTAssertTrue(profile.tests.allSatisfy { $0.testSizeBytes == fileSize })
        XCTAssertTrue(profile.tests.allSatisfy { $0.dataPattern == .zeroFill })
        XCTAssertFalse(profile.usesTrimmedAverage)
        XCTAssertTrue(profile.id.contains("r5"))
        XCTAssertTrue(profile.id.contains("zeroFill"))
        XCTAssertTrue(profile.id.contains("plain"))
    }

    func testBenchmarkProfileConfigurationSeparatesResultIDs() {
        let random = BenchmarkProfile.default.configured(runs: 3, fileSizeBytes: BenchmarkProfile.defaultTestSize, dataPattern: .random)
        let zeroFill = BenchmarkProfile.default.configured(runs: 3, fileSizeBytes: BenchmarkProfile.defaultTestSize, dataPattern: .zeroFill)
        let larger = BenchmarkProfile.default.configured(runs: 3, fileSizeBytes: 4 * 1_024 * 1_024 * 1_024, dataPattern: .random)
        let trimmedAverage = BenchmarkProfile.default.configured(runs: 3, fileSizeBytes: BenchmarkProfile.defaultTestSize, dataPattern: .random, usesTrimmedAverage: true)

        XCTAssertNotEqual(random.id, zeroFill.id)
        XCTAssertNotEqual(random.id, larger.id)
        XCTAssertNotEqual(random.id, trimmedAverage.id)
        XCTAssertEqual(random.baseProfileID, BenchmarkProfile.default.id)
        XCTAssertFalse(random.usesTrimmedAverage)
        XCTAssertTrue(trimmedAverage.usesTrimmedAverage)
    }

    func testBenchmarkLoopProfilePresetAndConfiguration() throws {
        let loop = try XCTUnwrap(BenchmarkProfile.presets.first { $0.baseProfileID == "loop" })

        XCTAssertEqual(loop.name, "Loop")
        XCTAssertEqual(loop.executionMode, .loopUntilCancelled)
        XCTAssertEqual(loop.tests.count, 4)
        XCTAssertEqual(loop.tests.map(\.label), ["SEQ1MiB Q1T1", "SEQ1MiB Q1T1", "SEQ1MiB Q8T1", "SEQ1MiB Q8T1"])
        XCTAssertEqual(loop.tests.map(\.operation), [.read, .write, .read, .write])
        XCTAssertTrue(loop.tests.allSatisfy { $0.accessPattern == .sequential })
        XCTAssertTrue(loop.tests.allSatisfy { $0.blockSizeBytes == 1_048_576 })
        XCTAssertFalse(loop.tests.contains { $0.operation == .mixed })

        let fileSize: Int64 = 8 * 1_024 * 1_024 * 1_024
        let configured = loop.configured(
            runs: 9,
            fileSizeBytes: fileSize,
            dataPattern: .zeroFill,
            usesTrimmedAverage: true
        )

        XCTAssertEqual(configured.executionMode, .loopUntilCancelled)
        XCTAssertEqual(configured.runs, 1)
        XCTAssertFalse(configured.usesTrimmedAverage)
        XCTAssertEqual(configured.testFileSizeBytes, fileSize)
        XCTAssertTrue(configured.tests.allSatisfy { $0.testSizeBytes == fileSize })
        XCTAssertTrue(configured.tests.allSatisfy { $0.dataPattern == .zeroFill })
        XCTAssertTrue(configured.id.contains("loop-s\(fileSize)-zeroFill"))
        XCTAssertFalse(configured.id.contains("r9"))
        XCTAssertFalse(configured.id.contains("trim"))
    }

    func testBenchmarkExtremeLoopProfilePresetAndConfiguration() throws {
        let extreme = try XCTUnwrap(BenchmarkProfile.presets.first { $0.baseProfileID == "loop-extreme" })

        XCTAssertEqual(extreme.name, "Extreme Loop")
        XCTAssertEqual(extreme.executionMode, .loopUntilCancelled)
        XCTAssertEqual(extreme.tests.count, 6)
        XCTAssertEqual(extreme.tests.map(\.label), [
            "SEQ1MiB Q8T1",
            "SEQ1MiB Q8T1",
            "SEQ4MiB Q8T4",
            "SEQ4MiB Q8T4",
            "SEQ1MiB Q32T4",
            "SEQ1MiB Q32T4"
        ])
        XCTAssertEqual(extreme.tests.map(\.operation), [.read, .write, .read, .write, .read, .write])
        XCTAssertEqual(extreme.tests.map(\.blockSizeBytes), [1_048_576, 1_048_576, 4_194_304, 4_194_304, 1_048_576, 1_048_576])
        XCTAssertEqual(extreme.tests.map(\.queueDepth), [8, 8, 8, 8, 32, 32])
        XCTAssertEqual(extreme.tests.map(\.threads), [1, 1, 4, 4, 4, 4])
        XCTAssertFalse(extreme.tests.contains { $0.operation == .mixed })

        let configured = extreme.configured(
            runs: 9,
            fileSizeBytes: 4 * 1_024 * 1_024 * 1_024,
            dataPattern: .zeroFill,
            usesTrimmedAverage: true
        )

        XCTAssertEqual(configured.executionMode, .loopUntilCancelled)
        XCTAssertEqual(configured.runs, 1)
        XCTAssertFalse(configured.usesTrimmedAverage)
        XCTAssertTrue(configured.id.hasPrefix("loop-extreme@loop-s"))
        XCTAssertTrue(configured.tests.allSatisfy { $0.dataPattern == .zeroFill })
    }

    func testBenchmarkTargetFolderMatcherDetectsFolderInsideSelectedDriveMount() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let target = root.appendingPathComponent("Benchmarks")
        let other = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: other)
        }

        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "unit", name: "Unit", mountPoint: root.path, sizeBytes: 1_000_000, isWritable: true, isSystem: false)
        ]

        XCTAssertTrue(BenchmarkTargetFolderMatcher.targetFolderBelongsToDrive(target.path, drive: drive))
        XCTAssertFalse(BenchmarkTargetFolderMatcher.targetFolderBelongsToDrive(other.path, drive: drive))
    }

    func testBenchmarkDefaultsMatchDiskMarkControls() {
        XCTAssertEqual(BenchmarkProfile.defaultRuns, 3)
        XCTAssertEqual(BenchmarkProfile.defaultTestSize, 1_073_741_824)
        XCTAssertEqual(BenchmarkProfile.defaultDataPattern, .random)
        XCTAssertFalse(BenchmarkProfile.defaultUsesTrimmedAverage)
        XCTAssertEqual(BenchmarkProfile.runCountOptions, Array(1...9))
        XCTAssertTrue(BenchmarkProfile.fileSizeOptions.contains(BenchmarkProfile.defaultTestSize))
    }

    func testBenchmarkProgressIncludesCurrentPhaseBytesInFraction() {
        let progress = BenchmarkProgress(
            currentTestLabel: "RND4K Q1T1",
            completed: 2,
            total: 10,
            message: "Read run 1/3",
            phaseCompletedBytes: 512,
            phaseTotalBytes: 1_024
        )

        XCTAssertEqual(progress.fraction, 0.25, accuracy: 0.0001)
    }

    func testBenchmarkSelectedRunCountAddsTwoMeasuredRunsWhenTrimmedAverageEnabled() {
        XCTAssertEqual(BenchmarkMeasurementReducer.measuredRunCount(for: 1, usesTrimmedAverage: true), 3)
        XCTAssertEqual(BenchmarkMeasurementReducer.measuredRunCount(for: 3, usesTrimmedAverage: true), 5)
        XCTAssertEqual(BenchmarkMeasurementReducer.measuredRunCount(for: 9, usesTrimmedAverage: true), 11)
    }

    func testBenchmarkSelectedRunCountIsExactWhenTrimmedAverageDisabled() {
        XCTAssertEqual(BenchmarkMeasurementReducer.measuredRunCount(for: 1, usesTrimmedAverage: false), 1)
        XCTAssertEqual(BenchmarkMeasurementReducer.measuredRunCount(for: 3, usesTrimmedAverage: false), 3)
        XCTAssertEqual(BenchmarkMeasurementReducer.measuredRunCount(for: 9, usesTrimmedAverage: false), 9)
    }

    func testBenchmarkMeasurementReducerDropsExtremesAndAverages() {
        let summary = BenchmarkMeasurementReducer.summarize([
            BenchmarkRunMeasurement(megabytesPerSecond: 100, iops: 10, latencyMicroseconds: 50, bytesTransferred: 1_000),
            BenchmarkRunMeasurement(megabytesPerSecond: 200, iops: 20, latencyMicroseconds: 40, bytesTransferred: 2_000),
            BenchmarkRunMeasurement(megabytesPerSecond: 300, iops: 30, latencyMicroseconds: 30, bytesTransferred: 3_000),
            BenchmarkRunMeasurement(megabytesPerSecond: 400, iops: 40, latencyMicroseconds: 20, bytesTransferred: 4_000),
            BenchmarkRunMeasurement(megabytesPerSecond: 900, iops: 90, latencyMicroseconds: 10, bytesTransferred: 9_000)
        ], usesTrimmedAverage: true)

        XCTAssertEqual(summary.megabytesPerSecond, 300, accuracy: 0.001)
        XCTAssertEqual(summary.iops, 30, accuracy: 0.001)
        XCTAssertEqual(summary.latencyMicroseconds, 30, accuracy: 0.001)
        XCTAssertEqual(summary.bytesTransferred, 3_000)
    }

    func testBenchmarkMeasurementReducerAveragesAllRunsWhenTrimmedAverageDisabled() {
        let summary = BenchmarkMeasurementReducer.summarize([
            BenchmarkRunMeasurement(megabytesPerSecond: 100, iops: 10, latencyMicroseconds: 50, bytesTransferred: 1_000),
            BenchmarkRunMeasurement(megabytesPerSecond: 200, iops: 20, latencyMicroseconds: 40, bytesTransferred: 2_000),
            BenchmarkRunMeasurement(megabytesPerSecond: 900, iops: 90, latencyMicroseconds: 10, bytesTransferred: 9_000)
        ], usesTrimmedAverage: false)

        XCTAssertEqual(summary.megabytesPerSecond, 400, accuracy: 0.001)
        XCTAssertEqual(summary.iops, 40, accuracy: 0.001)
        XCTAssertEqual(summary.latencyMicroseconds, 100.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(summary.bytesTransferred, 4_000)
    }

    func testBenchmarkConfigurationDescriptionIsLocalized() {
        let english = AppLanguage.english.benchmarkConfigurationDescription(
            profile: .default,
            runs: 3,
            fileSizeBytes: BenchmarkProfile.defaultTestSize,
            dataPattern: .random,
            usesTrimmedAverage: true
        )
        let chinese = AppLanguage.simplifiedChinese.benchmarkConfigurationDescription(
            profile: .default,
            runs: 3,
            fileSizeBytes: BenchmarkProfile.defaultTestSize,
            dataPattern: .random,
            usesTrimmedAverage: true
        )
        let plainChinese = AppLanguage.simplifiedChinese.benchmarkConfigurationDescription(
            profile: .default,
            runs: 3,
            fileSizeBytes: BenchmarkProfile.defaultTestSize,
            dataPattern: .random,
            usesTrimmedAverage: false
        )

        XCTAssertTrue(english.profileUse.contains("Default"))
        XCTAssertTrue(english.dataPattern.contains("Random"))
        XCTAssertTrue(english.runs.contains("5"))
        XCTAssertTrue(english.fileSize.contains("full file"))
        XCTAssertTrue(english.testTerms.contains("Each row"))
        XCTAssertTrue(english.testTerms.contains("SEQ"))
        XCTAssertFalse(english.testTerms.contains("1 second"))
        XCTAssertFalse(english.testTerms.contains("5 seconds"))
        XCTAssertTrue(chinese.profileUse.contains("默认"))
        XCTAssertTrue(chinese.runs.contains("3"))
        XCTAssertTrue(chinese.runs.contains("5"))
        XCTAssertTrue(plainChinese.runs.contains("普通平均"))
        XCTAssertTrue(chinese.fileSize.contains("1 GiB"))
        XCTAssertTrue(chinese.fileSize.contains("完整"))
        XCTAssertTrue(chinese.dataPattern.contains("随机"))
        XCTAssertTrue(chinese.testTerms.contains("SEQ"))
        XCTAssertTrue(chinese.testTerms.contains("每一行"))
        XCTAssertFalse(chinese.testTerms.contains("间隔"))

        let loopChinese = AppLanguage.simplifiedChinese.benchmarkConfigurationDescription(
            profile: .loop,
            runs: 9,
            fileSizeBytes: BenchmarkProfile.defaultTestSize,
            dataPattern: .random,
            usesTrimmedAverage: true
        )
        XCTAssertTrue(loopChinese.profileUse.contains("循环"))
        XCTAssertTrue(loopChinese.runs.contains("持续运行"))
        XCTAssertTrue(loopChinese.runs.contains("最新完成"))
        XCTAssertTrue(loopChinese.testTerms.contains("无间隔重复"))

        let extremeLoopChinese = AppLanguage.simplifiedChinese.benchmarkConfigurationDescription(
            profile: .extremeLoop,
            runs: 9,
            fileSizeBytes: BenchmarkProfile.defaultTestSize,
            dataPattern: .random,
            usesTrimmedAverage: true
        )
        XCTAssertTrue(extremeLoopChinese.profileUse.contains("极限循环"))
        XCTAssertTrue(extremeLoopChinese.testTerms.contains("SEQ4M Q8T4"))
        XCTAssertTrue(extremeLoopChinese.testTerms.contains("SEQ1M Q32T4"))

        XCTAssertEqual(
            AppLanguage.simplifiedChinese.progressLabel("Loop 3 - SEQ1MiB Q8T1 Write"),
            "循环第 3 轮 - SEQ1MiB Q8T1 写入"
        )
    }

    func testBenchmarkStorageValidatorFiltersUnavailableFileSizes() {
        let options: [Int64] = [
            16 * 1_024 * 1_024,
            64 * 1_024 * 1_024,
            256 * 1_024 * 1_024
        ]
        let available = BenchmarkStorageValidator.requiredSpace(for: options[1])

        XCTAssertEqual(BenchmarkStorageValidator.availableFileSizeOptions(from: options, availableCapacity: available), [options[0], options[1]])
        XCTAssertEqual(BenchmarkStorageValidator.largestAvailableFileSize(from: options, availableCapacity: available), options[1])
        XCTAssertFalse(BenchmarkStorageValidator.isFileSizeAvailable(options[2], availableCapacity: available))
    }

    func testBenchmarkRunnerCleansTemporaryFile() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "unit", name: "Unit", mountPoint: root.path, sizeBytes: 1_000_000, isWritable: true, isSystem: false)
        ]
        let test = BenchmarkTest(
            id: "unit-write",
            label: "RND4K Q1T1",
            accessPattern: .random,
            operation: .write,
            blockSizeBytes: 4_096,
            queueDepth: 1,
            threads: 1,
            durationSeconds: 0.05,
            testSizeBytes: 65_536,
            dataPattern: .zeroFill,
            writePercentForMixed: 100
        )
        let profile = BenchmarkProfile(id: "unit", name: "Unit", testFileSizeBytes: 65_536, runs: 1, tests: [test])

        let results = try await NativeBenchmarkRunner(operationIntervalSeconds: 0, passIntervalSeconds: 0).run(profile: profile, drive: drive, volumePath: root.path, progress: { _ in }, result: { _ in })
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.bytesTransferred, 65_536)

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter {
            $0.hasPrefix("Disk-Speed-Test-") || $0.hasPrefix(".dit-benchmark-")
        }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testBenchmarkRunnerPublishesEachRowReadThenWrite() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "unit", name: "Unit", mountPoint: root.path, sizeBytes: 1_000_000, isWritable: true, isSystem: false)
        ]
        let read = BenchmarkTest(
            id: "unit-read-a",
            label: "SEQ1M Q1T1",
            accessPattern: .sequential,
            operation: .read,
            blockSizeBytes: 4_096,
            queueDepth: 1,
            threads: 1,
            durationSeconds: 0.05,
            testSizeBytes: 65_536,
            dataPattern: .zeroFill,
            writePercentForMixed: 0
        )
        var write = read
        write.id = "unit-write-a"
        write.operation = .write
        write.writePercentForMixed = 100
        var readB = read
        readB.id = "unit-read-b"
        readB.label = "RND4K Q1T1"
        readB.accessPattern = .random
        var writeB = readB
        writeB.id = "unit-write-b"
        writeB.operation = .write
        writeB.writePercentForMixed = 100

        let profile = BenchmarkProfile(id: "unit", name: "Unit", testFileSizeBytes: 65_536, runs: 1, tests: [read, write, readB, writeB])
        var publishedTestIDs: [String] = []

        let results = try await NativeBenchmarkRunner(operationIntervalSeconds: 0, passIntervalSeconds: 0).run(profile: profile, drive: drive, volumePath: root.path, progress: { _ in }) { result in
            publishedTestIDs.append(result.testID)
        }

        XCTAssertEqual(results.map(\.testID), ["unit-read-a", "unit-write-a", "unit-read-b", "unit-write-b"])
        XCTAssertEqual(publishedTestIDs, ["unit-read-a", "unit-write-a", "unit-read-b", "unit-write-b"])
        XCTAssertTrue(results.allSatisfy { $0.bytesTransferred == 65_536 })
    }

    func testBenchmarkRunnerUsesUniqueFilesForWritePasses() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "unit", name: "Unit", mountPoint: root.path, sizeBytes: 1_000_000, isWritable: true, isSystem: false)
        ]
        let write = BenchmarkTest(
            id: "unit-write",
            label: "SEQ1M Q1T1",
            accessPattern: .sequential,
            operation: .write,
            blockSizeBytes: 4_096,
            queueDepth: 1,
            threads: 1,
            durationSeconds: 0.05,
            testSizeBytes: 32_768,
            dataPattern: .random,
            writePercentForMixed: 100
        )
        let profile = BenchmarkProfile(id: "unit", name: "Unit", testFileSizeBytes: 32_768, runs: 1, tests: [write])
        let lock = NSLock()
        var createdNames: [String] = []
        let runner = NativeBenchmarkRunner(operationIntervalSeconds: 0, passIntervalSeconds: 0, fileEventHandler: { url in
            lock.lock()
            createdNames.append(url.lastPathComponent)
            lock.unlock()
        })

        _ = try await runner.run(profile: profile, drive: drive, volumePath: root.path, progress: { _ in }, result: { _ in })

        lock.lock()
        let names = createdNames
        lock.unlock()
        XCTAssertEqual(names.count, 2)
        XCTAssertEqual(Set(names).count, 2)
        XCTAssertTrue(names.allSatisfy { $0.hasPrefix("Disk-Speed-Test-") })
        XCTAssertTrue(names.allSatisfy { $0.contains("write-run") })
    }

    func testBenchmarkRunnerIgnoresFixedDurationAndTransfersCompleteFile() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "unit", name: "Unit", mountPoint: root.path, sizeBytes: 1_000_000, isWritable: true, isSystem: false)
        ]
        let read = BenchmarkTest(
            id: "unit-read",
            label: "SEQ4K Q1T1",
            accessPattern: .sequential,
            operation: .read,
            blockSizeBytes: 4_096,
            queueDepth: 1,
            threads: 1,
            durationSeconds: 0.001,
            testSizeBytes: 131_072,
            dataPattern: .zeroFill,
            writePercentForMixed: 0
        )
        let profile = BenchmarkProfile(id: "unit", name: "Unit", testFileSizeBytes: 131_072, runs: 1, tests: [read])

        let results = try await NativeBenchmarkRunner(operationIntervalSeconds: 0, passIntervalSeconds: 0).run(profile: profile, drive: drive, volumePath: root.path, progress: { _ in }, result: { _ in })

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.bytesTransferred, 131_072)
    }

    func testBenchmarkRunnerRequestsIntervalBetweenScoredTests() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "unit", name: "Unit", mountPoint: root.path, sizeBytes: 1_000_000, isWritable: true, isSystem: false)
        ]
        let read = BenchmarkTest(
            id: "unit-read",
            label: "SEQ4K Q1T1",
            accessPattern: .sequential,
            operation: .read,
            blockSizeBytes: 4_096,
            queueDepth: 1,
            threads: 1,
            durationSeconds: 0.001,
            testSizeBytes: 8_192,
            dataPattern: .zeroFill,
            writePercentForMixed: 0
        )
        var write = read
        write.id = "unit-write"
        write.operation = .write
        write.writePercentForMixed = 100
        let profile = BenchmarkProfile(id: "unit", name: "Unit", testFileSizeBytes: 8_192, runs: 1, tests: [read, write])
        let lock = NSLock()
        var requestedWaits: [TimeInterval] = []
        let runner = NativeBenchmarkRunner(operationIntervalSeconds: 5, passIntervalSeconds: 0) { seconds, isCancelled in
            XCTAssertFalse(isCancelled())
            lock.lock()
            requestedWaits.append(seconds)
            lock.unlock()
        }

        _ = try await runner.run(profile: profile, drive: drive, volumePath: root.path, progress: { _ in }, result: { _ in })

        lock.lock()
        let waits = requestedWaits
        lock.unlock()
        XCTAssertEqual(waits, [5])
    }

    func testBenchmarkRunnerRequestsOneSecondBetweenPasses() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "unit", name: "Unit", mountPoint: root.path, sizeBytes: 1_000_000, isWritable: true, isSystem: false)
        ]
        let write = BenchmarkTest(
            id: "unit-write",
            label: "SEQ4K Q1T1",
            accessPattern: .sequential,
            operation: .write,
            blockSizeBytes: 4_096,
            queueDepth: 1,
            threads: 1,
            durationSeconds: 0.001,
            testSizeBytes: 8_192,
            dataPattern: .zeroFill,
            writePercentForMixed: 100
        )
        let profile = BenchmarkProfile(id: "unit", name: "Unit", testFileSizeBytes: 8_192, runs: 1, tests: [write])
        let lock = NSLock()
        var requestedWaits: [TimeInterval] = []
        let runner = NativeBenchmarkRunner(operationIntervalSeconds: 0, passIntervalSeconds: 1) { seconds, isCancelled in
            XCTAssertFalse(isCancelled())
            lock.lock()
            requestedWaits.append(seconds)
            lock.unlock()
        }

        _ = try await runner.run(profile: profile, drive: drive, volumePath: root.path, progress: { _ in }, result: { _ in })

        lock.lock()
        let waits = requestedWaits
        lock.unlock()
        XCTAssertEqual(waits, [1])
    }

    func testBenchmarkLoopRunnerPublishesLatestPassAndStopsWithoutWaiting() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "unit", name: "Unit", mountPoint: root.path, sizeBytes: 1_000_000, isWritable: true, isSystem: false)
        ]
        let readQ1 = BenchmarkTest(
            id: "loop-read-q1",
            label: "SEQ1M Q1T1",
            accessPattern: .sequential,
            operation: .read,
            blockSizeBytes: 4_096,
            queueDepth: 1,
            threads: 1,
            durationSeconds: 0.001,
            testSizeBytes: 8_192,
            dataPattern: .zeroFill,
            writePercentForMixed: 0
        )
        var writeQ1 = readQ1
        writeQ1.id = "loop-write-q1"
        writeQ1.operation = .write
        writeQ1.writePercentForMixed = 100
        var readQ8 = readQ1
        readQ8.id = "loop-read-q8"
        readQ8.label = "SEQ1M Q8T1"
        readQ8.queueDepth = 8
        var writeQ8 = readQ8
        writeQ8.id = "loop-write-q8"
        writeQ8.operation = .write
        writeQ8.writePercentForMixed = 100
        let profile = BenchmarkProfile(
            id: "unit-loop",
            name: "Unit Loop",
            testFileSizeBytes: 8_192,
            runs: 9,
            usesTrimmedAverage: true,
            executionMode: .loopUntilCancelled,
            tests: [readQ1, writeQ1, readQ8, writeQ8]
        )

        let lock = NSLock()
        var requestedWaits: [TimeInterval] = []
        var published: [BenchmarkResult] = []
        let runner = NativeBenchmarkRunner(operationIntervalSeconds: 5, passIntervalSeconds: 1) { seconds, _ in
            lock.lock()
            requestedWaits.append(seconds)
            lock.unlock()
        }

        let results = try await runner.run(profile: profile, drive: drive, volumePath: root.path, progress: { _ in }) { result in
            lock.lock()
            published.append(result)
            let shouldCancel = published.count == 8
            lock.unlock()
            if shouldCancel {
                runner.cancel()
            }
        }

        lock.lock()
        let waits = requestedWaits
        let publishedIDs = published.map(\.testID)
        lock.unlock()

        let expectedCycle = ["loop-read-q1", "loop-write-q1", "loop-read-q8", "loop-write-q8"]
        XCTAssertEqual(publishedIDs, expectedCycle + expectedCycle)
        XCTAssertEqual(results.map(\.testID), expectedCycle)
        XCTAssertTrue(results.allSatisfy { $0.bytesTransferred == 8_192 })
        XCTAssertTrue(waits.isEmpty)

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter {
            $0.hasPrefix("Disk-Speed-Test-") || $0.hasPrefix(".dit-benchmark-")
        }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testHistoryVisibilitySeparatesVisibleAndHiddenSmartRecords() {
        let drive = Self.fixtureDrive()
        let snapshot = Self.fixtureSnapshot(for: drive)
        let visible = SmartHistoryRecord(drive: drive, snapshot: snapshot)
        let hidden = SmartHistoryRecord(drive: drive, snapshot: snapshot)

        HistoryVisibility.hide(hidden, at: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(HistoryVisibility.visible([visible, hidden]).map(\.id), [visible.id])
        XCTAssertEqual(HistoryVisibility.hidden([visible, hidden]).map(\.id), [hidden.id])
        XCTAssertNil(visible.hiddenAt)
        XCTAssertNotNil(hidden.hiddenAt)
    }

    func testHistoryVisibilitySeparatesVisibleAndHiddenBenchmarkRecords() {
        let drive = Self.fixtureDrive()
        let visible = BenchmarkHistoryRecord(drive: drive, result: Self.fixtureBenchmarkResult(for: drive))
        let hidden = BenchmarkHistoryRecord(drive: drive, result: Self.fixtureBenchmarkResult(for: drive))

        HistoryVisibility.hide(hidden, at: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(HistoryVisibility.visible([visible, hidden]).map(\.id), [visible.id])
        XCTAssertEqual(HistoryVisibility.hidden([visible, hidden]).map(\.id), [hidden.id])
    }

    func testHistoryVisibilityRestoresSingleRecord() {
        let drive = Self.fixtureDrive()
        let record = SmartHistoryRecord(drive: drive, snapshot: Self.fixtureSnapshot(for: drive))

        HistoryVisibility.hide(record, at: Date(timeIntervalSince1970: 1))
        HistoryVisibility.restore(record)

        XCTAssertNil(record.hiddenAt)
        XCTAssertEqual(HistoryVisibility.visible([record]).map(\.id), [record.id])
    }

    func testHistoryVisibilityRestoreAllCanLimitToCurrentDrive() {
        let drive = Self.fixtureDrive()
        var otherDrive = drive
        otherDrive.bsdName = "disk9"
        let currentDriveRecord = SmartHistoryRecord(drive: drive, snapshot: Self.fixtureSnapshot(for: drive))
        let otherDriveRecord = SmartHistoryRecord(drive: otherDrive, snapshot: Self.fixtureSnapshot(for: otherDrive))

        HistoryVisibility.hide(currentDriveRecord, at: Date(timeIntervalSince1970: 1))
        HistoryVisibility.hide(otherDriveRecord, at: Date(timeIntervalSince1970: 2))
        HistoryVisibility.restoreAll([currentDriveRecord, otherDriveRecord], driveID: drive.id)

        XCTAssertNil(currentDriveRecord.hiddenAt)
        XCTAssertNotNil(otherDriveRecord.hiddenAt)
    }

    private static func fixtureDrive() -> DriveDevice {
        DriveDevice(
            bsdName: "disk0",
            deviceNode: "/dev/disk0",
            displayName: "APPLE SSD AP1024Z",
            mediaName: "APPLE SSD AP1024Z",
            protocolName: "NVMe",
            sizeBytes: 1_000_555_581_440,
            blockSize: 4096,
            isInternal: true,
            isRemovable: false,
            isSolidState: true,
            isWritable: true,
            isVirtual: false,
            isSystemDisk: true,
            smartStatusRaw: "Verified",
            nativeSmartKeys: [:],
            volumes: [],
            model: "APPLE SSD AP1024Z",
            serialNumber: "SN"
        )
    }

    private static func fixtureSnapshot(for drive: DriveDevice) -> SmartSnapshot {
        SmartSnapshot(
            driveID: drive.id,
            capturedAt: Date(timeIntervalSince1970: 1_000),
            health: .good,
            summary: "OK",
            providerStatuses: [ProviderStatus(name: "Fixture", state: .available, message: "OK")],
            attributes: [],
            temperatureCelsius: 32,
            lifeRemainingPercent: 98,
            powerOnHours: 120,
            powerCycleCount: 4,
            mediaErrors: 0,
            unsafeShutdowns: 0,
            smartStatusRaw: "Verified",
            selfTestStatus: nil
        )
    }

    private static func fixtureBenchmarkResult(for drive: DriveDevice) -> BenchmarkResult {
        BenchmarkResult(
            driveID: drive.id,
            volumePath: "/tmp",
            profileID: "unit",
            profileName: "Unit",
            testID: "unit-read",
            testLabel: "SEQ1M Q1T1",
            operation: .read,
            measuredAt: Date(timeIntervalSince1970: 1_000),
            bestMegabytesPerSecond: 1_234.5,
            iops: 100,
            latencyMicroseconds: 10,
            bytesTransferred: 65_536
        )
    }

    private static let diskutilListFixture = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>WholeDisks</key><array><string>disk0</string><string>disk3</string></array>
      <key>AllDisksAndPartitions</key><array>
        <dict>
          <key>Content</key><string>GUID_partition_scheme</string>
          <key>DeviceIdentifier</key><string>disk0</string>
          <key>Partitions</key><array>
            <dict><key>DeviceIdentifier</key><string>disk0s2</string><key>Content</key><string>Apple_APFS</string><key>Size</key><integer>994662584320</integer></dict>
          </array>
          <key>Size</key><integer>1000555581440</integer>
        </dict>
        <dict>
          <key>APFSPhysicalStores</key><array><dict><key>DeviceIdentifier</key><string>disk0s2</string></dict></array>
          <key>APFSVolumes</key><array>
            <dict><key>DeviceIdentifier</key><string>disk3s5</string><key>VolumeName</key><string>Data</string><key>MountPoint</key><string>/System/Volumes/Data</string><key>Size</key><integer>994662584320</integer><key>OSInternal</key><false/></dict>
          </array>
          <key>Content</key><string>Apple_APFS_Container</string>
          <key>DeviceIdentifier</key><string>disk3</string>
        </dict>
      </array>
    </dict></plist>
    """

    private static let disk0InfoFixture = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>BusProtocol</key><string>Apple Fabric</string>
      <key>Content</key><string>GUID_partition_scheme</string>
      <key>DeviceBlockSize</key><integer>4096</integer>
      <key>DeviceIdentifier</key><string>disk0</string>
      <key>DeviceNode</key><string>/dev/disk0</string>
      <key>IORegistryEntryName</key><string>APPLE SSD AP1024Z Media</string>
      <key>Internal</key><true/>
      <key>MediaName</key><string>APPLE SSD AP1024Z</string>
      <key>Removable</key><false/>
      <key>SMARTDeviceSpecificKeysMayVaryNotGuaranteed</key><dict>
        <key>AVAILABLE_SPARE</key><integer>100</integer>
        <key>AVAILABLE_SPARE_THRESHOLD</key><integer>99</integer>
        <key>PERCENTAGE_USED</key><integer>2</integer>
        <key>TEMPERATURE</key><integer>308</integer>
      </dict>
      <key>SMARTStatus</key><string>Verified</string>
      <key>SolidState</key><true/>
      <key>TotalSize</key><integer>1000555581440</integer>
      <key>VirtualOrPhysical</key><string>Physical</string>
      <key>WholeDisk</key><true/>
      <key>WritableMedia</key><true/>
    </dict></plist>
    """

    private static let smartctlNVMeFixture = """
    {
      "smartctl": {"exit_status": 0},
      "smart_status": {"passed": true},
      "temperature": {"current": 35},
      "power_on_time": {"hours": 1295},
      "power_cycle_count": 384,
      "nvme_smart_health_information_log": {
        "critical_warning": 0,
        "temperature": 35,
        "available_spare": 100,
        "available_spare_threshold": 99,
        "percentage_used": 2,
        "media_errors": 0,
        "num_err_log_entries": 0,
        "unsafe_shutdowns": 35,
        "data_units_read": 180246471,
        "data_units_written": 85848679
      }
    }
    """

    private static let smartctlOpenErrorFixture = """
    {
      "smartctl": {"exit_status": 2},
      "device": {"name": "IOService:/AppleANS"},
      "open_error": "IOCreatePlugInInterfaceForService failed"
    }
    """
}
