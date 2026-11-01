// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import SystemConfiguration
import Darwin

/// One process-wide queue serializes all clients, including different users.
/// Disconnecting a client never terminates a worker that owns USB restoration.
final class DeviceHelperExecutor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "lex.Capricorn.DeviceHelper.operations")
    private let gate = DeviceHelperOperationGate()
    private var stagedApp: URL?
    private let appURL: URL
    private let team: String

    init(appURL: URL, team: String) {
        self.appURL = appURL
        self.team = team
    }

    func perform(data: Data, uid: uid_t, reply: @escaping (Data?, String?) -> Void) {
        guard data.count <= 16_384 else { reply(nil, "The device request is too large."); return }
        let request: DeviceHelperRequest
        do {
            request = try JSONDecoder().decode(DeviceHelperRequest.self, from: data)
            try request.validate()
        } catch { reply(nil, error.localizedDescription); return }
        switch gate.begin(id: request.id, uid: uid) {
        case .cached(let response):
            reply(try? JSONEncoder().encode(response), nil); return
        case .busy:
            reply(nil, "The device service is busy. Wait for its current operation to complete."); return
        case .accepted:
            break
        }
        queue.async { [self] in
            do {
                var consoleUID: uid_t = 0
                guard SCDynamicStoreCopyConsoleUser(nil, &consoleUID, nil) != nil,
                      uid != 0, consoleUID == uid else {
                    throw DeviceHelperError.rejected("Only the current logged-in user may request a device operation.")
                }
                let bundle = try prepareTrustedBundle()
                // Revalidate after staging, immediately before execution.
                let disk = try DeviceHelperDeviceResolver.resolve(bsdName: request.disk.bsdName)
                guard disk == request.disk else {
                    throw DeviceHelperError.rejected("The physical disk changed before the service could open it.")
                }
                let target = request.operation == .readSNT
                    ? "usbraw:\(disk.usbRegistryID!)"
                    : try DeviceHelperDeviceResolver.targetPath(transportID: request.transportRegistryID, disk: disk)
                let name = request.operation == .readSNT ? "smartctl-usbraw" : "smartctl"
                let executable = bundle.appendingPathComponent("Contents/MacOS/\(name)")
                let args = try request.arguments(
                    target: target, driveDatabase: bundle.appendingPathComponent("Contents/Resources/drivedb.h").path)
                let response = try run(executable: executable, arguments: args, request: request, uid: uid)
                // Release ownership before replying, so a following bridge
                // attempt cannot race completion of the previous request.
                gate.finish(id: request.id, uid: uid, response: response)
                reply(try JSONEncoder().encode(response), nil)
            } catch {
                gate.finish(id: request.id, uid: uid, response: nil)
                reply(nil, error.localizedDescription)
            }
        }
    }

    func result(id: String, uid: uid_t, reply: @escaping (Data?) -> Void) {
        let response = gate.result(id: id, uid: uid)
        reply(response.flatMap { try? JSONEncoder().encode($0) })
    }

    func prepareToStop() -> Bool {
        gate.prepareToStop()
    }

    func cancelStop() { gate.cancelStop() }

    private func prepareTrustedBundle() throws -> URL {
        if let stagedApp { return stagedApp }
        // Execute only a root-owned snapshot. Checking a mutable user bundle
        // then launching its path would leave a signature-check/exec race.
        var template = Array("/private/var/run/lex.Capricorn.DeviceHelper.XXXXXX".utf8CString)
        guard let directory = mkdtemp(&template) else {
            throw DeviceHelperError.rejected("Unable to stage the signed device tools.")
        }
        let parent = URL(fileURLWithPath: String(cString: directory), isDirectory: true)
        let destination = parent.appendingPathComponent("Capricorn.app", isDirectory: true)
        try FileManager.default.copyItem(at: appURL, to: destination)
        try secureSnapshot(destination)
        try DeviceHelperSigning.verify(url: destination, identifier: DeviceHelperIdentity.appIdentifier,
                                       team: team, nested: true)
        let files = ["Contents/MacOS/smartctl", "Contents/MacOS/smartctl-usbraw", "Contents/Resources/drivedb.h"]
        for path in files {
            let url = destination.appendingPathComponent(path)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == 0 else {
                throw DeviceHelperError.rejected("A staged SMART file is not a root-owned regular file.")
            }
        }
        for (name, identifier) in [("smartctl", "smartctl"), ("smartctl-usbraw", "lex.Capricorn.smartctl-usbraw")] {
            try DeviceHelperSigning.verify(url: destination.appendingPathComponent("Contents/MacOS/\(name)"),
                                           identifier: identifier, team: team)
        }
        // TCC's per-user daemon must be able to validate the containing bundle.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parent.path)
        stagedApp = destination
        return destination
    }

    private func secureSnapshot(_ app: URL) throws {
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil,
                                                              errorHandler: { _, error in
                                                                  enumerationError = error
                                                                  return false
                                                              }),
              let emptyACL = acl_init(0) else {
            throw DeviceHelperError.rejected("Unable to inspect the signed tools snapshot.")
        }
        defer { acl_free(UnsafeMutableRawPointer(emptyACL)) }
        // The mkdtemp parent stays 0700 until every descendant is root-owned.
        // Do not follow symlinks while assigning ownership or permissions.
        let entries = [app] + enumerator.compactMap { $0 as? URL }
        if let enumerationError { throw enumerationError }
        for entry in entries {
            let attributes = try FileManager.default.attributesOfItem(atPath: entry.path)
            let type = attributes[.type] as? FileAttributeType
            if type == .typeSymbolicLink {
                guard entry.resolvingSymlinksInPath().path.hasPrefix(app.path + "/") else {
                    throw DeviceHelperError.rejected("The tools snapshot contains an external symbolic link.")
                }
                guard lchown(entry.path, 0, 0) == 0 else {
                    throw DeviceHelperError.rejected("Unable to secure a snapshot symbolic link.")
                }
                continue
            }
            guard type == .typeDirectory || type == .typeRegular else {
                throw DeviceHelperError.rejected("The tools snapshot contains a non-regular file.")
            }
            let originalMode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
            let mode = type == .typeDirectory || originalMode & 0o111 != 0 ? 0o755 : 0o644
            try FileManager.default.setAttributes(
                [.ownerAccountID: 0, .groupOwnerAccountID: 0, .posixPermissions: mode], ofItemAtPath: entry.path)
            guard acl_set_file(entry.path, ACL_TYPE_EXTENDED, emptyACL) == 0 else {
                throw DeviceHelperError.rejected("Unable to remove writable snapshot ACLs.")
            }
        }
    }

    private func run(executable: URL, arguments: [String], request: DeviceHelperRequest, uid: uid_t) throws -> DeviceHelperResponse {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        // UID comes from the signed XPC peer, never from the request payload.
        process.arguments = ["asuser", String(uid), executable.path] + arguments
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8",
            "CAPRICORN_USBRAW_USER_UID": String(uid),
            "CAPRICORN_USBRAW_MANUAL": request.operation == .readSNT ? "1" : "0"
        ]
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let output = DeviceHelperOutput()
        let group = DispatchGroup()
        try process.run()
        for (handle, isError) in [(stdout.fileHandleForReading, false), (stderr.fileHandleForReading, true)] {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    output.append(chunk, isError: isError)
                }
                group.leave()
            }
        }
        // Never force-kill a capture worker: it owns disk cleanup. Ordinary
        // SMART commands use bounded termination; USB transport has its own
        // timeouts and must finish its release/restoration path.
        let timeout = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        if request.operation != .readSNT {
            DispatchQueue.global().asyncAfter(deadline: .now() + 45, execute: timeout)
        }
        process.waitUntilExit()
        timeout.cancel()
        group.wait()
        return DeviceHelperResponse(requestID: request.id, stdout: output.stdout, stderr: output.stderr,
                                    exitStatus: process.terminationStatus)
    }
}

