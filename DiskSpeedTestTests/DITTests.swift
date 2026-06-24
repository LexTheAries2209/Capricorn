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

    func testBenchmarkCustomRowsDefaultGenerateCurrentCustomTests() {
        let profile = BenchmarkProfile.custom(rows: BenchmarkCustomRow.defaultRows)

        XCTAssertEqual(profile.baseProfileID, "custom")
        XCTAssertEqual(profile.tests.map(\.label), [
            "SEQ1MiB Q1T1",
            "SEQ1MiB Q1T1",
            "SEQ1MiB Q1T1 Mix",
            "RND4KiB Q4T1",
            "RND4KiB Q4T1",
            "RND4KiB Q4T1 Mix"
        ])
        XCTAssertEqual(profile.tests.map(\.operation), [.read, .write, .mixed, .read, .write, .mixed])
        XCTAssertEqual(profile.tests.filter { $0.operation == .mixed }.map(\.writePercentForMixed), [30, 30])
    }

    func testBenchmarkCustomRowsGenerateMixedPerGroup() {
        let rows = [
            BenchmarkCustomRow(id: "a", accessPattern: .sequential, blockSizeBytes: 1_048_576, queueDepth: 1, threads: 1, includeMixed: false),
            BenchmarkCustomRow(id: "b", accessPattern: .random, blockSizeBytes: 4_096, queueDepth: 8, threads: 2, includeMixed: true)
        ]

        let profile = BenchmarkProfile.custom(rows: rows)

        XCTAssertEqual(profile.tests.map(\.label), [
            "SEQ1MiB Q1T1",
            "SEQ1MiB Q1T1",
            "RND4KiB Q8T2",
            "RND4KiB Q8T2",
            "RND4KiB Q8T2 Mix"
        ])
        XCTAssertEqual(profile.tests.map(\.operation), [.read, .write, .read, .write, .mixed])
    }

    func testBenchmarkCustomRowsAreLimitedAndFallbackToDefaults() {
        let fiveRows = (0..<5).map { index in
            BenchmarkCustomRow(id: "row-\(index)", accessPattern: .sequential, blockSizeBytes: 1_048_576, queueDepth: 1, threads: 1, includeMixed: false)
        }

        XCTAssertEqual(BenchmarkCustomRow.sanitized(fiveRows).count, BenchmarkCustomRow.maxRows)
        XCTAssertEqual(BenchmarkCustomRow.sanitized([]), BenchmarkCustomRow.defaultRows)
    }

    func testBenchmarkCustomRowsPersistThroughJSONAndFallbackOnInvalidJSON() {
        let rows = [
            BenchmarkCustomRow(id: "a", accessPattern: .random, blockSizeBytes: 65_536, queueDepth: 16, threads: 4, includeMixed: true)
        ]

        let encoded = BenchmarkCustomRow.encodeList(rows)
        XCTAssertEqual(BenchmarkCustomRow.decodeList(from: encoded), rows)
        XCTAssertEqual(BenchmarkCustomRow.decodeList(from: "not-json"), BenchmarkCustomRow.defaultRows)
    }

    func testBenchmarkCustomProfileIDChangesWhenRowsChange() {
        let baseRows = [
            BenchmarkCustomRow(id: "a", accessPattern: .sequential, blockSizeBytes: 1_048_576, queueDepth: 1, threads: 1, includeMixed: true)
        ]
        let changedRows = [
            BenchmarkCustomRow(id: "a", accessPattern: .sequential, blockSizeBytes: 4_194_304, queueDepth: 1, threads: 1, includeMixed: true)
        ]

        let first = BenchmarkProfile.custom(rows: baseRows).configured(runs: 3, fileSizeBytes: BenchmarkProfile.defaultTestSize, dataPattern: .random)
        let second = BenchmarkProfile.custom(rows: changedRows).configured(runs: 3, fileSizeBytes: BenchmarkProfile.defaultTestSize, dataPattern: .random)

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertTrue(first.id.contains("rows-"))
        XCTAssertEqual(first.baseProfileID, "custom")
    }

    func testBenchmarkCustomProfileAppliesEngineAndLoopOptions() {
        let rows = [
            BenchmarkCustomRow(id: "a", accessPattern: .sequential, blockSizeBytes: 1_048_576, queueDepth: 8, threads: 2, includeMixed: false)
        ]

        let asyncLoop = BenchmarkProfile.custom(
            rows: rows,
            engine: .asyncQueue,
            executionMode: .loopUntilCancelled
        ).configured(
            runs: 9,
            fileSizeBytes: 2 * 1_024 * 1_024 * 1_024,
            dataPattern: .zeroFill,
            usesTrimmedAverage: true
        )

        XCTAssertEqual(asyncLoop.engine, .asyncQueue)
        XCTAssertEqual(asyncLoop.executionMode, .loopUntilCancelled)
        XCTAssertEqual(asyncLoop.runs, 1)
        XCTAssertFalse(asyncLoop.usesTrimmedAverage)
        XCTAssertTrue(asyncLoop.id.contains("rows-"))
        XCTAssertTrue(asyncLoop.id.contains("loop-s"))
        XCTAssertTrue(asyncLoop.id.contains("engine-asyncQueue"))
        XCTAssertTrue(asyncLoop.tests.allSatisfy { $0.dataPattern == .zeroFill })
    }

    func testBenchmarkCustomProfileIDChangesWhenEngineChanges() {
        let rows = [
            BenchmarkCustomRow(id: "a", accessPattern: .random, blockSizeBytes: 4_096, queueDepth: 8, threads: 1, includeMixed: true)
        ]

        let sync = BenchmarkProfile.custom(rows: rows, engine: .synchronous).configured(
            runs: 3,
            fileSizeBytes: BenchmarkProfile.defaultTestSize,
            dataPattern: .random
        )
        let async = BenchmarkProfile.custom(rows: rows, engine: .asyncQueue).configured(
            runs: 3,
            fileSizeBytes: BenchmarkProfile.defaultTestSize,
            dataPattern: .random
        )

        XCTAssertNotEqual(sync.id, async.id)
        XCTAssertEqual(sync.engine, .synchronous)
        XCTAssertEqual(async.engine, .asyncQueue)
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

    func testBenchmarkAsyncTestProfilePresetAndConfiguration() throws {
        let testProfile = try XCTUnwrap(BenchmarkProfile.presets.first { $0.baseProfileID == "test" })

        XCTAssertEqual(testProfile.name, "Test")
        XCTAssertEqual(testProfile.engine, .asyncQueue)
        XCTAssertEqual(testProfile.executionMode, .finite)
        XCTAssertEqual(testProfile.tests.map(\.label), [
            "SEQ1MiB Q1T1",
            "SEQ1MiB Q1T1",
            "SEQ1MiB Q1T2",
            "SEQ1MiB Q1T2",
            "SEQ1MiB Q1T4",
            "SEQ1MiB Q1T4",
            "SEQ1MiB Q8T1",
            "SEQ1MiB Q8T1",
            "SEQ1MiB Q8T2",
            "SEQ1MiB Q8T2",
            "SEQ1MiB Q8T4",
            "SEQ1MiB Q8T4"
        ])
        XCTAssertEqual(testProfile.tests.map(\.operation), [.read, .write, .read, .write, .read, .write, .read, .write, .read, .write, .read, .write])
        XCTAssertEqual(testProfile.tests.map(\.queueDepth), [1, 1, 1, 1, 1, 1, 8, 8, 8, 8, 8, 8])
        XCTAssertEqual(testProfile.tests.map(\.threads), [1, 1, 2, 2, 4, 4, 1, 1, 2, 2, 4, 4])
        XCTAssertEqual(testProfile.tests.map(\.blockSizeBytes), Array(repeating: 1_048_576, count: 12))
        XCTAssertFalse(testProfile.tests.contains { $0.queueDepth == 32 })

        let configured = testProfile.configured(
            runs: 4,
            fileSizeBytes: 256 * 1_024 * 1_024,
            dataPattern: .zeroFill,
            usesTrimmedAverage: true
        )

        XCTAssertEqual(configured.engine, .asyncQueue)
        XCTAssertEqual(configured.runs, 4)
        XCTAssertTrue(configured.usesTrimmedAverage)
        XCTAssertTrue(configured.id.contains("r4"))
        XCTAssertTrue(configured.id.contains("zeroFill"))
        XCTAssertTrue(configured.id.contains("trim"))
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
        XCTAssertEqual(BenchmarkProfile.fileSizeOptions.first, BenchmarkProfile.defaultTestSize)
        XCTAssertTrue(BenchmarkProfile.fileSizeOptions.contains(BenchmarkProfile.defaultTestSize))
        XCTAssertTrue(BenchmarkProfile.fileSizeOptions.allSatisfy { $0 >= BenchmarkProfile.defaultTestSize })
        XCTAssertTrue(BenchmarkProfile.presets.allSatisfy { $0.testFileSizeBytes >= BenchmarkProfile.defaultTestSize })
        XCTAssertTrue(BenchmarkProfile.presets.flatMap(\.tests).allSatisfy { $0.testSizeBytes >= BenchmarkProfile.defaultTestSize })
    }

    func testBenchmarkProfileConfigurationClampsSubGigabyteFileSize() {
        let profile = BenchmarkProfile.default.configured(
            runs: 3,
            fileSizeBytes: 256 * 1_024 * 1_024,
            dataPattern: .random
        )

        XCTAssertEqual(profile.testFileSizeBytes, BenchmarkProfile.defaultTestSize)
        XCTAssertTrue(profile.tests.allSatisfy { $0.testSizeBytes == BenchmarkProfile.defaultTestSize })
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

    func testDiskActivityRateCalculatorComputesDecimalMegabytesPerSecond() {
        let start = Date(timeIntervalSince1970: 1_000)
        let previous = DiskActivityCounters(timestamp: start, readBytes: 1_000, writeBytes: 2_000)
        let current = DiskActivityCounters(
            timestamp: start.addingTimeInterval(1),
            readBytes: 1_001_000,
            writeBytes: 2_002_000
        )

        let sample = DiskActivityRateCalculator.sample(previous: previous, current: current)

        XCTAssertEqual(sample.readMegabytesPerSecond, 1.0, accuracy: 0.0001)
        XCTAssertEqual(sample.writeMegabytesPerSecond, 2.0, accuracy: 0.0001)
    }

    func testDiskActivityRateCalculatorClampsCounterResetToZero() {
        let start = Date(timeIntervalSince1970: 1_000)
        let previous = DiskActivityCounters(timestamp: start, readBytes: 4_000, writeBytes: 8_000)
        let current = DiskActivityCounters(timestamp: start.addingTimeInterval(0.5), readBytes: 3_000, writeBytes: 7_000)

        let sample = DiskActivityRateCalculator.sample(previous: previous, current: current)

        XCTAssertEqual(sample.readMegabytesPerSecond, 0)
        XCTAssertEqual(sample.writeMegabytesPerSecond, 0)
    }

    func testDiskActivitySeriesKeepsLatestSamplesInsideLimit() {
        let start = Date(timeIntervalSince1970: 1_000)
        var samples: [DiskActivitySample] = []

        for index in 0..<5 {
            let sample = DiskActivitySample(
                timestamp: start.addingTimeInterval(Double(index)),
                readMegabytesPerSecond: Double(index),
                writeMegabytesPerSecond: Double(index * 2)
            )
            samples = DiskActivitySeries.appending(sample, to: samples, limit: 3)
        }

        XCTAssertEqual(samples.map(\.readMegabytesPerSecond), [2, 3, 4])
        XCTAssertEqual(samples.map(\.writeMegabytesPerSecond), [4, 6, 8])
    }

    func testDiskActivitySampleIntervalsAreFixed() {
        XCTAssertEqual(DiskActivitySampleInterval.allCases.map(\.seconds), [0.1, 0.2, 0.5, 1.0])
        XCTAssertEqual(DiskActivitySampleInterval.default, .half)
        XCTAssertEqual(DITViewModel.benchmarkActivityInterval, .half)
    }

    func testDiskActivityMonitorUsesSelectedIntervalAndCachedReader() async {
        let start = Date(timeIntervalSince1970: 1_000)
        let reader = FakeDiskActivityReader(counters: [
            DiskActivityCounters(timestamp: start, readBytes: 0, writeBytes: 0),
            DiskActivityCounters(timestamp: start.addingTimeInterval(0.1), readBytes: 100_000, writeBytes: 200_000)
        ])
        let provider = FakeDiskActivityProvider(reader: reader)
        let waitRequests = LockedArray<UInt64>()
        let samples = LockedArray<DiskActivitySample>()
        let monitor = DiskActivityMonitor(provider: provider) { nanoseconds in
            waitRequests.append(nanoseconds)
            if waitRequests.snapshot.count >= 2 {
                throw CancellationError()
            }
        }

        await monitor.run(bsdName: "disk0", interval: .tenth) { sample in
            samples.append(sample)
        }

        XCTAssertEqual(provider.readerCallCount, 1)
        XCTAssertEqual(provider.fallbackCounterCallCount, 0)
        XCTAssertEqual(waitRequests.snapshot, [100_000_000, 100_000_000])
        XCTAssertEqual(samples.snapshot.count, 2)
        XCTAssertEqual(samples.snapshot.last?.readMegabytesPerSecond ?? 0, 1.0, accuracy: 0.0001)
        XCTAssertEqual(samples.snapshot.last?.writeMegabytesPerSecond ?? 0, 2.0, accuracy: 0.0001)
    }

    func testDiskActivityChartScaleCreatesDurationAndSpeedTicks() {
        let start = Date(timeIntervalSince1970: 1_000)
        let samples = [
            DiskActivitySample(timestamp: start, readMegabytesPerSecond: 0, writeMegabytesPerSecond: 0),
            DiskActivitySample(timestamp: start.addingTimeInterval(45), readMegabytesPerSecond: 300, writeMegabytesPerSecond: 120),
            DiskActivitySample(timestamp: start.addingTimeInterval(90), readMegabytesPerSecond: 432, writeMegabytesPerSecond: 60)
        ]

        XCTAssertEqual(DiskActivityChartScale.durationSeconds(for: samples), 90, accuracy: 0.0001)
        XCTAssertEqual(DiskActivityChartScale.xTicks(for: samples).map(\.label), ["0s", "45s", "1m30s"])
        let yTicks = DiskActivityChartScale.yTicks(maxSpeed: 432)
        XCTAssertEqual(yTicks.count, 10)
        XCTAssertEqual(yTicks.first ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(yTicks.last ?? -1, 500, accuracy: 0.0001)
        XCTAssertEqual(yTicks[1], 500.0 / 9.0, accuracy: 0.0001)
    }

    func testDiskActivityHistoryRecordEncodesSamplesAndSummary() {
        let drive = Self.fixtureDrive()
        let start = Date(timeIntervalSince1970: 1_000)
        let samples = [
            DiskActivitySample(timestamp: start, readMegabytesPerSecond: 10, writeMegabytesPerSecond: 20),
            DiskActivitySample(timestamp: start.addingTimeInterval(1), readMegabytesPerSecond: 30, writeMegabytesPerSecond: 50)
        ]

        let record = DiskActivityHistoryRecord(
            drive: drive,
            samples: samples,
            sampleInterval: .half,
            startedAt: start,
            endedAt: start.addingTimeInterval(1)
        )

        XCTAssertEqual(record.driveID, drive.id)
        XCTAssertEqual(record.sampleInterval, .half)
        XCTAssertEqual(record.durationSeconds, 1)
        XCTAssertEqual(record.peakReadMegabytesPerSecond, 30)
        XCTAssertEqual(record.peakWriteMegabytesPerSecond, 50)
        XCTAssertEqual(record.averageReadMegabytesPerSecond, 20)
        XCTAssertEqual(record.averageWriteMegabytesPerSecond, 35)
        XCTAssertEqual(record.samples, samples)
    }

    func testDiskActivityWorkloadFullDiskUses95PercentOfAvailableCapacity() {
        let gib: Int64 = 1_024 * 1_024 * 1_024
        let mib: Int64 = 1_024 * 1_024
        let available = 100 * gib + DiskActivityWorkloadStorageValidator.safetyMarginBytes
        let usable = available - DiskActivityWorkloadStorageValidator.safetyMarginBytes
        let expectedSingle = (Int64(Double(usable) * 0.95) / mib) * mib
        let expectedMixed = ((Int64(Double(usable) * 0.95) / 2) / mib) * mib

        XCTAssertEqual(
            DiskActivityWorkloadStorageValidator.resolvedFileSize(for: .fullDisk95, operation: .write, availableCapacity: available),
            expectedSingle
        )
        XCTAssertEqual(
            DiskActivityWorkloadStorageValidator.resolvedFileSize(for: .fullDisk95, operation: .mixed, availableCapacity: available),
            expectedMixed
        )
        XCTAssertEqual(
            DiskActivityWorkloadStorageValidator.requiredSpace(fileSizeBytes: expectedSingle, operation: .write),
            expectedSingle + DiskActivityWorkloadStorageValidator.safetyMarginBytes
        )
        XCTAssertEqual(
            DiskActivityWorkloadStorageValidator.requiredSpace(fileSizeBytes: expectedMixed, operation: .mixed),
            expectedMixed * 2 + DiskActivityWorkloadStorageValidator.safetyMarginBytes
        )
    }

    func testDiskActivityWorkloadAvailabilityAccountsForMixedTwoFileFootprint() {
        let fileSize = DiskActivityWorkloadFileSize.gib32.fixedBytes!
        let required = DiskActivityWorkloadStorageValidator.requiredSpace(fileSizeBytes: fileSize, operation: .mixed)

        XCTAssertFalse(DiskActivityWorkloadStorageValidator.isFileSizeAvailable(.gib32, operation: .mixed, availableCapacity: required - 1))
        XCTAssertTrue(DiskActivityWorkloadStorageValidator.isFileSizeAvailable(.gib32, operation: .mixed, availableCapacity: required))
        XCTAssertEqual(required, fileSize * 2 + DiskActivityWorkloadStorageValidator.safetyMarginBytes)
    }

    func testDiskActivityWorkloadRunnerPreparesReadFileAndCleansUp() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let drive = Self.fixtureDrive(mountedAt: root.path)
        let names = LockedArray<String>()
        let progressValues = LockedArray<DiskActivityWorkloadProgress>()
        let runner = NativeDiskActivityWorkloadRunner(fileEventHandler: { url in
            names.append(url.lastPathComponent)
        })

        try await runner.run(
            configuration: DiskActivityWorkloadConfiguration(
                targetFolderURL: root,
                operation: .read,
                fileSizeOption: .gib32,
                fileSizeBytes: 32_768,
                loopEnabled: false
            ),
            drive: drive
        ) { progress in
            progressValues.append(progress)
        }

        XCTAssertEqual(names.snapshot.filter { $0.contains("read-source") }.count, 1)
        XCTAssertTrue(progressValues.snapshot.contains { $0.phase == .preparingReadFile })
        XCTAssertTrue(progressValues.snapshot.contains { $0.phase == .reading && $0.completedBytes == 32_768 })

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter {
            $0.hasPrefix("Disk-Speed-Test-Activity-")
        }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testDiskActivityWorkloadRunnerMixedUsesSeparateReadAndWriteFiles() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let drive = Self.fixtureDrive(mountedAt: root.path)
        let names = LockedArray<String>()
        let progressValues = LockedArray<DiskActivityWorkloadProgress>()
        let runner = NativeDiskActivityWorkloadRunner(fileEventHandler: { url in
            names.append(url.lastPathComponent)
        })

        try await runner.run(
            configuration: DiskActivityWorkloadConfiguration(
                targetFolderURL: root,
                operation: .mixed,
                fileSizeOption: .gib32,
                fileSizeBytes: 65_536,
                loopEnabled: false
            ),
            drive: drive
        ) { progress in
            progressValues.append(progress)
        }

        let createdNames = names.snapshot
        XCTAssertEqual(createdNames.filter { $0.contains("read-source") }.count, 1)
        XCTAssertEqual(createdNames.filter { $0.contains("mixed-write") }.count, 1)
        XCTAssertEqual(Set(createdNames).count, createdNames.count)
        XCTAssertTrue(progressValues.snapshot.contains { $0.phase == .mixed && $0.totalBytes == 131_072 })

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter {
            $0.hasPrefix("Disk-Speed-Test-Activity-")
        }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testDiskActivityWorkloadRunnerLoopCancelsAndCleansUp() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let drive = Self.fixtureDrive(mountedAt: root.path)
        let names = LockedArray<String>()
        let runner = NativeDiskActivityWorkloadRunner(fileEventHandler: { url in
            names.append(url.lastPathComponent)
        })

        do {
            try await runner.run(
                configuration: DiskActivityWorkloadConfiguration(
                    targetFolderURL: root,
                    operation: .write,
                    fileSizeOption: .gib32,
                    fileSizeBytes: 16_384,
                    loopEnabled: true
                ),
                drive: drive
            ) { progress in
                if progress.loopIndex >= 2, progress.phase == .writing {
                    runner.cancel()
                }
            }
            XCTFail("Expected cancellation")
        } catch BenchmarkError.cancelled {
        }

        XCTAssertGreaterThanOrEqual(names.snapshot.filter { $0.contains("-write-loop") }.count, 2)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter {
            $0.hasPrefix("Disk-Speed-Test-Activity-")
        }
        XCTAssertTrue(leftovers.isEmpty)
    }

    @MainActor
    func testLiveActivityWorkloadAutoStartsMonitoringAndStopsWithoutClearingChart() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let drive = Self.fixtureDrive(mountedAt: root.path)
        let reader = FakeDiskActivityReader(counters: [
            DiskActivityCounters(timestamp: Date(timeIntervalSince1970: 1), readBytes: 0, writeBytes: 0),
            DiskActivityCounters(timestamp: Date(timeIntervalSince1970: 2), readBytes: 1_000_000, writeBytes: 2_000_000)
        ])
        let workloadRunner = FakeDiskActivityWorkloadRunner()
        let model = DITViewModel(
            diskActivityProvider: FakeDiskActivityProvider(reader: reader),
            liveActivityWorkloadRunner: workloadRunner
        )
        model.drives = [drive]
        model.liveActivitySelectedDriveID = drive.id

        model.startLiveActivityWorkload(
            configuration: DiskActivityWorkloadConfiguration(
                targetFolderURL: root,
                operation: .write,
                fileSizeOption: .gib32,
                fileSizeBytes: 16_384,
                loopEnabled: true
            ),
            drive: drive,
            interval: .tenth
        )

        XCTAssertTrue(model.isLiveActivityWorkloadRunning)
        XCTAssertTrue(model.isLiveActivityMonitoring)

        model.stopLiveActivityWorkload()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(model.isLiveActivityWorkloadRunning)
        XCTAssertTrue(model.isLiveActivityMonitoring)
        XCTAssertNil(model.liveActivityWorkloadError)
        model.stopLiveActivityMonitoring()
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

    func testBenchmarkMeasurementReducerAveragesAsyncTransferAndFlushMetrics() {
        let summary = BenchmarkMeasurementReducer.summarize([
            BenchmarkRunMeasurement(megabytesPerSecond: 100, iops: 10, latencyMicroseconds: 50, bytesTransferred: 1_000, transferMegabytesPerSecond: 140, flushMilliseconds: 20),
            BenchmarkRunMeasurement(megabytesPerSecond: 200, iops: 20, latencyMicroseconds: 40, bytesTransferred: 2_000, transferMegabytesPerSecond: 260, flushMilliseconds: 40)
        ])

        XCTAssertEqual(summary.megabytesPerSecond, 150, accuracy: 0.001)
        XCTAssertEqual(summary.transferMegabytesPerSecond ?? 0, 200, accuracy: 0.001)
        XCTAssertEqual(summary.flushMilliseconds ?? 0, 30, accuracy: 0.001)
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

        let asyncChinese = AppLanguage.simplifiedChinese.benchmarkConfigurationDescription(
            profile: .asyncTest,
            runs: 3,
            fileSizeBytes: BenchmarkProfile.defaultTestSize,
            dataPattern: .random,
            usesTrimmedAverage: false
        )
        XCTAssertEqual(AppLanguage.simplifiedChinese.profileName(.asyncTest), "测试")
        XCTAssertTrue(asyncChinese.profileUse.contains("异步"))
        XCTAssertTrue(asyncChinese.testTerms.contains("POSIX AIO"))
        XCTAssertTrue(asyncChinese.testTerms.contains("刷盘"))

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

    func testBenchmarkStorageValidatorCountsLoopReadPreparationFiles() {
        let readA = BenchmarkTest(
            id: "loop-read-a",
            label: "SEQ1M Q1T1",
            accessPattern: .sequential,
            operation: .read,
            blockSizeBytes: 4_096,
            queueDepth: 1,
            threads: 1,
            durationSeconds: 0.001,
            testSizeBytes: 16_384,
            dataPattern: .zeroFill,
            writePercentForMixed: 0
        )
        var readB = readA
        readB.id = "loop-read-b"
        readB.testSizeBytes = 32_768
        var write = readA
        write.id = "loop-write"
        write.operation = .write
        write.testSizeBytes = 65_536
        write.writePercentForMixed = 100
        let profile = BenchmarkProfile(
            id: "loop-space",
            name: "Loop Space",
            testFileSizeBytes: 65_536,
            runs: 1,
            executionMode: .loopUntilCancelled,
            tests: [readA, readB, write]
        )
        let required = Int64(16_384 + 32_768 + 65_536) + BenchmarkStorageValidator.safetyMarginBytes

        XCTAssertEqual(BenchmarkStorageValidator.requiredSpace(for: profile), required)
        XCTAssertFalse(BenchmarkStorageValidator.isRequiredSpaceAvailable(for: profile, availableCapacity: required - 1))
        XCTAssertTrue(BenchmarkStorageValidator.isRequiredSpaceAvailable(for: profile, availableCapacity: required))
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

    func testBenchmarkRunnerReusesPreparedFileForReadPasses() async throws {
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
            testSizeBytes: 32_768,
            dataPattern: .zeroFill,
            writePercentForMixed: 0
        )
        let profile = BenchmarkProfile(id: "unit", name: "Unit", testFileSizeBytes: 32_768, runs: 3, tests: [read])
        let lock = NSLock()
        var createdNames: [String] = []
        let runner = NativeBenchmarkRunner(operationIntervalSeconds: 0, passIntervalSeconds: 0, fileEventHandler: { url in
            lock.lock()
            createdNames.append(url.lastPathComponent)
            lock.unlock()
        })

        let results = try await runner.run(profile: profile, drive: drive, volumePath: root.path, progress: { _ in }, result: { _ in })

        lock.lock()
        let names = createdNames
        lock.unlock()
        XCTAssertEqual(results.first?.bytesTransferred, 32_768)
        XCTAssertEqual(names.count, 1)
        XCTAssertTrue(names.first?.contains("read-run0") == true)

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter {
            $0.hasPrefix("Disk-Speed-Test-") || $0.hasPrefix(".dit-benchmark-")
        }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testBenchmarkRunnerReusesReadFileButKeepsWriteAndMixedFilesPerPass() async throws {
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
        var mixed = read
        mixed.id = "unit-mixed"
        mixed.operation = .mixed
        mixed.writePercentForMixed = 30
        let profile = BenchmarkProfile(id: "unit", name: "Unit", testFileSizeBytes: 8_192, runs: 2, tests: [read, write, mixed])
        let lock = NSLock()
        var createdNames: [String] = []
        let runner = NativeBenchmarkRunner(operationIntervalSeconds: 0, passIntervalSeconds: 0, fileEventHandler: { url in
            lock.lock()
            createdNames.append(url.lastPathComponent)
            lock.unlock()
        })

        let results = try await runner.run(profile: profile, drive: drive, volumePath: root.path, progress: { _ in }, result: { _ in })

        lock.lock()
        let names = createdNames
        lock.unlock()
        XCTAssertEqual(results.map(\.testID), ["unit-read", "unit-write", "unit-mixed"])
        XCTAssertEqual(names.filter { $0.contains("-read-run") }.count, 1)
        XCTAssertEqual(names.filter { $0.contains("-write-run") }.count, 3)
        XCTAssertEqual(names.filter { $0.contains("-mixed-run") }.count, 3)
    }

    func testAsyncQueueBenchmarkRunnerPublishesTransferAndFlushMetrics() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "unit", name: "Unit", mountPoint: root.path, sizeBytes: 1_000_000, isWritable: true, isSystem: false)
        ]
        let write = BenchmarkTest(
            id: "async-write",
            label: "SEQ4K Q2T1",
            accessPattern: .sequential,
            operation: .write,
            blockSizeBytes: 4_096,
            queueDepth: 2,
            threads: 1,
            durationSeconds: 0.001,
            testSizeBytes: 65_536,
            dataPattern: .zeroFill,
            writePercentForMixed: 100
        )
        let profile = BenchmarkProfile(
            id: "async-unit",
            name: "Async Unit",
            testFileSizeBytes: 65_536,
            runs: 1,
            engine: .asyncQueue,
            tests: [write]
        )
        var published: [BenchmarkResult] = []
        let runner = AsyncQueueBenchmarkRunner(operationIntervalSeconds: 0, passIntervalSeconds: 0)

        let results = try await runner.run(profile: profile, drive: drive, volumePath: root.path, progress: { _ in }) { result in
            published.append(result)
        }

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(published.count, 1)
        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(result.bytesTransferred, 65_536)
        XCTAssertNotNil(result.transferMegabytesPerSecond)
        XCTAssertNotNil(result.flushMilliseconds)
        XCTAssertGreaterThanOrEqual(result.transferMegabytesPerSecond ?? 0, result.bestMegabytesPerSecond)

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter {
            $0.hasPrefix("Disk-Speed-Test-") || $0.hasPrefix(".dit-benchmark-")
        }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testAsyncQueueBenchmarkRunnerReusesPreparedFileForReadPasses() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "unit", name: "Unit", mountPoint: root.path, sizeBytes: 1_000_000, isWritable: true, isSystem: false)
        ]
        let read = BenchmarkTest(
            id: "async-read",
            label: "SEQ4K Q2T1",
            accessPattern: .sequential,
            operation: .read,
            blockSizeBytes: 4_096,
            queueDepth: 2,
            threads: 1,
            durationSeconds: 0.001,
            testSizeBytes: 65_536,
            dataPattern: .zeroFill,
            writePercentForMixed: 0
        )
        let profile = BenchmarkProfile(
            id: "async-unit",
            name: "Async Unit",
            testFileSizeBytes: 65_536,
            runs: 2,
            engine: .asyncQueue,
            tests: [read]
        )
        let lock = NSLock()
        var createdNames: [String] = []
        let runner = AsyncQueueBenchmarkRunner(operationIntervalSeconds: 0, passIntervalSeconds: 0, fileEventHandler: { url in
            lock.lock()
            createdNames.append(url.lastPathComponent)
            lock.unlock()
        })

        let results = try await runner.run(profile: profile, drive: drive, volumePath: root.path, progress: { _ in }, result: { _ in })

        lock.lock()
        let names = createdNames
        lock.unlock()
        XCTAssertEqual(results.first?.bytesTransferred, 65_536)
        XCTAssertEqual(names.count, 1)
        XCTAssertTrue(names.first?.contains("read-run0") == true)
    }

    func testAsyncQueueBenchmarkRunnerLoopPublishesLatestPassAndStopsWithoutWaiting() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "unit", name: "Unit", mountPoint: root.path, sizeBytes: 1_000_000, isWritable: true, isSystem: false)
        ]
        let read = BenchmarkTest(
            id: "async-loop-read",
            label: "SEQ4K Q2T1",
            accessPattern: .sequential,
            operation: .read,
            blockSizeBytes: 4_096,
            queueDepth: 2,
            threads: 1,
            durationSeconds: 0.001,
            testSizeBytes: 8_192,
            dataPattern: .zeroFill,
            writePercentForMixed: 0
        )
        var write = read
        write.id = "async-loop-write"
        write.operation = .write
        write.writePercentForMixed = 100
        let profile = BenchmarkProfile(
            id: "async-loop-unit",
            name: "Async Loop Unit",
            testFileSizeBytes: 8_192,
            runs: 9,
            executionMode: .loopUntilCancelled,
            engine: .asyncQueue,
            tests: [read, write]
        )

        let lock = NSLock()
        var requestedWaits: [TimeInterval] = []
        var published: [BenchmarkResult] = []
        var createdNames: [String] = []
        let runner = AsyncQueueBenchmarkRunner(
            operationIntervalSeconds: 5,
            passIntervalSeconds: 1,
            operationSleeper: { seconds, _ in
                lock.lock()
                requestedWaits.append(seconds)
                lock.unlock()
            },
            fileEventHandler: { url in
                lock.lock()
                createdNames.append(url.lastPathComponent)
                lock.unlock()
            }
        )

        let results = try await runner.run(profile: profile, drive: drive, volumePath: root.path, progress: { _ in }) { result in
            lock.lock()
            published.append(result)
            let shouldCancel = published.count == 4
            lock.unlock()
            if shouldCancel {
                runner.cancel()
            }
        }

        lock.lock()
        let waits = requestedWaits
        let publishedIDs = published.map(\.testID)
        let names = createdNames
        lock.unlock()

        let expectedCycle = ["async-loop-read", "async-loop-write"]
        XCTAssertEqual(publishedIDs, expectedCycle + expectedCycle)
        XCTAssertEqual(results.map(\.testID), expectedCycle)
        XCTAssertTrue(results.allSatisfy { $0.bytesTransferred == 8_192 })
        XCTAssertTrue(waits.isEmpty)
        XCTAssertEqual(names.filter { $0.contains("-read-run") }.count, 1)
        XCTAssertEqual(names.filter { $0.contains("-write-run") }.count, 2)

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter {
            $0.hasPrefix("Disk-Speed-Test-") || $0.hasPrefix(".dit-benchmark-")
        }
        XCTAssertTrue(leftovers.isEmpty)
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
        var createdNames: [String] = []
        let runner = NativeBenchmarkRunner(
            operationIntervalSeconds: 5,
            passIntervalSeconds: 1,
            operationSleeper: { seconds, _ in
                lock.lock()
                requestedWaits.append(seconds)
                lock.unlock()
            },
            fileEventHandler: { url in
                lock.lock()
                createdNames.append(url.lastPathComponent)
                lock.unlock()
            }
        )

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
        let names = createdNames
        lock.unlock()

        let expectedCycle = ["loop-read-q1", "loop-write-q1", "loop-read-q8", "loop-write-q8"]
        XCTAssertEqual(publishedIDs, expectedCycle + expectedCycle)
        XCTAssertEqual(results.map(\.testID), expectedCycle)
        XCTAssertTrue(results.allSatisfy { $0.bytesTransferred == 8_192 })
        XCTAssertTrue(waits.isEmpty)
        XCTAssertEqual(names.filter { $0.contains("-read-run") }.count, 2)
        XCTAssertEqual(names.filter { $0.contains("-write-run") }.count, 4)

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

    func testHistoryVisibilitySeparatesVisibleAndHiddenActivityRecords() {
        let drive = Self.fixtureDrive()
        let visible = Self.fixtureActivityRecord(for: drive)
        let hidden = Self.fixtureActivityRecord(for: drive)

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

    func testHistoryVisibilityHideAllCanLimitToCurrentDrive() {
        let drive = Self.fixtureDrive()
        var otherDrive = drive
        otherDrive.bsdName = "disk9"
        let currentDriveRecord = SmartHistoryRecord(drive: drive, snapshot: Self.fixtureSnapshot(for: drive))
        let otherDriveRecord = SmartHistoryRecord(drive: otherDrive, snapshot: Self.fixtureSnapshot(for: otherDrive))

        HistoryVisibility.hideAll([currentDriveRecord, otherDriveRecord], at: Date(timeIntervalSince1970: 1), driveID: drive.id)

        XCTAssertNotNil(currentDriveRecord.hiddenAt)
        XCTAssertNil(otherDriveRecord.hiddenAt)
        XCTAssertEqual(HistoryVisibility.visible([currentDriveRecord, otherDriveRecord]).map(\.id), [otherDriveRecord.id])
        XCTAssertEqual(HistoryVisibility.hidden([currentDriveRecord, otherDriveRecord]).map(\.id), [currentDriveRecord.id])
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

    private static func fixtureDrive(mountedAt mountPoint: String) -> DriveDevice {
        var drive = fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "unit", name: "Unit", mountPoint: mountPoint, sizeBytes: 1_000_000_000, isWritable: true, isSystem: false)
        ]
        return drive
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

    private static func fixtureActivityRecord(for drive: DriveDevice) -> DiskActivityHistoryRecord {
        let start = Date(timeIntervalSince1970: 1_000)
        return DiskActivityHistoryRecord(
            drive: drive,
            samples: [
                DiskActivitySample(timestamp: start, readMegabytesPerSecond: 1, writeMegabytesPerSecond: 2),
                DiskActivitySample(timestamp: start.addingTimeInterval(1), readMegabytesPerSecond: 3, writeMegabytesPerSecond: 4)
            ],
            sampleInterval: .half,
            startedAt: start,
            endedAt: start.addingTimeInterval(1)
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

private final class LockedArray<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Element] = []

    var snapshot: [Element] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    func append(_ value: Element) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }
}

