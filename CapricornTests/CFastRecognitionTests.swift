// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import Capricorn

final class CFastRecognitionTests: XCTestCase {
    func testUSBReaderIdentityRecognizesCFastMedia() {
        var drive = DriveDevice(
            bsdName: "disk11",
            deviceNode: "/dev/disk11",
            displayName: "SanDisk SDCFSP-256G",
            mediaName: "SanDisk SDCFSP-256G",
            protocolName: "USB",
            sizeBytes: 256_070_647_808,
            blockSize: 512,
            isInternal: false,
            isRemovable: true,
            isSolidState: false,
            isWritable: true,
            isVirtual: false,
            isSystemDisk: false,
            smartStatusRaw: nil,
            nativeSmartKeys: [:],
            volumes: [],
            model: "SanDisk SanDisk SDCFSP-256G Media",
            serialNumber: "181103300044"
        )
        drive.usbDevice = DriveUSBDeviceIdentity(
            vendorName: "JMicron",
            productName: "FB-CFast2",
            vendorID: 5421,
            productID: 1412
        )

        XCTAssertTrue(drive.isCFast)
        XCTAssertEqual(DrivePageHeaderText.mediaKind(for: drive, language: .english), "CFast 2.0")
    }

    func testSmartSnapshotCSVUsesCFastMediaTypeInsteadOfHDD() {
        var drive = DriveDevice(
            bsdName: "disk11",
            deviceNode: "/dev/disk11",
            displayName: "SanDisk SDCFSP-256G",
            mediaName: "SanDisk SDCFSP-256G",
            protocolName: "USB",
            sizeBytes: 256_070_647_808,
            blockSize: 512,
            isInternal: false,
            isRemovable: true,
            isSolidState: false,
            isWritable: true,
            isVirtual: false,
            isSystemDisk: false,
            smartStatusRaw: nil,
            nativeSmartKeys: [:],
            volumes: [],
            model: "SanDisk SanDisk SDCFSP-256G Media",
            serialNumber: "181103300044"
        )
        drive.usbDevice = DriveUSBDeviceIdentity(
            vendorName: "JMicron",
            productName: "FB-CFast2",
            vendorID: 5421,
            productID: 1412
        )

        let snapshot = SmartSnapshot.unavailable(for: drive, reason: "Fixture")
        let csv = ReportExporter.smartSnapshotCSVReport(
            drive: drive,
            snapshot: snapshot,
            language: .english
        )

        XCTAssertTrue(csv.contains("device_type,Device Type,Device media type,CFast 2.0"))
        XCTAssertFalse(csv.contains("device_type,Device Type,Device media type,HDD"))
    }
}
