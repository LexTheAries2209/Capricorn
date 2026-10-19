import XCTest
@testable import Capricorn

final class BenchmarkProfileConfigurationTests: XCTestCase {
    func testEveryPresetAndLegacyProfileKeepsConcurrencyAtMostSixteen() {
        let profiles = BenchmarkProfile.presets + [.peakNVMe, .realWorld, .demoLight, .asyncTest, .loop, .extremeLoop]
        for profile in profiles {
            for test in profile.tests {
                XCTAssertGreaterThan(test.queueDepth, 0)
                XCTAssertGreaterThan(test.threads, 0)
                XCTAssertLessThanOrEqual(test.queueDepth * test.threads, 16, test.label)
            }
        }
        XCTAssertEqual(BenchmarkProfile.presets.map(\.id), ["default", "quick", "ssd", "hdd", "custom"])
        XCTAssertEqual(Set(BenchmarkProfile.ssd.tests.map(\.rowLabel)), [
            "SEQ1MiB Q8T2", "SEQ1MiB Q1T1", "RND4KiB Q4T4", "RND4KiB Q1T1"
        ])
        XCTAssertTrue(BenchmarkProfile.hdd.tests.allSatisfy { $0.threads == 1 })
    }

    func testQuickStaysSmallAndSingleRunRegardlessOfSavedSettings() {
        let profile = BenchmarkProfile.quick.configured(
            runs: 9, fileSizeBytes: 64 * 1_024 * 1_024 * 1_024, dataPattern: .random,
            usesTrimmedAverage: true, usesSmallBlockEfficiency: true, smallBlockFileSizePercent: 5
        )
        XCTAssertEqual(profile.runs, 1)
        XCTAssertFalse(profile.usesTrimmedAverage)
        XCTAssertEqual(profile.testFileSizeBytes, 128 * 1_024 * 1_024)
        XCTAssertEqual(profile.tests.count, 4)
        XCTAssertEqual(Set(profile.tests.map(\.rowLabel)), ["SEQ1MiB Q1T1", "RND4KiB Q1T1"])
        for test in profile.tests {
            XCTAssertEqual(test.testSizeBytes, test.accessPattern == .random ? 1_024 * 1_024 : 128 * 1_024 * 1_024)
            XCTAssertNotEqual(test.operation, .mixed)
        }
    }

    func testCustomQueueDepthChangesClampThreadsAndPersist() {
        var row = BenchmarkCustomRow.defaultRows[0]
        row.selectThreads(16)
        XCTAssertEqual(row.threads, 16)
        row.selectQueueDepth(8)
        XCTAssertEqual(row.queueDepth, 8)
        XCTAssertEqual(row.threads, 2)
        XCTAssertEqual(row.availableThreadOptions, [1, 2])
        row.selectThreads(16)
        XCTAssertEqual(row.threads, 2)
        row.selectQueueDepth(16)
        XCTAssertEqual(row.threads, 1)
        XCTAssertEqual(row.availableThreadOptions, [1])
        row.selectQueueDepth(1)
        XCTAssertEqual(row.availableThreadOptions, [1, 2, 4, 8, 16])
        XCTAssertEqual(row.threads, 1)
        XCTAssertEqual(BenchmarkCustomRow.decodeList(from: BenchmarkCustomRow.encodeList([row])), [row])
    }

    func testEveryOfferedCustomCombinationFitsAndLegacyRowsMigrate() throws {
        for depth in BenchmarkCustomRow.queueDepthOptions {
            for threads in BenchmarkConcurrency.threadOptions(queueDepth: depth) {
                XCTAssertLessThanOrEqual(depth * threads, 16)
            }
        }
        let rows = [
            BenchmarkCustomRow(id: "old", accessPattern: .random, blockSizeBytes: 4096, queueDepth: 32, threads: 16, includeMixed: true),
            BenchmarkCustomRow(id: "invalid", accessPattern: .sequential, blockSizeBytes: 4096, queueDepth: -1, threads: Int.max, includeMixed: false)
        ]
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(rows), encoding: .utf8))
        let decoded = BenchmarkCustomRow.decodeList(from: encoded)
        XCTAssertEqual(decoded[0].queueDepth, 16)
        XCTAssertEqual(decoded[0].threads, 1)
        XCTAssertEqual(decoded[1].queueDepth, 1)
        XCTAssertEqual(decoded[1].threads, 16)
        XCTAssertEqual(decoded.map(\.id), ["old", "invalid"])
        XCTAssertTrue(decoded[0].includeMixed)
    }

    func testNewResultsHaveDifferentIdentityFromOldThreadMultiplierResults() {
        for preset in BenchmarkProfile.presets {
            let configured = preset.configured(runs: 3, fileSizeBytes: BenchmarkProfile.defaultTestSize, dataPattern: .random)
            XCTAssertTrue(configured.id.contains("workers-v2"))
            XCTAssertTrue(configured.tests.allSatisfy { $0.id.contains("workers-v2") })
        }
    }

    func testProfileNamesAndQuickExplanationAreBilingual() {
        XCTAssertEqual(BenchmarkProfile.presets.map { AppLanguage.simplifiedChinese.profileName($0) }, ["默认", "快速", "SSD", "HDD", "自定义"])
        XCTAssertEqual(BenchmarkProfile.presets.map { AppLanguage.english.profileName($0) }, ["Default", "Quick", "SSD", "HDD", "Custom"])
        for language in AppLanguage.allCases {
            let description = language.benchmarkConfigurationDescription(
                profile: .quick, runs: 1, fileSizeBytes: BenchmarkProfile.quickTestSize,
                dataPattern: .random, usesTrimmedAverage: false
            )
            XCTAssertTrue(description.fileSize.contains("128 MiB"))
            XCTAssertTrue(description.fileSize.contains("1 MiB"))
            XCTAssertTrue(description.testTerms.contains("16"))
        }
    }
}
