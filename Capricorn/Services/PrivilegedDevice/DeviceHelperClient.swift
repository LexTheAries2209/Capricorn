// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import ServiceManagement

protocol DeviceHelperRequesting: Sendable {
    func perform(_ request: DeviceHelperRequest) async throws -> DeviceHelperResponse
}

struct DeviceHelperClient: DeviceHelperRequesting {
    static let unavailableMessage = "Enable the privileged device service in Settings before running this operation."
    let bundle: Bundle

    init(bundle: Bundle = .main) { self.bundle = bundle }

    static func checkConnection() async throws {
        _ = try await connect(request: nil, bundle: .main)
    }

    static func prepareToStop() async throws {
        try await stopControl(cancel: false)
    }

    static func cancelStop() async throws {
        try await stopControl(cancel: true)
    }

    private static func stopControl(cancel: Bool) async throws {
        let requirement = DeviceHelperSigning.requirement(
            identifier: DeviceHelperIdentity.service, team: try DeviceHelperSigning.ownTeam())
        let _: DeviceHelperResponse = try await withCheckedThrowingContinuation { continuation in
            let call = DeviceHelperCall(continuation)
            let connection = NSXPCConnection(machServiceName: DeviceHelperIdentity.service, options: .privileged)
            call.connection = connection
            connection.remoteObjectInterface = NSXPCInterface(with: DeviceHelperXPC.self)
            connection.setCodeSigningRequirement(requirement)
            connection.invalidationHandler = {
                call.finish(.failure(DeviceHelperError.rejected("The device service is unavailable; it was not unregistered.")))
            }
            call.startHandshakeTimeout()
            connection.activate()
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({
                call.finish(.failure($0))
            }) as? DeviceHelperXPC else {
                call.finish(.failure(DeviceHelperError.rejected("Unable to connect to the device service.")))
                return
            }
            if cancel {
                proxy.cancelStop {
                    call.finish(.success(DeviceHelperResponse(requestID: UUID(), stdout: Data(), stderr: Data(), exitStatus: 0)))
                }
                return
            }
            proxy.prepareToStop { allowed in
                if allowed {
                    call.finish(.success(DeviceHelperResponse(requestID: UUID(), stdout: Data(), stderr: Data(), exitStatus: 0)))
                } else {
                    call.finish(.failure(DeviceHelperError.rejected(
                        "The device service is busy. Wait for its current operation to complete.")))
                }
            }
        }
    }

    func perform(_ request: DeviceHelperRequest) async throws -> DeviceHelperResponse {
        try request.validate()
        return try await Self.connect(request: request, bundle: bundle)
    }

    private static func connect(request: DeviceHelperRequest?, bundle: Bundle) async throws -> DeviceHelperResponse {
        guard SMAppService.daemon(plistName: DeviceHelperIdentity.plistName).status == .enabled else {
            throw DeviceHelperError.rejected(Self.unavailableMessage)
        }
        let requirement = DeviceHelperSigning.requirement(
            identifier: DeviceHelperIdentity.service, team: try DeviceHelperSigning.ownTeam())
        let expectedInstallation = try DeviceHelperSigning.codeIdentity(bundle.bundleURL)
        let data = try request.map { try JSONEncoder().encode($0) }
        return try await withCheckedThrowingContinuation { continuation in
            let call = DeviceHelperCall(continuation)
            let connection = NSXPCConnection(machServiceName: DeviceHelperIdentity.service, options: .privileged)
            call.connection = connection
            connection.remoteObjectInterface = NSXPCInterface(with: DeviceHelperXPC.self)
            connection.setCodeSigningRequirement(requirement)
            connection.invalidationHandler = {
                call.finish(.failure(DeviceHelperError.rejected(
                    "The device service connection ended. A USB worker may still be restoring mounts; do not disconnect the disk.")))
            }
            connection.interruptionHandler = {
                call.finish(.failure(DeviceHelperError.rejected(
                    "The device service was interrupted. Check the disk's mount state before another operation.")))
            }
            call.startHandshakeTimeout()
            connection.activate()
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({
                call.finish(.failure($0))
            }) as? DeviceHelperXPC else {
                call.finish(.failure(DeviceHelperError.rejected("Unable to connect to the device service.")))
                return
            }
            proxy.version { version in
                guard version == DeviceHelperIdentity.protocolVersion else {
                    call.finish(.failure(DeviceHelperError.rejected("The device helper version does not match this application.")))
                    return
                }
                proxy.installation { installation in
                    guard installation == expectedInstallation else {
                        call.finish(.failure(DeviceHelperError.rejected(
                            "The device service belongs to a different application build. Re-enable it in Settings.")))
                        return
                    }
                    guard call.completeHandshake() else { return }
                    guard let data, let request else {
                        call.finish(.success(DeviceHelperResponse(requestID: UUID(), stdout: Data(), stderr: Data(), exitStatus: 0)))
                        return
                    }
                    proxy.perform(data) { data, message in
                        do {
                            if let message { throw DeviceHelperError.rejected(message) }
                            guard let data, data.count <= 6 * 1024 * 1024 else {
                                throw DeviceHelperError.rejected("The device service returned an invalid response.")
                            }
                            let response = try JSONDecoder().decode(DeviceHelperResponse.self, from: data)
                            guard response.requestID == request.id else {
                                throw DeviceHelperError.rejected("The device service response does not match the request.")
                            }
                            call.finish(.success(response))
                        } catch { call.finish(.failure(error)) }
                    }
                }
            }
        }
    }
}