private final class DeviceHelperOutput: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var stdout = Data()
    private(set) var stderr = Data()
    func append(_ data: Data, isError: Bool) {
        lock.lock()
        defer { lock.unlock() }
        // Continue draining even if a broken tool produces excessive output.
        let limit = 2 * 1024 * 1024
        if isError { stderr.append(data.prefix(max(0, limit - stderr.count))) }
        else { stdout.append(data.prefix(max(0, limit - stdout.count))) }
    }
}

private final class DeviceHelperPeer: NSObject, DeviceHelperXPC {
    let uid: uid_t
    let executor: DeviceHelperExecutor
    init(uid: uid_t, executor: DeviceHelperExecutor) { self.uid = uid; self.executor = executor }
    func version(reply: @escaping (Int) -> Void) { reply(DeviceHelperIdentity.protocolVersion) }
    func perform(_ request: Data, reply: @escaping (Data?, String?) -> Void) {
        executor.perform(data: request, uid: uid, reply: reply)
    }
    func result(_ requestID: String, reply: @escaping (Data?) -> Void) {
        executor.result(id: requestID, uid: uid, reply: reply)
    }
    func prepareToStop(reply: @escaping (Bool) -> Void) { reply(executor.prepareToStop()) }
    func cancelStop(reply: @escaping () -> Void) { executor.cancelStop(); reply() }
}

final class DeviceHelperListener: NSObject, NSXPCListenerDelegate {
    let executor: DeviceHelperExecutor
    let requirement: String
    init(appURL: URL, team: String) {
        executor = DeviceHelperExecutor(appURL: appURL, team: team)
        requirement = DeviceHelperSigning.requirement(identifier: DeviceHelperIdentity.appIdentifier, team: team)
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier != 0,
              connection.auditSessionIdentifier != 0,
              connection.auditSessionIdentifier != UInt32.max else { return false }
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: DeviceHelperXPC.self)
        connection.exportedObject = DeviceHelperPeer(uid: connection.effectiveUserIdentifier, executor: executor)
        connection.activate()
        return true
    }
}
