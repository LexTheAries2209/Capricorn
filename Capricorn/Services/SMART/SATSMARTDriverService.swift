// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation
import IOKit
import IOKit.kext

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
              !identifiesNVMe(drive: drive, diagnostics: snapshot.smartctlDiagnostics) else {
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

    private static func identifiesNVMe(drive: DriveDevice, diagnostics: SmartctlDiagnostics?) -> Bool {
        let values = [
            drive.protocolName,
            diagnostics?.selectedTransport,
            diagnostics?.deviceType,
            diagnostics?.protocolName
        ]
            .compactMap { $0?.lowercased() }
        return values.contains { $0.contains("nvme") || $0.hasPrefix("snt") }
    }
}

struct SATSMARTDriverService: Sendable {
    private static let bundleIdentifier = "com.binaryfruit.driver.SATSMARTDriver"
    private let kextPath = "/Library/Extensions/SATSMARTDriver.kext"
    private let pluginPath = "/Library/Extensions/SATSMARTLib.plugin"
    private let fileExistsAtPath: @Sendable (String) -> Bool
    private let readDataAtURL: @Sendable (URL) -> Data?
    private let isKernelExtensionLoaded: @Sendable () -> Bool
    static let guideURL = URL(string: "https://binaryfruit.com/drivedx/usb-drive-support")!
    static let sourceURL = URL(string: "https://github.com/kasbert/OS-X-SAT-SMART-Driver")!

    init() {
        fileExistsAtPath = { FileManager.default.fileExists(atPath: $0) }
        readDataAtURL = { try? Data(contentsOf: $0) }
        isKernelExtensionLoaded = Self.kernelExtensionIsLoaded
    }

    init(
        fileExistsAtPath: @escaping @Sendable (String) -> Bool,
        readDataAtURL: @escaping @Sendable (URL) -> Data?,
        isKernelExtensionLoaded: @escaping @Sendable () -> Bool
    ) {
        self.fileExistsAtPath = fileExistsAtPath
        self.readDataAtURL = readDataAtURL
        self.isKernelExtensionLoaded = isKernelExtensionLoaded
    }

    func status() -> SATSMARTDriverStatus {
        let hasFiles = fileExistsAtPath(kextPath) && fileExistsAtPath(pluginPath)
        guard hasFiles else {
            return SATSMARTDriverStatus(state: .notInstalled, version: nil, kextPath: nil, pluginPath: nil, message: "SAT SMART Driver is not installed.")
        }
        let plist = try? PropertyListSerialization.propertyList(
            from: readDataAtURL(URL(fileURLWithPath: "\(kextPath)/Contents/Info.plist")) ?? Data(),
            options: [],
            format: nil
        ) as? [String: Any]
        let version = plist?["CFBundleShortVersionString"] as? String
        let isLoaded = isKernelExtensionLoaded()
        return SATSMARTDriverStatus(
            state: isLoaded ? .loaded : .installedNotLoaded,
            version: version,
            kextPath: kextPath,
            pluginPath: pluginPath,
            message: isLoaded
                ? "SAT SMART Driver is loaded."
                : "SAT SMART Driver files are installed."
        )
    }

    private static func kernelExtensionIsLoaded() -> Bool {
        let identifiers = NSArray(object: bundleIdentifier) as CFArray
        guard let loadedInfo = KextManagerCopyLoadedKextInfo(identifiers, nil)?.takeRetainedValue() as? [String: Any],
              let driverInfo = loadedInfo[bundleIdentifier] as? [String: Any] else {
            return false
        }
        return driverInfo["OSBundleStarted"] as? Bool ?? true
    }

    func revealPackage() {
        guard let resource = Bundle.main.url(forResource: "SATSMARTDriver-0.10.3", withExtension: "pkg") else { return }
        NSWorkspace.shared.activateFileViewerSelecting([resource])
    }
}
