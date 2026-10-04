// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import Capricorn

final class CFastRecognitionTests: XCTestCase {
    func testMissingSolidStateMetadataProducesUnknownMediaKind() throws {
        let drive = try XCTUnwrap(DiskutilPlistParser.parseDevice(
            infoData: Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
              <key>BusProtocol</key><string>USB</string>
              <key>DeviceIdentifier</key><string>disk20</string>
              <key>MediaName</key><string>Generic USB Storage</string>
              <key>Size</key><integer>1000000000</integer>
              <key>WholeDisk</key><true/>
            </dict></plist>
            """.utf8),
            volumes: [],
            showVirtual: false
        ))

        XCTAssertFalse(drive.isSolidStateKnown)
        XCTAssertEqual(drive.mediaKind, .unknown)
    }

    func testUnknownSolidStateDoesNotRenderAsHDD() {
        var drive = makeDrive(isSolidStateKnown: false)
        drive.usbDevice = nil

        XCTAssertEqual(drive.mediaKind, .unknown)
        XCTAssertEqual(DrivePageHeaderText.mediaKind(for: drive, language: .english), "Unknown")

        let csv = ReportExporter.smartSnapshotCSVReport(
            drive: drive,
            snapshot: SmartSnapshot.unavailable(for: drive, reason: "Fixture"),
            language: .english
        )
        XCTAssertTrue(csv.contains("device_type,Device Type,Device media type,Unknown"))
    }

    func testKnownNonSolidStateStillRendersAsHDD() {
        let drive = makeDrive(isSolidStateKnown: true)

        XCTAssertEqual(drive.mediaKind, .hdd)
        XCTAssertEqual(DrivePageHeaderText.mediaKind(for: drive, language: .english), "HDD")
    }

    func testSanDiskSDCFSPModelRecognizesCFastWithoutSerialNumberOrReaderName() {
        let drive = DriveDevice(
            bsdName: "disk16",
            deviceNode: "/dev/disk16",
            displayName: "SanDisk SDCFSP-256G",
            mediaName: "SanDisk SDCFSP-256G",
            protocolName: "USB",
            sizeBytes: 256_070_647_808,
            blockSize: 512,
            isInternal: false,
            isRemovable: true,
            isSolidState: false,
            isWritable: false,
            isVirtual: false,
            isSystemDisk: false,
            smartStatusRaw: nil,
            nativeSmartKeys: [:],
            volumes: [],
            model: "SanDisk SDCFSP-256G",
            serialNumber: nil
        )

        XCTAssertTrue(drive.isCFast)
        XCTAssertEqual(DrivePageHeaderText.mediaKind(for: drive, language: .english), "CFast 2.0")
    }

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

    func testSmartctlCFastCountersUseGiBUnits() throws {
        let fixture = """
        {
          "smartctl": {"exit_status": 0},
          "smart_status": {"passed": true},
          "logical_block_size": 512,
          "ata_smart_attributes": {
            "table": [
              {"id": 241, "name": "Total_LBAs_Written", "value": 253, "worst": 253, "thresh": 0, "raw": {"value": 63876, "string": "63876"}},
              {"id": 242, "name": "Total_LBAs_Read", "value": 100, "worst": 100, "thresh": 0, "raw": {"value": 177713, "string": "177713"}}
            ]
          }
        }
        """
        var drive = DriveDevice(
            bsdName: "disk18",
            deviceNode: "/dev/disk18",
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
            vendorName: "SanDisk",
            productName: "USB3.0 CFast Reader",
            vendorID: 1921,
            productID: 51151
        )

        let snapshot = SmartctlParser.parseSnapshot(
            Data(fixture.utf8),
            drive: drive,
            providerName: "smartctl",
            exitStatus: 0
        )

        let written = try XCTUnwrap(snapshot.attributes.first(where: { $0.name == "Total_LBAs_Written" }))
        let read = try XCTUnwrap(snapshot.attributes.first(where: { $0.name == "Total_LBAs_Read" }))
        XCTAssertEqual(
            written.rawValue,
            formatSmartDataUnits(63_876, unitBytes: 1_073_741_824, unitLabel: "GiB")
        )
        XCTAssertEqual(
            read.rawValue,
            formatSmartDataUnits(177_713, unitBytes: 1_073_741_824, unitLabel: "GiB")
        )
        XCTAssertTrue(written.rawValue.contains("GiB"))
        XCTAssertFalse(written.rawValue.contains("512 B/LBA"))
    }

    private func makeDrive(isSolidStateKnown: Bool) -> DriveDevice {
        DriveDevice(
            bsdName: "disk19",
            deviceNode: "/dev/disk19",
            displayName: "Generic USB Storage",
            mediaName: "Generic USB Storage",
            protocolName: "USB",
            sizeBytes: 1_000_000_000,
            blockSize: 512,
            isInternal: false,
            isRemovable: true,
            isSolidState: false,
            isSolidStateKnown: isSolidStateKnown,
            isWritable: true,
            isVirtual: false,
            isSystemDisk: false,
            smartStatusRaw: nil,
            nativeSmartKeys: [:],
            volumes: [],
            model: "Generic USB Storage",
            serialNumber: nil
        )
    }
}
