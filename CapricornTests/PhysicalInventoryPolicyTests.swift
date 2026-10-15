// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import Capricorn

final class PhysicalInventoryPolicyTests: XCTestCase {
    func testDiscoveryAlwaysExcludesLogicalDevicesAndInstallerImages() throws {
        let baseInfo: [String: Any] = [
            "DeviceIdentifier": "disk20",
            "WholeDisk": true,
            "VirtualOrPhysical": "Physical",
            "BusProtocol": "USB",
            "MediaName": "External SSD",
            "TotalSize": 1_000_000_000
        ]
        let logicalOverrides: [[String: Any]] = [
            ["WholeDisk": false, "DeviceIdentifier": "disk0s2"],
            ["Content": "Apple_APFS_Container"],
            ["Content": "Apple_CoreStorage"],
            ["VirtualOrPhysical": "Virtual"],
            ["BusProtocol": "Disk Image", "MediaName": "Installer"],
            ["MediaName": "Apple Disk Image Media"]
        ]
        for overrides in logicalOverrides {
            let info = baseInfo.merging(overrides) { _, updated in updated }
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            XCTAssertNil(try DiskutilPlistParser.parseDevice(infoData: data, volumes: []), "\(overrides)")
        }

        let data = try PropertyListSerialization.data(fromPropertyList: baseInfo, format: .xml, options: 0)
        let simulatorVolume = DriveDevice.Volume(
            deviceIdentifier: "disk20s1",
            name: "Simulator",
            mountPoint: "/Library/Developer/CoreSimulator/Volumes/Runtime",
            sizeBytes: 1_000_000,
            isWritable: false,
            isSystem: false
        )
        XCTAssertNil(try DiskutilPlistParser.parseDevice(infoData: data, volumes: [simulatorVolume]))

        let physicalDrive = try XCTUnwrap(DiskutilPlistParser.parseDevice(infoData: data, volumes: []))
        XCTAssertEqual(physicalDrive.bsdName, "disk20")
        XCTAssertFalse(physicalDrive.isVirtual)
    }

    func testSystemVolumeRemainsAttachedToPhysicalSystemDrive() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: [
            "DeviceIdentifier": "disk0",
            "WholeDisk": true,
            "VirtualOrPhysical": "Physical",
            "BusProtocol": "Apple Fabric",
            "Internal": true,
            "MediaName": "APPLE SSD",
            "TotalSize": 1_000_000_000
        ], format: .xml, options: 0)
        let volume = DriveDevice.Volume(
            deviceIdentifier: "disk3s1",
            name: "Macintosh HD",
            mountPoint: "/",
            sizeBytes: 1_000_000_000,
            isWritable: false,
            isSystem: true,
            fileSystemType: "APFS"
        )

        let drive = try XCTUnwrap(DiskutilPlistParser.parseDevice(infoData: data, volumes: [volume]))

        XCTAssertEqual(drive.bsdName, "disk0")
        XCTAssertTrue(drive.isSystemDisk)
        XCTAssertFalse(drive.isVirtual)
        XCTAssertTrue(drive.volumes.contains { $0.mountPoint == "/" })
    }
}
