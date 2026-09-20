// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum ApplicationRuntime {
    static let isRunningTests = isTestProcess(environment: ProcessInfo.processInfo.environment)

    static func isTestProcess(environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCInjectBundleInto"] != nil
    }
}
