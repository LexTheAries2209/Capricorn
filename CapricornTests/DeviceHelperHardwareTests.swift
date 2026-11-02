// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import IOKit
import IOKit.storage
import XCTest
@testable import Capricorn

/// Explicit opt-in only. This suite never starts self-tests or captures USB.
final class DeviceHelperHardwareTests: XCTestCase {
    func testUSBIdentityRoundTripsThroughNestedHubs() throws {
        guard let name = ProcessInfo.processInfo.environment["CAPRICORN_HELPER_TEST_USB_DISK"] else {
            throw XCTSkip("Set CAPRICORN_HELPER_TEST_USB_DISK for a read-only USB identity check through nested hubs.")
        }
        let disk = try DeviceHelperDeviceResolver.resolve(bsdName: name)
        XCTAssertFalse(disk.isInternal)
        var entry = IOServiceGetMatchingService(
            kIOMainPortDefault, IORegistryEntryIDMatching(disk.mediaRegistryID))
        var usbAncestors: [UInt64] = []
        var storageTarget: String?
        while entry != 0 {
            if storageTarget == nil, IOObjectConformsTo(entry, "IOBlockStorageDevice") != 0 {
                var path = [CChar](repeating: 0, count: 4096)
                if IORegistryEntryGetPath(entry, kIOServicePlane, &path) == KERN_SUCCESS {
                    storageTarget = String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                }
            }
            if IOObjectConformsTo(entry, "IOUSBHostDevice") != 0 {
                var identifier: UInt64 = 0
                let status = IORegistryEntryGetRegistryEntryID(entry, &identifier)
                XCTAssertEqual(status, KERN_SUCCESS)
                if status == KERN_SUCCESS { usbAncestors.append(identifier) }
            }
            var parent: io_registry_entry_t = 0
            let status = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent)
            IOObjectRelease(entry)
            entry = status == KERN_SUCCESS ? parent : 0
        }
        XCTAssertGreaterThan(usbAncestors.count, 1, "Connect the selected USB disk through a hub.")
        let nearestUSB = try XCTUnwrap(usbAncestors.first)
        var drive = USBRawSmartTests.drive()
        drive.bsdName = disk.bsdName
        drive.sizeBytes = disk.sizeBytes
        let target = try USBRawSmartTargetResolver().target(for: drive)
        XCTAssertEqual(target.registryID, nearestUSB)
        XCTAssertEqual(disk.usbRegistryID, nearestUSB)
        XCTAssertEqual(try DeviceHelperDeviceResolver.disk(forTarget: target.selector), disk)
        XCTAssertEqual(try DeviceHelperDeviceResolver.disk(forTarget: XCTUnwrap(storageTarget)), disk)
        for hub in usbAncestors.dropFirst() {
            XCTAssertThrowsError(try DeviceHelperDeviceResolver.disk(forTarget: "usbraw:\(hub)"),
                                 "An upstream hub must not identify a physical disk.")
        }
        let media = IOServiceGetMatchingService(
            kIOMainPortDefault, IORegistryEntryIDMatching(disk.mediaRegistryID))
        XCTAssertNotEqual(media, 0)
        defer { if media != 0 { IOObjectRelease(media) } }
        var descendants: io_iterator_t = 0
        XCTAssertEqual(IORegistryEntryCreateIterator(
            media, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &descendants), KERN_SUCCESS)
        defer { if descendants != 0 { IOObjectRelease(descendants) } }
        var synthesized: [String] = []
        while case let child = IOIteratorNext(descendants), child != 0 {
            defer { IOObjectRelease(child) }
            guard IOObjectConformsTo(child, kIOMediaClass) != 0,
                  IORegistryEntryCreateCFProperty(
                    child, kIOMediaWholeKey as CFString, kCFAllocatorDefault, 0
                  )?.takeRetainedValue() as? Bool == true,
                  let bsd = IORegistryEntryCreateCFProperty(
                    child, kIOBSDNameKey as CFString, kCFAllocatorDefault, 0
                  )?.takeRetainedValue() as? String, bsd != name else { continue }
            synthesized.append(bsd)
            XCTAssertThrowsError(try DeviceHelperDeviceResolver.resolve(bsdName: bsd),
                                 "A synthesized whole disk must not duplicate its physical backing disk.")
        }
        print("DEVICE_HELPER_USB_IDENTITY disk=\(name) device=\(nearestUSB) upstream_hubs=\(usbAncestors.dropFirst())")
        print("DEVICE_HELPER_MEDIA_IDENTITY physical=\(name) excluded_synthesized=\(synthesized)")
    }

    func testApprovedServiceReadsExternalDiskAndRejectsStaleIdentity() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let name = environment["CAPRICORN_HELPER_TEST_DISK"],
              let type = environment["CAPRICORN_HELPER_TEST_TYPE"] else {
            throw XCTSkip("Set CAPRICORN_HELPER_TEST_DISK and CAPRICORN_HELPER_TEST_TYPE for an approved, external read-only hardware test.")
        }
        let disk = try DeviceHelperDeviceResolver.resolve(bsdName: name)
        guard !disk.isInternal else { throw DeviceHelperError.rejected("Hardware tests require an external physical disk.") }
        let request = DeviceHelperRequest(operation: .readSMART, disk: disk, deviceType: type)
        try request.validate()
        let expectedBundle: Bundle
        if let path = environment["CAPRICORN_HELPER_TEST_BUNDLE"] {
            expectedBundle = try XCTUnwrap(Bundle(url: URL(fileURLWithPath: path)))
            XCTAssertEqual(expectedBundle.bundleIdentifier, DeviceHelperIdentity.appIdentifier)
        } else { expectedBundle = .main }
        let response = try await DeviceHelperClient(bundle: expectedBundle).perform(request)
        XCTAssertEqual(response.exitStatus & 0x07, 0, String(decoding: response.stderr, as: UTF8.self))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: response.stdout) as? [String: Any])
        XCTAssertNotNil(json["smart_status"])
        XCTAssertNotNil(json["model_name"])
        let smartctl = try XCTUnwrap(json["smartctl"] as? [String: Any])
        let argv = try XCTUnwrap(smartctl["argv"] as? [String])
        XCTAssertTrue(argv.contains { $0.hasPrefix("--drivedb=/private/var/run/lex.Capricorn.DeviceHelper.") })
        let database = try XCTUnwrap(argv.first { $0.hasPrefix("--drivedb=") })
        let databaseURL = URL(fileURLWithPath: String(database.dropFirst("--drivedb=".count)))
        let stagedBundle = databaseURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try DeviceHelperSigning.verify(url: stagedBundle, identifier: DeviceHelperIdentity.appIdentifier,
                                       team: try DeviceHelperSigning.ownTeam(), nested: true)
        for url in [stagedBundle, databaseURL, stagedBundle.appendingPathComponent("Contents/MacOS/smartctl")] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            XCTAssertEqual((attributes[.ownerAccountID] as? NSNumber)?.uint32Value, 0)
            XCTAssertEqual(((attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1) & 0o022, 0)
        }
        print("DEVICE_HELPER_HARDWARE readSMART exit=\(response.exitStatus) model=\(json["model_name"] ?? "")")
        print("DEVICE_HELPER_HARDWARE signed root-owned snapshot verified: \(stagedBundle.path)")
        let health = json["nvme_smart_health_information_log"] as? [String: Any]
        print("DEVICE_HELPER_HARDWARE temperature=\(health?["temperature"] ?? "") used_percent=\(health?["percentage_used"] ?? "") media_errors=\(health?["media_errors"] ?? "")")

        let replay = try await send(request)
        XCTAssertEqual(replay.requestID, response.requestID)
        XCTAssertEqual(replay.stdout, response.stdout, "Replaying a completed request must return its cached result.")
        print("DEVICE_HELPER_HARDWARE cached replay matched")

        for operation in [DeviceHelperOperation.selfTestCapability, .selfTestLog, .errorLog] {
            let response = try await send(DeviceHelperRequest(operation: operation, disk: disk, deviceType: type))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: response.stdout) as? [String: Any])
            XCTAssertNotNil(json["smartctl"])
            XCTAssertEqual(response.exitStatus & 0x07, 0, String(decoding: response.stderr, as: UTF8.self))
            print("DEVICE_HELPER_HARDWARE \(operation.rawValue) exit=\(response.exitStatus)")
        }
        let staleDisk = DeviceHelperDisk(
            bsdName: disk.bsdName, mediaRegistryID: disk.mediaRegistryID + 1, sizeBytes: disk.sizeBytes,
            usbRegistryID: disk.usbRegistryID, isInternal: disk.isInternal)
        do {
            _ = try await send(DeviceHelperRequest(operation: .readSMART, disk: staleDisk, deviceType: type))
            XCTFail("The helper accepted a changed physical disk identity.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("physical disk changed"), error.localizedDescription)
            print("DEVICE_HELPER_HARDWARE stale identity rejected")
        }
        XCTAssertEqual(try DeviceHelperDeviceResolver.resolve(bsdName: name), disk)
    }

    private func send(_ request: DeviceHelperRequest) async throws -> DeviceHelperResponse {
        let requirement = DeviceHelperSigning.requirement(
            identifier: DeviceHelperIdentity.service, team: try DeviceHelperSigning.ownTeam())
        let data = try JSONEncoder().encode(request)
        return try await withCheckedThrowingContinuation { continuation in
            let call = HardwareHelperCall(continuation)
            let connection = NSXPCConnection(machServiceName: DeviceHelperIdentity.service, options: .privileged)
            call.connection = connection
            connection.remoteObjectInterface = NSXPCInterface(with: DeviceHelperXPC.self)
            connection.setCodeSigningRequirement(requirement)
            connection.invalidationHandler = {
                call.finish(.failure(DeviceHelperError.rejected("Hardware test XPC connection was invalidated.")))
            }
            connection.interruptionHandler = {
                call.finish(.failure(DeviceHelperError.rejected("Hardware test XPC connection was interrupted.")))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 60) {
                call.finish(.failure(DeviceHelperError.rejected("Hardware test XPC request timed out.")))
            }
            connection.activate()
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({
                call.finish(.failure($0))
            }) as? DeviceHelperXPC else {
                call.finish(.failure(DeviceHelperError.rejected("No hardware test XPC proxy.")))
                return
            }
            proxy.version { version in
                guard version == DeviceHelperIdentity.protocolVersion else {
                    call.finish(.failure(DeviceHelperError.rejected("Hardware test protocol mismatch.")))
                    return
                }
                proxy.perform(data) { bytes, error in
                    do {
                        if let error { throw DeviceHelperError.rejected(error) }
                        guard let bytes, bytes.count < 6 * 1024 * 1024 else {
                            throw DeviceHelperError.rejected("Invalid hardware response.")
                        }
                        let response = try JSONDecoder().decode(DeviceHelperResponse.self, from: bytes)
                        guard response.requestID == request.id else {
                            throw DeviceHelperError.rejected("Hardware response identity mismatch.")
                        }
                        call.finish(.success(response))
                    } catch { call.finish(.failure(error)) }
                }
            }
        }
    }
}

private final class HardwareHelperCall: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<DeviceHelperResponse, Error>?
    var connection: NSXPCConnection?
    init(_ continuation: CheckedContinuation<DeviceHelperResponse, Error>) { self.continuation = continuation }
    func finish(_ result: Result<DeviceHelperResponse, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let connection = self.connection
        self.connection = nil
        lock.unlock()
        guard let continuation else { return }
        connection?.invalidationHandler = nil
        connection?.interruptionHandler = nil
        connection?.invalidate()
        continuation.resume(with: result)
    }
}