private final class DeviceHelperCall: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<DeviceHelperResponse, Error>?
    private var handshakeTimeout: DispatchWorkItem?
    var connection: NSXPCConnection?
    init(_ continuation: CheckedContinuation<DeviceHelperResponse, Error>) { self.continuation = continuation }
    func startHandshakeTimeout() {
        let timeout = DispatchWorkItem { [weak self] in
            self?.finish(.failure(DeviceHelperError.rejected("The device service did not respond. Check its status in Settings.")))
        }
        lock.lock()
        handshakeTimeout = timeout
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: timeout)
    }
    func completeHandshake() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        handshakeTimeout?.cancel()
        handshakeTimeout = nil
        return continuation != nil
    }
    func finish(_ result: Result<DeviceHelperResponse, Error>) {
        lock.lock()
        handshakeTimeout?.cancel()
        handshakeTimeout = nil
        let completion = continuation
        continuation = nil
        let connection = self.connection
        self.connection = nil
        lock.unlock()
        guard let completion else { return }
        connection?.invalidationHandler = nil
        connection?.interruptionHandler = nil
        connection?.invalidate()
        completion.resume(with: result)
    }
}

/// Adapts existing SMART services to typed requests, without forwarding their
/// executable paths, database paths, environments or command strings over XPC.
struct PrivilegedDeviceCommandRunner: CommandRunning {
    let client: any DeviceHelperRequesting
    let bundle: Bundle
    let resolve: @Sendable (String) throws -> DeviceHelperDisk

    init(
        client: any DeviceHelperRequesting = DeviceHelperClient(),
        bundle: Bundle = .main,
        resolve: @escaping @Sendable (String) throws -> DeviceHelperDisk = DeviceHelperDeviceResolver.disk(forTarget:)
    ) {
        self.client = client
        self.bundle = bundle
        self.resolve = resolve
    }

    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        let request = try Self.request(executable: executable, arguments: arguments, bundle: bundle, resolve: resolve)
        let response = try await client.perform(request)
        return CommandResult(stdout: response.stdout, stderr: response.stderr, terminationStatus: response.exitStatus)
    }

    static func request(
        executable: String, arguments: [String], bundle: Bundle,
        resolve: (String) throws -> DeviceHelperDisk,
        resolveTransport: (String, DeviceHelperDisk) throws -> UInt64? = DeviceHelperDeviceResolver.transportID(path:disk:)
    ) throws -> DeviceHelperRequest {
        let raw = bundle.executableURL?.deletingLastPathComponent().appendingPathComponent("smartctl-usbraw").path
        let normal = bundle.url(forResource: "smartctl", withExtension: nil)?.path
        var args = arguments
        let isSNT = executable == "/usr/bin/env"
        if isSNT {
            guard args.count >= 2, args[0] == "CAPRICORN_USBRAW_MANUAL=1", args[1] == raw else {
                throw DeviceHelperError.rejected("Only the bundled SNT tool may request USB capture.")
            }
            args.removeFirst(2)
        } else {
            guard executable == normal else {
                throw DeviceHelperError.rejected("Only the bundled SMART tool may use the device service.")
            }
            if args.first?.hasPrefix("--drivedb=") == true { args.removeFirst() }
        }
        guard let target = args.popLast(), !target.hasPrefix("-") else {
            throw DeviceHelperError.rejected("The device request has no physical disk target.")
        }
        var type: String?
        if args.count >= 2, args[args.count - 2] == "-d" {
            type = args.removeLast()
            args.removeLast()
        }
        let operation: DeviceHelperOperation
        var avoidWaking = false
        if isSNT, args == ["-i", "-H", "-A", "--json=c"], target.hasPrefix("usbraw:") {
            operation = .readSNT
        } else if !isSNT {
            switch args {
            case ["-a", "--json"]: operation = .readSMART
            case ["-n", "standby,0", "-a", "--json"]: operation = .readSMART; avoidWaking = true
            case ["-c", "--json"]: operation = .selfTestCapability
            case ["-l", "selftest", "--json"]: operation = .selfTestLog
            case ["-l", "error", "--json"]: operation = .errorLog
            case ["-t", "short", "--json"]: operation = .startShortSelfTest
            case ["-t", "long", "--json"]: operation = .startLongSelfTest
            case ["-X"]: operation = .abortSelfTest
            default: throw DeviceHelperError.rejected("This command is not allowed by the device service.")
            }
        } else { throw DeviceHelperError.rejected("This USB capture command is not allowed.") }
        let disk = try resolve(target)
        var request = DeviceHelperRequest(operation: operation, disk: disk, deviceType: type)
        if !isSNT { request.transportRegistryID = try resolveTransport(target, disk) }
        request.avoidWaking = avoidWaking
        request.confirmedUnmount = isSNT
        try request.validate()
        return request
    }
}