private final class FakeDiskActivityProvider: DiskActivityProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let fakeReader: FakeDiskActivityReader
    private var readerCalls = 0
    private var fallbackCounterCalls = 0

    init(reader: FakeDiskActivityReader) {
        self.fakeReader = reader
    }

    var readerCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return readerCalls
    }

    var fallbackCounterCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return fallbackCounterCalls
    }

    func reader(forBSDName bsdName: String) -> DiskActivityCounterReading? {
        lock.lock()
        readerCalls += 1
        lock.unlock()
        return fakeReader
    }

    func counters(forBSDName bsdName: String) -> DiskActivityCounters? {
        lock.lock()
        fallbackCounterCalls += 1
        lock.unlock()
        return nil
    }
}

private final class FakeDiskActivityReader: DiskActivityCounterReading, @unchecked Sendable {
    private let lock = NSLock()
    private let values: [DiskActivityCounters]
    private var index = 0

    init(counters: [DiskActivityCounters]) {
        self.values = counters
    }

    func counters() -> DiskActivityCounters? {
        lock.lock()
        defer { lock.unlock() }
        guard !values.isEmpty else { return nil }
        let value = values[min(index, values.count - 1)]
        index += 1
        return value
    }
}

private final class FakeDiskActivityWorkloadRunner: DiskActivityWorkloadRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func run(
        configuration: DiskActivityWorkloadConfiguration,
        drive: DriveDevice,
        progress: @escaping (DiskActivityWorkloadProgress) -> Void
    ) async throws {
        progress(DiskActivityWorkloadProgress(
            operation: configuration.operation,
            phase: .writing,
            loopIndex: 1,
            completedBytes: 0,
            totalBytes: configuration.fileSizeBytes,
            message: "Writing workload file"
        ))

        while !isCancelled {
            if Task.isCancelled {
                throw BenchmarkError.cancelled
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        throw BenchmarkError.cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}
