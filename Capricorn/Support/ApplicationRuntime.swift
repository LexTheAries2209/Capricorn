// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum ApplicationRuntime {
    #if CAPRICORN_VIRTUAL_T7_DEMO
    static let isVirtualT7DemoBuild = true
    #else
    static let isVirtualT7DemoBuild = false
    #endif

    static let isRunningTests = isTestProcess(environment: ProcessInfo.processInfo.environment)
    static let allowsAutomaticStartupTasks = !isVirtualT7DemoBuild
        && shouldRunAutomaticStartupTasks(environment: ProcessInfo.processInfo.environment)

    static func isTestProcess(environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCInjectBundleInto"] != nil
    }

    static func shouldRunAutomaticStartupTasks(environment: [String: String]) -> Bool {
        guard !isTestProcess(environment: environment) else { return false }
        let disabled = environment["CAPRICORN_DISABLE_STARTUP_TASKS"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return disabled != "1" && disabled != "true" && disabled != "yes"
    }
}
