// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XCTest
@testable import Capricorn

final class UpdateTests: XCTestCase {
    func testAppVersionUsesBuildAsThirdComponent() {
        let version = AppVersion(marketingVersion: "1.2", build: "11")

        XCTAssertEqual(version.displayValue, "1.2.11")
        XCTAssertLessThan(AppVersion("1.2.10"), version)
        XCTAssertEqual(AppVersion("v1.2.11"), version)
        XCTAssertGreaterThan(AppVersion("1.3.0"), version)
    }

    func testGitHubReleaseParserUsesStableReleaseMetadata() throws {
        let data = Data("{\"tag_name\":\"v1.2.12\",\"name\":\"Capricorn V1.2.12\",\"html_url\":\"https://github.com/LexTheAries2209/Capricorn/releases/tag/v1.2.12\",\"body\":\"SMART improvements\",\"draft\":false,\"prerelease\":false}".utf8)

        let release = try GitHubReleaseService.parseRelease(data: data)

        XCTAssertEqual(release.tagName, "v1.2.12")
        XCTAssertEqual(release.version, AppVersion("1.2.12"))
        XCTAssertEqual(release.body, "SMART improvements")
    }

    @MainActor
    func testUpdateCheckerReportsAvailableAndUpToDateStates() async {
        let release = AppUpdateRelease(
            tagName: "v1.2.12",
            name: "Capricorn V1.2.12",
            version: AppVersion("1.2.12"),
            htmlURL: URL(string: "https://github.com/LexTheAries2209/Capricorn/releases/tag/v1.2.12")!,
            body: ""
        )
        let checker = AppUpdateChecker(currentVersion: AppVersion("1.2.11"), fetchLatest: { release })

        await checker.checkNow()
        XCTAssertEqual(checker.state, .updateAvailable(release))

        let currentChecker = AppUpdateChecker(currentVersion: AppVersion("1.2.12"), fetchLatest: { release })
        await currentChecker.checkNow()
        XCTAssertEqual(currentChecker.state, .upToDate)
    }

    @MainActor
    func testUpdateCheckerReportsConnectionFailureAndOnlyChecksLaunchOnce() async {
        let checker = AppUpdateChecker(
            currentVersion: AppVersion("1.2.11"),
            fetchLatest: { throw URLError(.notConnectedToInternet) }
        )

        await checker.checkQuietlyAtLaunch()
        let firstCheckDate = checker.lastCheckedAt
        XCTAssertEqual(checker.state, .failed)
        XCTAssertNotNil(firstCheckDate)

        await checker.checkQuietlyAtLaunch()
        XCTAssertEqual(checker.lastCheckedAt, firstCheckDate)
    }
}
