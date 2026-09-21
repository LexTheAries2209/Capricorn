// SPDX-License-Identifier: GPL-3.0-only
import Darwin
import Foundation

enum TemporaryRunKind: String, Sendable {
    case benchmark
    case activity

    var temporaryFilePrefix: String {
        switch self {
        case .benchmark:
            "Capricorn-"
        case .activity:
            "Capricorn-Activity-"
        }
    }

    fileprivate var leaseFilePrefix: String {
        ".Capricorn-RunLease-\(rawValue)-"
    }

    func runID(fromTemporaryFileName name: String) -> String? {
        guard name.hasPrefix(temporaryFilePrefix), name.hasSuffix(".tmp") else { return nil }
        let remainder = name.dropFirst(temporaryFilePrefix.count)
        guard remainder.count > 36 else { return nil }
        let candidate = String(remainder.prefix(36))
        let separator = remainder.index(remainder.startIndex, offsetBy: 36)
        guard remainder[separator] == "-", UUID(uuidString: candidate) != nil else { return nil }
        return candidate
    }
}

final class TemporaryRunLease {
    static let staleFileAge: TimeInterval = 60 * 60

    let kind: TemporaryRunKind
    let runID: String
    let fileURL: URL

    private let fileManager: FileManager
    private var fileDescriptor: Int32
    private var isReleased = false

    init(
        kind: TemporaryRunKind,
        runID: String,
        leaseDirectoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        self.kind = kind
        self.runID = runID
        self.fileManager = fileManager

        let directory = try leaseDirectoryURL ?? Self.defaultLeaseDirectoryURL(fileManager: fileManager)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = Self.leaseFileURL(kind: kind, runID: runID, directoryURL: directory)

        let descriptor = open(fileURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let lockError = errno
            close(descriptor)
            throw POSIXError(POSIXErrorCode(rawValue: lockError) ?? .EWOULDBLOCK)
        }
        fileDescriptor = descriptor
    }

    deinit {
        release(removingLeaseFile: true)
    }

    func release(removingLeaseFile: Bool) {
        guard !isReleased else { return }
        isReleased = true
        if removingLeaseFile {
            try? fileManager.removeItem(at: fileURL)
        }
        _ = flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
        fileDescriptor = -1
    }

    static func cleanupStaleFiles(
        in targetDirectoryURL: URL,
        kind: TemporaryRunKind,
        leaseDirectoryURL: URL? = nil,
        staleFileAge: TimeInterval = staleFileAge,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) {
        guard let leaseDirectory = try? leaseDirectoryURL ?? defaultLeaseDirectoryURL(fileManager: fileManager),
              let files = try? fileManager.contentsOfDirectory(
                  at: targetDirectoryURL,
                  includingPropertiesForKeys: [.contentModificationDateKey],
                  options: [.skipsHiddenFiles]
              ) else {
            return
        }

        let cutoff = now.addingTimeInterval(-staleFileAge)
        let filesByRunID = Dictionary(grouping: files.compactMap { file -> (String, URL, Date)? in
            guard let runID = kind.runID(fromTemporaryFileName: file.lastPathComponent),
                  let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modifiedAt = values.contentModificationDate else {
                return nil
            }
            return (runID, file, modifiedAt)
        }, by: { $0.0 })

        for (runID, filesForRun) in filesByRunID {
            guard filesForRun.allSatisfy({ $0.2 <= cutoff }) else { continue }
            let leaseURL = leaseFileURL(kind: kind, runID: runID, directoryURL: leaseDirectory)
            // File age only selects candidates. The lease lock is the authority on whether a run is still active.
            guard let staleLease = acquireExisting(
                kind: kind,
                runID: runID,
                fileURL: leaseURL,
                fileManager: fileManager
            ) else {
                continue
            }
            filesForRun.forEach { try? fileManager.removeItem(at: $0.1) }
            staleLease.release(removingLeaseFile: true)
        }

        cleanupOrphanedLeaseFiles(
            kind: kind,
            leaseDirectoryURL: leaseDirectory,
            cutoff: cutoff,
            runIDsWithFiles: Set(filesByRunID.keys),
            fileManager: fileManager
        )
    }

    static func leaseFileURL(kind: TemporaryRunKind, runID: String, directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent("\(kind.leaseFilePrefix)\(runID).lock")
    }

    private init(
        kind: TemporaryRunKind,
        runID: String,
        fileURL: URL,
        fileDescriptor: Int32,
        fileManager: FileManager
    ) {
        self.kind = kind
        self.runID = runID
        self.fileURL = fileURL
        self.fileDescriptor = fileDescriptor
        self.fileManager = fileManager
    }

    private static func acquireExisting(
        kind: TemporaryRunKind,
        runID: String,
        fileURL: URL,
        fileManager: FileManager
    ) -> TemporaryRunLease? {
        let descriptor = open(fileURL.path, O_RDWR)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        return TemporaryRunLease(
            kind: kind,
            runID: runID,
            fileURL: fileURL,
            fileDescriptor: descriptor,
            fileManager: fileManager
        )
    }

    private static func cleanupOrphanedLeaseFiles(
        kind: TemporaryRunKind,
        leaseDirectoryURL: URL,
        cutoff: Date,
        runIDsWithFiles: Set<String>,
        fileManager: FileManager
    ) {
        guard let leaseFiles = try? fileManager.contentsOfDirectory(
            at: leaseDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return
        }

        for leaseFile in leaseFiles where leaseFile.lastPathComponent.hasPrefix(kind.leaseFilePrefix) {
            guard let values = try? leaseFile.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt <= cutoff,
                  let runID = runID(fromLeaseFileName: leaseFile.lastPathComponent, kind: kind),
                  // Keep the marker while any run file remains, including a file that has not aged out yet.
                  !runIDsWithFiles.contains(runID),
                  let staleLease = acquireExisting(
                      kind: kind,
                      runID: runID,
                      fileURL: leaseFile,
                      fileManager: fileManager
                  ) else {
                continue
            }
            staleLease.release(removingLeaseFile: true)
        }
    }

    private static func runID(fromLeaseFileName name: String, kind: TemporaryRunKind) -> String? {
        guard name.hasPrefix(kind.leaseFilePrefix), name.hasSuffix(".lock") else { return nil }
        let start = name.index(name.startIndex, offsetBy: kind.leaseFilePrefix.count)
        let end = name.index(name.endIndex, offsetBy: -".lock".count)
        let candidate = String(name[start..<end])
        return UUID(uuidString: candidate) == nil ? nil : candidate
    }

    private static func defaultLeaseDirectoryURL(fileManager: FileManager) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupport
            .appendingPathComponent("CapricornRuntime", isDirectory: true)
            .appendingPathComponent("TemporaryRunLeases", isDirectory: true)
    }
}
