// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum DeviceHelperIdentity {
    static let service = "lex.Capricorn.DeviceHelper"
    static let executable = "CapricornDeviceHelper"
    static let appIdentifier = "lex.Capricorn"
    static let protocolVersion = 2
    static let plistName = service + ".plist"
}

@objc protocol DeviceHelperXPC {
    func version(reply: @escaping (Int) -> Void)
    func installation(reply: @escaping (String) -> Void)
    func perform(_ request: Data, reply: @escaping @Sendable (Data?, String?) -> Void)
    func result(_ requestID: String, reply: @escaping (Data?) -> Void)
    func prepareToStop(reply: @escaping (Bool) -> Void)
    func cancelStop(reply: @escaping () -> Void)
}

enum DeviceHelperOperation: String, Codable, CaseIterable, Sendable {
    case readSMART, selfTestCapability, selfTestLog, errorLog
    case startShortSelfTest, startLongSelfTest, abortSelfTest
    case readSNT

    var changesSelfTest: Bool {
        [.startShortSelfTest, .startLongSelfTest, .abortSelfTest].contains(self)
    }
}

struct DeviceHelperDisk: Codable, Equatable, Sendable {
    let bsdName: String
    let mediaRegistryID: UInt64
    let sizeBytes: Int64
    let usbRegistryID: UInt64?
    let isInternal: Bool
}

struct DeviceHelperRequest: Codable, Sendable {
    var version = DeviceHelperIdentity.protocolVersion
    var id = UUID()
    let operation: DeviceHelperOperation
    let disk: DeviceHelperDisk
    let deviceType: String?
    // An IORegistry ancestor, not a client-supplied arbitrary IOService path.
    var transportRegistryID: UInt64? = nil
    var avoidWaking = false
    var confirmedUnmount = false

    func validate() throws {
        guard version == DeviceHelperIdentity.protocolVersion else {
            throw DeviceHelperError.rejected("The device helper version does not match this application.")
        }
        guard disk.bsdName.range(of: #"^disk[0-9]+\z"#, options: .regularExpression) != nil,
              disk.mediaRegistryID > 0, disk.sizeBytes > 0 else {
            throw DeviceHelperError.rejected("The physical disk identity is invalid.")
        }
        let allowedTypes: Set<String> = [
            "ata", "scsi", "sat", "sat,12", "sat,16", "nvme",
            "sntasmedia", "sntjmicron", "sntrealtek", "sntjmicron/sat", "sntrealtek/sat"
        ]
        if let deviceType, !allowedTypes.contains(deviceType) {
            throw DeviceHelperError.rejected("This SMART transport is not allowed by the device helper.")
        }
        if operation == .readSNT {
            guard confirmedUnmount, !disk.isInternal, disk.usbRegistryID != nil,
                  ["sntasmedia", "sntjmicron", "sntrealtek"].contains(deviceType ?? ""),
                  transportRegistryID == nil, !avoidWaking else {
                throw DeviceHelperError.rejected("SNT requires explicit unmount confirmation and an external USB disk.")
            }
        } else if confirmedUnmount {
            throw DeviceHelperError.rejected("Only SNT may request USB capture.")
        }
        if avoidWaking {
            guard operation == .readSMART, let deviceType,
                  deviceType != "nvme", !deviceType.hasPrefix("snt") || deviceType.hasSuffix("/sat") else {
                throw DeviceHelperError.rejected("This transport cannot safely check disk power mode.")
            }
        }
        if operation.changesSelfTest,
           deviceType == "nvme" || deviceType == "sntasmedia" || deviceType == "sntrealtek" {
            throw DeviceHelperError.rejected("This macOS transport does not support hardware SMART self-tests.")
        }
    }

    func arguments(target: String, driveDatabase: String) throws -> [String] {
        try validate()
        if operation == .readSNT {
            return ["-i", "-H", "-A", "--json=c", "-d", deviceType!, target]
        }
        let command: [String]
        switch operation {
        case .readSMART: command = (avoidWaking ? ["-n", "standby,0"] : []) + ["-a", "--json"]
        case .selfTestCapability: command = ["-c", "--json"]
        case .selfTestLog: command = ["-l", "selftest", "--json"]
        case .errorLog: command = ["-l", "error", "--json"]
        case .startShortSelfTest: command = ["-t", "short", "--json"]
        case .startLongSelfTest: command = ["-t", "long", "--json"]
        case .abortSelfTest: command = ["-X"]
        case .readSNT: preconditionFailure("Handled above")
        }
        return ["--drivedb=\(driveDatabase)"] + command
            + (deviceType.map { ["-d", $0] } ?? []) + [target]
    }
}

struct DeviceHelperResponse: Codable, Sendable {
    let requestID: UUID
    let stdout: Data
    let stderr: Data
    let exitStatus: Int32
}

enum DeviceHelperError: Error, LocalizedError, Sendable {
    case rejected(String)
    var errorDescription: String? {
        switch self { case .rejected(let message): message }
    }
}
