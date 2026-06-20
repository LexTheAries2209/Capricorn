import XCTest
@testable import DiskSpeedTest

final class DITTests: XCTestCase {
    func testDiskutilParserMapsAPFSVolumesToPhysicalDisk() throws {
        let list = try DiskutilPlistParser.parseList(Self.diskutilListFixture.data(using: .utf8)!)
        XCTAssertTrue(list.wholeDiskIDs.contains("disk0"))
        XCTAssertEqual(list.volumesByPhysicalDisk["disk0"]?.first?.mountPoint, "/System/Volumes/Data")

        let drive = try XCTUnwrap(DiskutilPlistParser.parseDevice(
            infoData: Self.disk0InfoFixture.data(using: .utf8)!,
            volumes: list.volumesByPhysicalDisk["disk0"] ?? [],
            showVirtual: false
        ))

        XCTAssertEqual(drive.bsdName, "disk0")
        XCTAssertEqual(drive.displayName, "APPLE SSD AP1024Z")
        XCTAssertEqual(drive.nativeSmartKeys["PERCENTAGE_USED"], 2)
        XCTAssertEqual(drive.benchmarkMountPoint, "/System/Volumes/Data")
    }

    func testSmartctlNVMeParserExtractsHealthFields() {
        let drive = Self.fixtureDrive()
        let snapshot = SmartctlParser.parseSnapshot(Self.smartctlNVMeFixture.data(using: .utf8)!, drive: drive, providerName: "smartctl", exitStatus: 0)

        XCTAssertEqual(snapshot.health, .good)
        XCTAssertEqual(snapshot.temperatureCelsius, 35)
        XCTAssertEqual(snapshot.lifeRemainingPercent, 98)
        XCTAssertEqual(snapshot.mediaErrors, 0)
        XCTAssertTrue(snapshot.attributes.contains(where: { $0.name == "Available Spare" }))
    }

    func testSmartctlOpenErrorBecomesUnavailable() {
        let snapshot = SmartctlParser.parseSnapshot(Self.smartctlOpenErrorFixture.data(using: .utf8)!, drive: Self.fixtureDrive(), providerName: "smartctl", exitStatus: 2)

        XCTAssertEqual(snapshot.health, .unavailable)
        XCTAssertEqual(snapshot.providerStatuses.first?.state, .limited)
        XCTAssertTrue(snapshot.summary.contains("IOCreatePlugInInterfaceForService failed"))
    }

    func testSmartAttributeColumnsHideNormalizedValuesForNVMe() {
        let attributes = [
            SmartAttribute(id: "nvme.available_spare", name: "Available Spare", rawValue: "100", current: nil, worst: nil, threshold: nil, status: .good, source: "smartctl"),
            SmartAttribute(id: "nvme.percentage_used", name: "Percentage Used", rawValue: "2", current: nil, worst: nil, threshold: nil, status: .good, source: "smartctl")
        ]

        XCTAssertFalse(SmartAttributeTableColumns.showsNormalizedColumns(for: attributes))
    }

    func testSmartAttributeColumnsShowNormalizedValuesForATA() {
        let attributes = [
            SmartAttribute(id: "0x05", name: "Reallocated Sectors Count", rawValue: "4", current: 100, worst: 100, threshold: 10, status: .warning, source: "smartctl")
        ]

        XCTAssertTrue(SmartAttributeTableColumns.showsNormalizedColumns(for: attributes))
    }

    func testSmartAttributeDisplayMapsKnownFieldToChineseExplanation() {
        let attribute = SmartAttribute(id: "nvme.available_spare", name: "Available Spare", rawValue: "100", current: nil, worst: nil, threshold: nil, status: .good, source: "smartctl")

        let display = AppLanguage.simplifiedChinese.smartAttributeDisplay(attribute)

        XCTAssertEqual(display.title, "可用备用空间")
        XCTAssertTrue(display.subtitle.contains("备用块"))
        XCTAssertTrue(display.help.contains("Available Spare"))
    }

    func testSmartAttributeDisplayKeepsUnknownFieldName() {
        let attribute = SmartAttribute(id: "vendor.foo", name: "Vendor Foo", rawValue: "7", current: nil, worst: nil, threshold: nil, status: .good, source: "Fixture")

        let display = AppLanguage.simplifiedChinese.smartAttributeDisplay(attribute)

        XCTAssertEqual(display.title, "Vendor Foo")
        XCTAssertTrue(display.subtitle.contains("扩展 SMART 字段"))
    }

    func testHealthEvaluatorFlagsCriticalATAAttributes() {
        let drive = Self.fixtureDrive()
        let snapshot = SmartSnapshot(
            driveID: drive.id,
            capturedAt: Date(),
            health: .good,
            summary: "",
            providerStatuses: [ProviderStatus(name: "Fixture", state: .available, message: "OK")],
            attributes: [
                SmartAttribute(id: "0x05", name: "Reallocated Sectors Count", rawValue: "4", current: 100, worst: 100, threshold: 10, status: .warning, source: "Fixture")
            ],
            temperatureCelsius: 32,
            lifeRemainingPercent: 88,
            powerOnHours: 100,
            powerCycleCount: 2,
            mediaErrors: 0,
            unsafeShutdowns: 0,
            smartStatusRaw: "Passed",
            selfTestStatus: nil
        )

        XCTAssertEqual(DriveHealthEvaluator().evaluate(drive: drive, snapshot: snapshot), .warning)
    }

