// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation
import IOKit

enum SATSMARTDriverState: String, Equatable, Sendable {
    case notInstalled
    case installedNotLoaded
    case loaded
    case inconclusive
}

struct SATSMARTDriverStatus: Equatable, Sendable {
    var state: SATSMARTDriverState
    var version: String?
    var kextPath: String?
    var pluginPath: String?
    var message: String
}

enum SATSMARTDriverGuidance: Equatable, Sendable {
    case installationSuggested
    case activationRequired
}

enum SATSMARTDriverGuidancePolicy {
    static func guidance(
        for drive: DriveDevice,
        snapshot: SmartSnapshot?,
        driverStatus: SATSMARTDriverStatus
    ) -> SATSMARTDriverGuidance? {
        guard let snapshot,
              !snapshot.hasSMARTPayload,
              !drive.isInternal,
              !drive.isSystemDisk,
              !drive.isNetwork,
              !drive.isVirtual,
              !drive.isMemoryCard,
              drive.protocolName.localizedCaseInsensitiveContains("USB"),
              !diagnosticsIdentifyNVMe(snapshot.smartctlDiagnostics) else {
            return nil
        }

        switch driverStatus.state {
        case .notInstalled:
            return .installationSuggested
        case .installedNotLoaded, .inconclusive:
            return .activationRequired
        case .loaded:
            return nil
        }
    }

    private static func diagnosticsIdentifyNVMe(_ diagnostics: SmartctlDiagnostics?) -> Bool {
        let values = [
            diagnostics?.selectedTransport,
            diagnostics?.deviceType,
            diagnostics?.protocolName
        ]
            .compactMap { $0?.lowercased() }
        return values.contains { $0.contains("nvme") || $0.hasPrefix("snt") }
    }
}

struct SATSMARTDriverService: Sendable {
    private let kextPath = "/Library/Extensions/SATSMARTDriver.kext"
    private let pluginPath = "/Library/Extensions/SATSMARTLib.plugin"
    static let packageURL = URL(string: "https://binaryfruit.com/download/mac/satsmartdriver/SATSMARTDriver-0.10.3.macOS11_and_AppleSilicon.zip")!
    static let guideURL = URL(string: "https://binaryfruit.com/drivedx/usb-drive-support")!
    static let sourceURL = URL(string: "https://github.com/kasbert/OS-X-SAT-SMART-Driver")!

    func status() -> SATSMARTDriverStatus {
        let fileManager = FileManager.default
        let hasFiles = fileManager.fileExists(atPath: kextPath)
            && fileManager.fileExists(atPath: pluginPath)
        guard hasFiles else {
            return SATSMARTDriverStatus(state: .notInstalled, version: nil, kextPath: nil, pluginPath: nil, message: "SAT SMART Driver is not installed.")
        }
        let plist = try? PropertyListSerialization.propertyList(
            from: Data(contentsOf: URL(fileURLWithPath: "\(kextPath)/Contents/Info.plist")),
            options: [],
            format: nil
        ) as? [String: Any]
        let version = plist?["CFBundleShortVersionString"] as? String
        let matching = IOServiceMatching("fi_dungeon_driver_IOSATDriver")
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        let isLoaded = result == KERN_SUCCESS && IOIteratorIsValid(iterator) != 0 && IOIteratorNext(iterator) != 0
        IOObjectRelease(iterator)
        return SATSMARTDriverStatus(
            state: isLoaded ? .loaded : .installedNotLoaded,
            version: version,
            kextPath: kextPath,
            pluginPath: pluginPath,
            message: isLoaded
                ? "SAT SMART Driver is loaded and has an IOKit match."
                : "SAT SMART Driver files are installed."
        )
    }

    func revealPackage() {
        guard let resource = Bundle.main.url(forResource: "SATSMARTDriver-0.10.3", withExtension: "pkg") else { return }
        NSWorkspace.shared.activateFileViewerSelecting([resource])
    }
}
