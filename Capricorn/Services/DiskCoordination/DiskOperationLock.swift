// SPDX-License-Identifier: GPL-3.0-only
import Darwin
import Foundation

enum DiskOperationKind: String, Codable, Sendable {
    case benchmark
    case activityWorkload
    case detailedCheck
    case firstAid
    case mount
    case unmount
    case forceUnmount
    case eject
    case rename
    case disconnect

    var title: String {
        switch self {
        case .benchmark: "Benchmark"
        case .activityWorkload: "Live Activity Workload"
        case .detailedCheck: "System Check"
        case .firstAid: "First Aid"
        case .mount: "Mount"
        case .unmount: "Unmount"
        case .forceUnmount: "Force Unmount"
        case .eject: "Eject"
        case .rename: "Rename Volume"
        case .disconnect: "Disconnect"
        }
    }
}

struct DiskOperationLockOwner: Codable, Equatable, Sendable {
    var operation: DiskOperationKind
    var driveName: String
    var diskIdentifier: String
    var processIdentifier: Int32
    var executableName: String
    var startedAt: Date
}

struct DiskOperationLockConflict: Error, Equatable, Sendable {
    var requestedOperation: DiskOperationKind
    var driveName: String
    var diskIdentifier: String
    var owner: DiskOperationLockOwner?
}

enum DiskOperationLockError: Error, LocalizedError {
    case conflict(DiskOperationLockConflict)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case let .conflict(conflict):
            if let owner = conflict.owner {
                return "\(conflict.driveName) is already being used by Capricorn for \(owner.operation.title)."
            }
            return "\(conflict.driveName) is already being used by another Capricorn operation."
        case let .unavailable(message):
            return message
        }
    }
}

protocol DiskOperationLocking: Sendable {
    func acquire(for drive: DriveDevice, operation: DiskOperationKind) throws -> DiskOperationLease
}

final class DiskOperationLease: @unchecked Sendable {
    let owner: DiskOperationLockOwner
    let fileURL: URL

    private let stateLock = NSLock()
    private var fileDescriptor: Int32
    private var isReleased = false

    fileprivate init(owner: DiskOperationLockOwner, fileURL: URL, fileDescriptor: Int32) {
        self.owner = owner
        self.fileURL = fileURL
        self.fileDescriptor = fileDescriptor
    }

    deinit {
        release()
    }

    func release() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !isReleased else { return }
        isReleased = true
        _ = flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
        fileDescriptor = -1
    }
}

final class DiskOperationLockCoordinator: DiskOperationLocking, @unchecked Sendable {
    private let fileManager: FileManager
    private let lockDirectoryURL: URL?

    init(
        lockDirectoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.lockDirectoryURL = lockDirectoryURL
        self.fileManager = fileManager
    }

    func acquire(for drive: DriveDevice, operation: DiskOperationKind) throws -> DiskOperationLease {
        let directory = try lockDirectoryURL ?? Self.defaultLockDirectoryURL(fileManager: fileManager)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let diskIdentifier = Self.lockIdentifier(for: drive)
        let fileURL = directory.appendingPathComponent("disk-\(diskIdentifier).lock")
        let descriptor = open(fileURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw Self.posixError(message: "Could not open the Capricorn disk-operation lock.")
        }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let lockError = errno
            let owner = Self.readOwner(from: fileURL)
            close(descriptor)
            if lockError == EWOULDBLOCK || lockError == EAGAIN {
                throw DiskOperationLockError.conflict(DiskOperationLockConflict(
                    requestedOperation: operation,
                    driveName: drive.displayName,
                    diskIdentifier: diskIdentifier,
                    owner: owner
                ))
            }
            errno = lockError
            throw Self.posixError(message: "Could not acquire the Capricorn disk-operation lock.")
        }

        let owner = DiskOperationLockOwner(
            operation: operation,
            driveName: drive.displayName,
            diskIdentifier: diskIdentifier,
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            executableName: Bundle.main.executableURL?.lastPathComponent ?? "Capricorn",
            startedAt: Date()
        )

        do {
            try Self.writeOwner(owner, to: descriptor)
        } catch {
            _ = flock(descriptor, LOCK_UN)
            close(descriptor)
            throw error
        }

        return DiskOperationLease(owner: owner, fileURL: fileURL, fileDescriptor: descriptor)
    }

    static func lockIdentifier(for drive: DriveDevice) -> String {
        let rawIdentifier = drive.bsdName.isEmpty
            ? URL(fileURLWithPath: drive.deviceNode).lastPathComponent
            : URL(fileURLWithPath: drive.bsdName).lastPathComponent
        let normalized = wholeDiskIdentifier(from: rawIdentifier)
        let safe = normalized.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_"
                ? Character(String(scalar))
                : "_"
        }
        return String(safe).isEmpty ? "unknown" : String(safe)
    }

    private static func wholeDiskIdentifier(from identifier: String) -> String {
        var value = identifier
        if value.hasPrefix("rdisk") {
            value.removeFirst()
        }
        guard value.hasPrefix("disk") else { return value }

        var index = value.index(value.startIndex, offsetBy: 4)
        while index < value.endIndex, value[index].isNumber {
            index = value.index(after: index)
        }
        guard index < value.endIndex, value[index] == "s" else { return value }
        let partitionStart = value.index(after: index)
        guard partitionStart < value.endIndex,
              value[partitionStart...].allSatisfy(\.isNumber) else {
            return value
        }
        return String(value[..<index])
    }

    private static func writeOwner(_ owner: DiskOperationLockOwner, to descriptor: Int32) throws {
        let data = try JSONEncoder().encode(owner)
        guard ftruncate(descriptor, 0) == 0, lseek(descriptor, 0, SEEK_SET) >= 0 else {
            throw posixError(message: "Could not prepare the Capricorn disk-operation lock.")
        }

        let writtenSuccessfully = data.withUnsafeBytes { bytes -> Bool in
            guard let baseAddress = bytes.baseAddress else { return data.isEmpty }
            var totalWritten = 0
            while totalWritten < bytes.count {
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: totalWritten),
                    bytes.count - totalWritten
                )
                guard written > 0 else { return false }
                totalWritten += written
            }
            return true
        }
        guard writtenSuccessfully else {
            throw posixError(message: "Could not write the Capricorn disk-operation lock.")
        }
    }

    private static func readOwner(from fileURL: URL) -> DiskOperationLockOwner? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(DiskOperationLockOwner.self, from: data)
    }

    private static func defaultLockDirectoryURL(fileManager: FileManager) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        // Deliberately independent of the bundle identifier so Debug and Release coordinate.
        return applicationSupport
            .appendingPathComponent("CapricornRuntime", isDirectory: true)
            .appendingPathComponent("DiskOperationLocks", isDirectory: true)
    }

    private static func posixError(message: String) -> DiskOperationLockError {
        let detail = String(cString: strerror(errno))
        return .unavailable("\(message) \(detail)")
    }
}