    func testExternalDetectorFindsSATDriverPath() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let driver = root.appendingPathComponent("SATSMARTDriver.kext")
        try FileManager.default.createDirectory(at: driver, withIntermediateDirectories: true)

        let status = ExternalDriveSupportDetector(driverPaths: [driver.path]).detect()
        XCTAssertTrue(status.satDriverInstalled)
        XCTAssertEqual(status.driverPaths, [driver.path])
    }

    func testBenchmarkRunnerCleansTemporaryFile() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "unit", name: "Unit", mountPoint: root.path, sizeBytes: 1_000_000, isWritable: true, isSystem: false)
        ]
        let test = BenchmarkTest(
            id: "unit-write",
            label: "RND4K Q1T1",
            accessPattern: .random,
            operation: .write,
            blockSizeBytes: 4_096,
            queueDepth: 1,
            threads: 1,
            durationSeconds: 0.05,
            testSizeBytes: 65_536,
            dataPattern: .zeroFill,
            writePercentForMixed: 100
        )
        let profile = BenchmarkProfile(id: "unit", name: "Unit", testFileSizeBytes: 65_536, runs: 1, tests: [test])

        let results = try await NativeBenchmarkRunner().run(profile: profile, drive: drive, volumePath: root.path) { _ in }
        XCTAssertEqual(results.count, 1)

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".dit-benchmark-") }
        XCTAssertTrue(leftovers.isEmpty)
    }

    private static func fixtureDrive() -> DriveDevice {
        DriveDevice(
            bsdName: "disk0",
            deviceNode: "/dev/disk0",
            displayName: "APPLE SSD AP1024Z",
            mediaName: "APPLE SSD AP1024Z",
            protocolName: "NVMe",
            sizeBytes: 1_000_555_581_440,
            blockSize: 4096,
            isInternal: true,
            isRemovable: false,
            isSolidState: true,
            isWritable: true,
            isVirtual: false,
            isSystemDisk: true,
            smartStatusRaw: "Verified",
            nativeSmartKeys: [:],
            volumes: [],
            model: "APPLE SSD AP1024Z",
            serialNumber: "SN"
        )
    }

    private static let diskutilListFixture = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>WholeDisks</key><array><string>disk0</string><string>disk3</string></array>
      <key>AllDisksAndPartitions</key><array>
        <dict>
          <key>Content</key><string>GUID_partition_scheme</string>
          <key>DeviceIdentifier</key><string>disk0</string>
          <key>Partitions</key><array>
            <dict><key>DeviceIdentifier</key><string>disk0s2</string><key>Content</key><string>Apple_APFS</string><key>Size</key><integer>994662584320</integer></dict>
          </array>
          <key>Size</key><integer>1000555581440</integer>
        </dict>
        <dict>
          <key>APFSPhysicalStores</key><array><dict><key>DeviceIdentifier</key><string>disk0s2</string></dict></array>
          <key>APFSVolumes</key><array>
            <dict><key>DeviceIdentifier</key><string>disk3s5</string><key>VolumeName</key><string>Data</string><key>MountPoint</key><string>/System/Volumes/Data</string><key>Size</key><integer>994662584320</integer><key>OSInternal</key><false/></dict>
          </array>
          <key>Content</key><string>Apple_APFS_Container</string>
          <key>DeviceIdentifier</key><string>disk3</string>
        </dict>
      </array>
    </dict></plist>
    """

    private static let disk0InfoFixture = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>BusProtocol</key><string>Apple Fabric</string>
      <key>Content</key><string>GUID_partition_scheme</string>
      <key>DeviceBlockSize</key><integer>4096</integer>
      <key>DeviceIdentifier</key><string>disk0</string>
      <key>DeviceNode</key><string>/dev/disk0</string>
      <key>IORegistryEntryName</key><string>APPLE SSD AP1024Z Media</string>
      <key>Internal</key><true/>
      <key>MediaName</key><string>APPLE SSD AP1024Z</string>
      <key>Removable</key><false/>
      <key>SMARTDeviceSpecificKeysMayVaryNotGuaranteed</key><dict>
        <key>AVAILABLE_SPARE</key><integer>100</integer>
        <key>AVAILABLE_SPARE_THRESHOLD</key><integer>99</integer>
        <key>PERCENTAGE_USED</key><integer>2</integer>
        <key>TEMPERATURE</key><integer>308</integer>
      </dict>
      <key>SMARTStatus</key><string>Verified</string>
      <key>SolidState</key><true/>
      <key>TotalSize</key><integer>1000555581440</integer>
      <key>VirtualOrPhysical</key><string>Physical</string>
      <key>WholeDisk</key><true/>
      <key>WritableMedia</key><true/>
    </dict></plist>
    """

    private static let smartctlNVMeFixture = """
    {
      "smartctl": {"exit_status": 0},
      "smart_status": {"passed": true},
      "temperature": {"current": 35},
      "power_on_time": {"hours": 1295},
      "power_cycle_count": 384,
      "nvme_smart_health_information_log": {
        "critical_warning": 0,
        "temperature": 35,
        "available_spare": 100,
        "available_spare_threshold": 99,
        "percentage_used": 2,
        "media_errors": 0,
        "num_err_log_entries": 0,
        "unsafe_shutdowns": 35,
        "data_units_read": 180246471,
        "data_units_written": 85848679
      }
    }
    """

    private static let smartctlOpenErrorFixture = """
    {
      "smartctl": {"exit_status": 2},
      "device": {"name": "IOService:/AppleANS"},
      "open_error": "IOCreatePlugInInterfaceForService failed"
    }
    """
}
