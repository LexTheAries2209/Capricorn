// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import SwiftData
import SwiftUI
@testable import Capricorn

final class CapricornTests: XCTestCase {
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
        XCTAssertEqual(drive.volumes.first?.fileSystemType, "APFS")
        XCTAssertEqual(drive.volumes.first?.capacityGroupIdentifier, "apfs:disk3")
        XCTAssertEqual(drive.fileSystemSummary, "APFS")
    }

    func testSystemProfilerDriveSerialParserMapsPhysicalBSDNames() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><array>
          <dict>
            <key>_dataType</key><string>SPNVMeDataType</string>
            <key>_items</key><array>
              <dict><key>_items</key><array>
                <dict>
                  <key>_name</key><string>APPLE SSD AP1024Z</string>
                  <key>bsd_name</key><string>disk0</string>
                  <key>device_serial</key><string> 0ba01ee32464d219 </string>
                  <key>volumes</key><array>
                    <dict><key>bsd_name</key><string>disk0s1</string></dict>
                  </array>
                </dict>
                <dict>
                  <key>_name</key><string>Lexar SSD ARES 4TB</string>
                  <key>bsd_name</key><string>disk10</string>
                  <key>device_serial</key><string>NL86722004672P2202</string>
                </dict>
                <dict>
                  <key>bsd_name</key><string>disk11</string>
                  <key>device_serial</key><string>Unknown</string>
                </dict>
              </array></dict>
            </array>
          </dict>
        </array></plist>
        """

        XCTAssertEqual(
            SystemProfilerDriveSerialParser.parse(Data(xml.utf8)),
            [
                "disk0": "0ba01ee32464d219",
                "disk10": "NL86722004672P2202"
            ]
        )
    }

    func testBundledExternalDriveModelCatalogMatchesEveryDocumentedExample() throws {
        let catalog = ExternalDriveModelCatalog.bundled

        XCTAssertGreaterThanOrEqual(catalog.records.count, 40)
        XCTAssertTrue(catalog.records.contains(where: { $0.mediaKind == "HDD" }))
        XCTAssertTrue(catalog.records.contains(where: { $0.mediaKind == "SSD" }))

        for record in catalog.records {
            XCTAssertTrue(record.sourceURL.hasPrefix("https://"), record.id)
            XCTAssertFalse(record.examples.isEmpty, record.id)
            for example in record.examples {
                let drive = Self.externalCatalogDrive(model: example.reportedModel)
                let match = try XCTUnwrap(catalog.match(for: drive), record.id)
                XCTAssertEqual(match.recordID, record.id, example.reportedModel)
                XCTAssertEqual(match.canonicalModel, example.canonicalModel, example.reportedModel)
                XCTAssertEqual(
                    match.marketingName,
                    record.marketingName(capacityToken: example.capacityToken),
                    example.reportedModel
                )
            }
        }
    }

    func testExternalDriveModelCatalogFormatsKnownHDDModels() throws {
        let catalog = ExternalDriveModelCatalog.bundled
        let seagate = try XCTUnwrap(catalog.match(for: Self.externalCatalogDrive(model: "ST8000NM000A-2KE101")))
        let westernDigital = try XCTUnwrap(catalog.match(for: Self.externalCatalogDrive(model: "WUH722016CLE604")))

        XCTAssertEqual(seagate.displayName, "ST8000NM000A · Seagate Exos 7E8 8TB")
        XCTAssertEqual(seagate.reportedModel, "ST8000NM000A-2KE101")
        XCTAssertEqual(westernDigital.displayName, "WUH722016CLE604 · Western Digital Ultrastar DC HC555 16TB")
    }

    func testExternalDriveCatalogHelpRetainsLocalizedRawModel() {
        let drive = Self.externalCatalogDrive(model: "ST8000NM000A-2KE101")

        XCTAssertEqual(
            drive.catalogDisplayHelp(language: .english),
            "ST8000NM000A · Seagate Exos 7E8 8TB\nOriginal model: ST8000NM000A-2KE101"
        )
        XCTAssertEqual(
            drive.catalogDisplayHelp(language: .simplifiedChinese),
            "ST8000NM000A · Seagate Exos 7E8 8TB\n原始型号: ST8000NM000A-2KE101"
        )
    }

    func testExternalDriveCatalogProvidesStructuredSidebarAndGroupedHeaderNames() throws {
        let drive = Self.externalCatalogDrive(model: "WUH722016CLE604")
        let match = try XCTUnwrap(drive.catalogMatch)

        XCTAssertEqual(match.marketingName, "Western Digital Ultrastar DC HC555 16TB")
        XCTAssertEqual(match.canonicalModel, "WUH722016CLE604")
        XCTAssertEqual(
            drive.catalogHeaderDisplayName,
            "WUH722016CLE604 · Western\u{00A0}Digital\u{00A0}Ultrastar\u{00A0}DC\u{00A0}HC555\u{00A0}16TB"
        )
    }

    func testSmartSnapshotFileNameUsesLocalizedTimeZoneAndCSVExtension() {
        let drive = Self.fixtureDrive()
        let date = Date(timeIntervalSince1970: 0)

        XCTAssertEqual(
            ReportExporter.smartSnapshotFileName(drive: drive, date: date, language: .simplifiedChinese),
            "Capricorn-APPLE-SSD-AP1024Z-1970-01-01T08-00-00+0800-UTC+8.csv"
        )
        XCTAssertEqual(
            ReportExporter.smartSnapshotFileName(drive: drive, date: date, language: .english),
            "Capricorn-APPLE-SSD-AP1024Z-1970-01-01T00-00-00Z-UTC+0.csv"
        )
    }

    func testSmartSnapshotCSVReportIncludesMetadataAndEscapesValues() {
        let drive = Self.fixtureDrive()
        var snapshot = Self.fixtureSnapshot(for: drive)
        snapshot.attributes = [
            SmartAttribute(
                id: "AVAILABLE_SPARE",
                name: "Available Spare",
                rawValue: "value, with \"quotes\"",
                current: 100,
                worst: 99,
                threshold: 10,
                status: .good,
                source: "Fixture"
            )
        ]

        let englishCSV = ReportExporter.smartSnapshotCSVReport(drive: drive, snapshot: snapshot, language: .english)
        XCTAssertEqual(
            englishCSV.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init),
            "attribute_id,attribute_name,description,raw_value,current,worst,threshold,status,source"
        )
        XCTAssertFalse(englishCSV.contains("chinese_name"))
        XCTAssertTrue(englishCSV.contains("drive_name,Drive Name,Current display name,APPLE SSD AP1024Z"))
        XCTAssertTrue(englishCSV.contains("model,Model,Model reported by the device,APPLE SSD AP1024Z"))
        XCTAssertTrue(englishCSV.contains("serial_number,Serial Number,Hardware serial reported by the device,SN"))
        XCTAssertTrue(englishCSV.contains("bsd_name,BSD Name,Current macOS device identifier,disk0"))
        XCTAssertTrue(englishCSV.contains("AVAILABLE_SPARE,Available Spare,Remaining NVMe spare capacity.,\"value, with \"\"quotes\"\"\",100,99,10,Good,Fixture"))

        let chineseCSV = ReportExporter.smartSnapshotCSVReport(drive: drive, snapshot: snapshot, language: .simplifiedChinese)
        XCTAssertEqual(
            chineseCSV.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init),
            "attribute_id,attribute_name,chinese_name,description,raw_value,current,worst,threshold,status,source"
        )
        XCTAssertTrue(chineseCSV.contains("AVAILABLE_SPARE,Available Spare,可用备用空间,NVMe 备用块剩余比例，低于阈值时需要关注。,\"value, with \"\"quotes\"\"\",100,99,10,Good,Fixture"))
        XCTAssertTrue(chineseCSV.contains("serial_number,Serial Number,序列号,设备报告的硬件序列号,SN"))
    }

    func testExternalDriveModelCatalogUsesHardwareModelWhenBridgeNameIsGeneric() throws {
        var drive = Self.externalCatalogDrive(model: "USB 3.0 Device")
        drive.model = "ST8000NM000A-2KE101 Media"

        let match = try XCTUnwrap(ExternalDriveModelCatalog.bundled.match(for: drive))

        XCTAssertEqual(match.canonicalModel, "ST8000NM000A")
        XCTAssertEqual(match.reportedModel, "ST8000NM000A-2KE101 Media")
    }

    func testExternalDriveModelCatalogLeavesUnknownInternalAndNVMeDrivesUntouched() {
        let catalog = ExternalDriveModelCatalog.bundled
        let unknown = Self.externalCatalogDrive(model: "Vendor Unknown 8TB")
        var internalDrive = Self.externalCatalogDrive(model: "ST8000NM000A-2KE101")
        internalDrive.isInternal = true
        var systemDrive = Self.externalCatalogDrive(model: "ST8000NM000A-2KE101")
        systemDrive.isSystemDisk = true
        var nvmeDrive = Self.externalCatalogDrive(model: "ST8000NM000A-2KE101", protocolName: "PCI-Express")
        nvmeDrive.isSolidState = true

        XCTAssertNil(catalog.match(for: unknown))
        XCTAssertNil(catalog.match(for: internalDrive))
        XCTAssertNil(catalog.match(for: systemDrive))
        XCTAssertNil(catalog.match(for: nvmeDrive))
        XCTAssertEqual(unknown.catalogDisplayName, unknown.displayName)
        XCTAssertEqual(internalDrive.catalogDisplayName, internalDrive.displayName)
        XCTAssertEqual(nvmeDrive.catalogDisplayName, nvmeDrive.displayName)
    }

    func testExternalDriveModelCatalogRejectsUnsupportedSchemaAndInvalidRegex() {
        let unsupportedSchema = Data(#"{"schemaVersion":2,"records":[]}"#.utf8)
        let invalidRegex = Data(#"{"schemaVersion":1,"records":[{"id":"bad","manufacturer":"Vendor","family":"Family","mediaKind":"HDD","interfaces":["SATA"],"introduced":2024,"modelPatterns":["("],"capacityLabels":{"1":"1TB"},"sourceURL":"https://example.com","examples":[]}]}"#.utf8)

        XCTAssertThrowsError(try ExternalDriveModelCatalog(data: unsupportedSchema))
        XCTAssertThrowsError(try ExternalDriveModelCatalog(data: invalidRegex))
    }

    func testDriveCapacityUsageDeduplicatesSharedAPFSSpaceAndAggregatesPartitions() throws {
        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(
                deviceIdentifier: "disk3s1",
                name: "System",
                mountPoint: "/",
                sizeBytes: 1_000,
                isWritable: false,
                isSystem: true,
                fileSystemType: "APFS",
                capacityGroupIdentifier: "apfs:disk3",
                totalCapacityBytes: 1_000,
                availableCapacityBytes: 400
            ),
            DriveDevice.Volume(
                deviceIdentifier: "disk3s5",
                name: "Data",
                mountPoint: "/System/Volumes/Data",
                sizeBytes: 1_000,
                isWritable: true,
                isSystem: true,
                fileSystemType: "APFS",
                capacityGroupIdentifier: "apfs:disk3",
                totalCapacityBytes: 1_000,
                availableCapacityBytes: 400
            ),
            DriveDevice.Volume(
                deviceIdentifier: "disk0s4",
                name: "Media",
                mountPoint: "/Volumes/Media",
                sizeBytes: 500,
                isWritable: true,
                isSystem: false,
                fileSystemType: "ExFAT",
                capacityGroupIdentifier: "volume:disk0s4",
                totalCapacityBytes: 500,
                availableCapacityBytes: 100
            )
        ]

        let usage = try XCTUnwrap(drive.capacityUsage)
        XCTAssertEqual(usage.totalBytes, 1_500)
        XCTAssertEqual(usage.usedBytes, 1_000)
        XCTAssertEqual(usage.availableBytes, 500)
        XCTAssertEqual(usage.usedFraction, 2.0 / 3.0, accuracy: 0.0001)
    }

    func testDriveCapacityUsageIsUnavailableWithoutMountedCapacityData() {
        XCTAssertNil(Self.fixtureDrive(mountedAt: "/Volumes/Unit").capacityUsage)
    }

    func testDiskutilParserMapsMountedExternalPartitionToPhysicalDisk() throws {
        let list = try DiskutilPlistParser.parseList(Self.diskutilExternalPartitionListFixture.data(using: .utf8)!)
        let volumes = try XCTUnwrap(list.volumesByPhysicalDisk["disk11"])

        XCTAssertEqual(volumes.map(\.deviceIdentifier), ["disk11s1"])
        XCTAssertEqual(volumes.first?.name, "40G4T_NTFS_E")
        XCTAssertEqual(volumes.first?.mountPoint, "/Volumes/40G4T_NTFS_E")
        XCTAssertEqual(volumes.first?.fileSystemType, "NTFS")

        let drive = try XCTUnwrap(DiskutilPlistParser.parseDevice(
            infoData: Self.disk11InfoFixture.data(using: .utf8)!,
            volumes: volumes,
            showVirtual: false
        ))

        XCTAssertTrue(BenchmarkTargetFolderMatcher.targetFolderBelongsToDrive("/Volumes/40G4T_NTFS_E", drive: drive))
        XCTAssertTrue(BenchmarkTargetFolderMatcher.targetFolderBelongsToDrive("/Volumes/40G4T_NTFS_E/Load", drive: drive))
        XCTAssertEqual(drive.benchmarkMountPoint, "/Volumes/40G4T_NTFS_E")
        XCTAssertEqual(drive.fileSystemSummary, "NTFS")
    }

    func testNetworkMountParserDetectsMountedNetworkVolumes() {
        let output = """
        /dev/disk3s1 on / (apfs, sealed, local, read-only, journaled)
        //lex@nas.local/Media on /Volumes/Media (smbfs, nodev, nosuid, mounted by lex)
        server:/exports/project on /Volumes/Project (nfs, nodev, nosuid)
        map auto_home on /System/Volumes/Data/home (autofs, automounted, nobrowse)
        """

        let entries = NetworkVolumeMountParser.parse(output)

        XCTAssertEqual(entries.map(\.fileSystemType), ["smbfs", "nfs"])
        XCTAssertEqual(entries.map(\.source), ["//lex@nas.local/Media", "server:/exports/project"])
        XCTAssertEqual(entries.map(\.mountPoint), ["/Volumes/Media", "/Volumes/Project"])
        XCTAssertEqual(NetworkVolumeMountParser.protocolDisplayName(for: entries[0].fileSystemType), "SMB")
        XCTAssertEqual(NetworkVolumeMountParser.protocolDisplayName(for: entries[1].fileSystemType), "NFS")
    }

    func testNetworkMountInventoryProviderCreatesBenchmarkableNetworkDrive() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let target = root.appendingPathComponent("Benchmarks")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let output = "//lex@nas.local/Media on \(root.path) (smbfs, nodev, nosuid, mounted by lex)\n"
        let provider = NetworkMountInventoryProvider(runner: StaticCommandRunner(stdout: output))

        let drives = try await provider.loadNetworkDrives()
        let drive = try XCTUnwrap(drives.first)

        XCTAssertTrue(drive.isNetwork)
        XCTAssertEqual(drive.protocolName, "SMB")
        XCTAssertEqual(drive.displayName, root.lastPathComponent)
        XCTAssertEqual(drive.benchmarkMountPoint, root.path)
        XCTAssertTrue(drive.isWritable)
        XCTAssertNotNil(drive.capacityUsage)
        XCTAssertTrue(BenchmarkTargetFolderMatcher.targetFolderBelongsToDrive(target.path, drive: drive))
    }

    func testGitHubRepositoryIntroductionIsLocalized() {
        XCTAssertEqual(AppLanguage.english.t("Open Capricorn GitHub repository"), "Open Capricorn GitHub repository")
        XCTAssertEqual(AppLanguage.simplifiedChinese.t("Open Capricorn GitHub repository"), "打开 Capricorn GitHub 仓库")
        XCTAssertEqual(
            AppLanguage.simplifiedChinese.t("Capricorn GitHub repository introduction"),
            "GitHub 仓库：github.com/LexTheAries2209/Capricorn。代码、版本说明、发布包与问题反馈均在仓库维护，欢迎通过 Issue 或 Pull Request 参与改进。"
        )
    }

    func testSettingsContentIsLocalized() {
        let expectedTranslations = [
            "Settings": "设置",
            "Use Tab to switch feature pages": "使用 Tab 切换功能页面",
            "SMART Refresh": "SMART 刷新",
            "Do not wake sleeping disks for SMART refresh": "SMART 刷新时不唤醒休眠磁盘",
            "Automatic detection": "自动检测",
            "Choose…": "选择…",
            "Automatic": "自动",
            "The selected smartctl path is not executable.": "所选 smartctl 路径不可执行。",
            "Control-Tab and Control-Shift-Tab always switch feature pages. Disable plain Tab switching to restore standard keyboard focus traversal.": "Control-Tab 和 Control-Shift-Tab 始终用于切换功能页面。关闭普通 Tab 切换后，可恢复标准键盘焦点遍历。",
            "Choose": "选择",
            "Choose the smartctl executable.": "选择 smartctl 可执行文件。",
            "Open Settings": "打开设置",
            "Used Capacity": "已用容量",
            "Available Capacity": "可用容量",
            "Used": "已用",
            "Available": "可用"
        ]

        for (key, expected) in expectedTranslations {
            XCTAssertEqual(AppLanguage.simplifiedChinese.t(key), expected, key)
            XCTAssertEqual(AppLanguage.english.t(key), key, key)
        }
    }

    func testContinueMonitoringIsLocalized() {
        XCTAssertEqual(AppLanguage.simplifiedChinese.t("Continue Monitoring"), "继续监控")
    }

    func testExternalSmartDisclosureVerificationRequiresAvailableSmartctlWithoutOpenError() {
        let verified = [ProviderStatus(name: "smartctl", state: .available, message: "Available")]
        let nativeOnly = [ProviderStatus(name: "Native macOS", state: .available, message: "Available")]

        XCTAssertTrue(ExternalSmartDisclosurePolicy.isVerified(providerStatuses: verified, diagnostics: nil))
        XCTAssertFalse(ExternalSmartDisclosurePolicy.isVerified(providerStatuses: nativeOnly, diagnostics: nil))
        XCTAssertFalse(ExternalSmartDisclosurePolicy.isVerified(
            providerStatuses: verified,
            diagnostics: SmartctlDiagnostics(openError: "Device open failed")
        ))
    }

    func testSATSmartDriverPathTitleIsExplicitlyLocalized() {
        XCTAssertEqual(AppLanguage.english.t("SAT SMART Driver Paths"), "SAT SMART Driver Paths")
        XCTAssertEqual(AppLanguage.simplifiedChinese.t("SAT SMART Driver Paths"), "SAT SMART Driver 路径")
    }

    func testExternalSmartDisclosureVisibilityAndInitialExpansionPolicy() {
        let missingSupport = ExternalSupportStatus(
            satDriverInstalled: false,
            smartctlInstalled: false,
            driverPaths: [],
            message: "Missing"
        )
        let installedSupport = ExternalSupportStatus(
            satDriverInstalled: true,
            smartctlInstalled: true,
            driverPaths: ["/Library/Extensions/SATSMARTDriver.kext"],
            message: "Installed"
        )
        let internalDrive = Self.fixtureDrive()
        var externalDrive = internalDrive
        externalDrive.isInternal = false
        externalDrive.isRemovable = true
        var networkDrive = externalDrive
        networkDrive.isNetwork = true
        var memoryCard = externalDrive
        memoryCard.isMemoryCard = true

        XCTAssertTrue(ExternalSmartDisclosurePolicy.showsPanel(for: internalDrive))
        XCTAssertTrue(ExternalSmartDisclosurePolicy.showsPanel(for: externalDrive))
        XCTAssertFalse(ExternalSmartDisclosurePolicy.showsPanel(for: networkDrive))
        XCTAssertFalse(ExternalSmartDisclosurePolicy.showsPanel(for: memoryCard))

        XCTAssertFalse(ExternalSmartDisclosurePolicy.startsExpanded(
            for: internalDrive,
            status: missingSupport,
            isVerified: false
        ))
        XCTAssertFalse(ExternalSmartDisclosurePolicy.startsExpanded(
            for: externalDrive,
            status: installedSupport,
            isVerified: false
        ))
        XCTAssertTrue(ExternalSmartDisclosurePolicy.startsExpanded(
            for: externalDrive,
            status: missingSupport,
            isVerified: false
        ))
        XCTAssertFalse(ExternalSmartDisclosurePolicy.startsExpanded(
            for: externalDrive,
            status: missingSupport,
            isVerified: true
        ))
    }

    func testSingleBenchmarkActionsAreLocalized() {
        XCTAssertEqual(AppLanguage.simplifiedChinese.t("Run Single Test"), "运行单项测试")
        XCTAssertEqual(AppLanguage.simplifiedChinese.t("Benchmark in Progress"), "测速正在进行")
        XCTAssertEqual(
            AppLanguage.simplifiedChinese.t("Please stop the current benchmark before running a single test."),
            "请先停止当前测试，再运行单项测试。"
        )
    }

    func testSmallBlockEfficiencyControlsAreLocalized() {
        XCTAssertEqual(
            AppLanguage.simplifiedChinese.t("Improve Small-Block Test Efficiency"),
            "提高小块文件测试效率"
        )
        XCTAssertEqual(
            AppLanguage.simplifiedChinese.t("Use the selected test-size percentage for 4 KiB, 16 KiB, and 64 KiB items."),
            "4 KiB、16 KiB 和 64 KiB 测试项目使用所选的测试文件大小比例。"
        )
    }

    func testFirstAidContentIsLocalized() {
        let expectedTranslations = [
            "First Aid…": "急救…",
            "Disk First Aid": "磁盘急救",
            "Required Confirmations": "必要确认",
            "Run First Aid": "运行磁盘急救",
            "Direct First Aid Unavailable": "无法直接执行磁盘急救",
            "Open Files Found": "发现占用文件的程序",
            "Stop After Current Volume": "完成当前卷后停止",
            "Windows CHKDSK Guide": "Windows CHKDSK 指南",
            "First Aid completed.": "磁盘急救已完成。"
        ]

        for (key, expected) in expectedTranslations {
            XCTAssertEqual(AppLanguage.simplifiedChinese.t(key), expected, key)
            XCTAssertEqual(AppLanguage.english.t(key), key, key)
        }
    }


    func testDriveDeviceDecodesOlderRecordsWithoutNetworkFlag() throws {
        let encoded = try JSONEncoder().encode(Self.fixtureDrive(mountedAt: "/Volumes/Unit"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "isNetwork")
        object.removeValue(forKey: "isMemoryCard")
        if var volumes = object["volumes"] as? [[String: Any]] {
            volumes = volumes.map { volume in
                var volume = volume
                volume.removeValue(forKey: "fileSystemType")
                volume.removeValue(forKey: "capacityGroupIdentifier")
                volume.removeValue(forKey: "totalCapacityBytes")
                volume.removeValue(forKey: "availableCapacityBytes")
                return volume
            }
            object["volumes"] = volumes
        }
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(DriveDevice.self, from: legacyData)

        XCTAssertFalse(decoded.isNetwork)
        XCTAssertFalse(decoded.isMemoryCard)
        XCTAssertEqual(decoded.bsdName, "disk0")
        XCTAssertNil(decoded.capacityUsage)
    }

    func testDiskSidebarActionsLimitNetworkDrivesToSafeNetworkOperations() {
        var drive = Self.fixtureDrive(mountedAt: "/Volumes/Media")
        drive.isNetwork = true
        drive.protocolName = "SMB"
        drive.deviceNode = "//lex@nas.local/Media"

        XCTAssertEqual(
            DiskSidebarActionPolicy.actions(for: drive),
            [.mount, .unmount, .disconnect, .inspectOpenFiles]
        )
        XCTAssertTrue(DiskSidebarActionPolicy.isEnabled(.mount, for: drive))
        XCTAssertTrue(DiskSidebarActionPolicy.isEnabled(.unmount, for: drive))
        XCTAssertTrue(DiskSidebarActionPolicy.isEnabled(.disconnect, for: drive))
        XCTAssertTrue(DiskSidebarActionPolicy.isEnabled(.inspectOpenFiles, for: drive))
        XCTAssertFalse(DiskSidebarActionPolicy.isEnabled(.eject, for: drive))
        XCTAssertFalse(DiskSidebarActionPolicy.isEnabled(.checkLog, for: drive))
        XCTAssertFalse(DiskSidebarActionPolicy.isEnabled(.detailedCheck, for: drive))
        XCTAssertFalse(DiskSidebarActionPolicy.actions(for: drive).contains(.firstAid))
        XCTAssertFalse(DiskSidebarActionPolicy.isEnabled(.firstAid, for: drive))
    }

    func testDiskSidebarActionsProtectInternalSystemDiskFromMountUnmountAndEject() {
        var drive = Self.fixtureDrive(mountedAt: "/")
        drive.isInternal = true
        drive.isSystemDisk = true
        drive.isRemovable = false
        drive.isMemoryCard = false

        XCTAssertFalse(DiskSidebarActionPolicy.isEnabled(.mount, for: drive))
        XCTAssertFalse(DiskSidebarActionPolicy.isEnabled(.unmount, for: drive))
        XCTAssertFalse(DiskSidebarActionPolicy.isEnabled(.forceUnmount, for: drive))
        XCTAssertFalse(DiskSidebarActionPolicy.isEnabled(.eject, for: drive))
        XCTAssertTrue(DiskSidebarActionPolicy.isEnabled(.inspectOpenFiles, for: drive))
        XCTAssertTrue(DiskSidebarActionPolicy.isEnabled(.revealInFinder, for: drive))
        XCTAssertTrue(DiskSidebarActionPolicy.isEnabled(.refresh, for: drive))
        XCTAssertFalse(DiskSidebarActionPolicy.isEnabled(.checkLog, for: drive))
        XCTAssertFalse(DiskSidebarActionPolicy.isEnabled(.detailedCheck, for: drive))
        XCTAssertTrue(DiskSidebarActionPolicy.actions(for: drive).contains(.firstAid))
        XCTAssertTrue(DiskSidebarActionPolicy.isEnabled(.firstAid, for: drive))
    }

    func testDiskSidebarActionsIncludeReadOnlyCheckActionsForPhysicalDrives() {
        var drive = Self.fixtureDrive(mountedAt: "/Volumes/Unit")
        drive.isInternal = false
        drive.isSystemDisk = false

        XCTAssertTrue(DiskSidebarActionPolicy.actions(for: drive).contains(.checkLog))
        XCTAssertTrue(DiskSidebarActionPolicy.actions(for: drive).contains(.detailedCheck))
        XCTAssertTrue(DiskSidebarActionPolicy.isEnabled(.checkLog, for: drive))
        XCTAssertTrue(DiskSidebarActionPolicy.isEnabled(.detailedCheck, for: drive))
    }

    func testDiskActionServiceUsesDiskutilForPhysicalSafeActions() async throws {
        let runner = RecordingCommandRunner()
        let service = DiskActionService(runner: runner)
        var drive = Self.fixtureDrive(mountedAt: "/Volumes/Unit")
        drive.isInternal = false
        drive.isSystemDisk = false

        try await service.perform(.mount, on: drive)
        try await service.perform(.unmount, on: drive)
        try await service.perform(.forceUnmount, on: drive)
        try await service.perform(.eject, on: drive)
        try await service.perform(.rename, on: drive, newName: "Renamed")

        XCTAssertEqual(runner.calls.map(\.arguments), [
            ["mountDisk", "disk0"],
            ["unmountDisk", "disk0"],
            ["unmountDisk", "force", "disk0"],
            ["eject", "disk0"],
            ["renameVolume", "/Volumes/Unit", "Renamed"]
        ])
    }

    func testDiskActionServiceRefusesProtectedInternalSystemDiskActions() async throws {
        let runner = RecordingCommandRunner()
        let service = DiskActionService(runner: runner)
        var drive = Self.fixtureDrive(mountedAt: "/")
        drive.isInternal = true
        drive.isSystemDisk = true
        drive.isRemovable = false
        drive.isMemoryCard = false

        for action in [DiskSidebarAction.mount, .unmount, .forceUnmount, .eject] {
            do {
                try await service.perform(action, on: drive)
                XCTFail("Expected protected system disk error for \(action)")
            } catch DiskActionError.protectedSystemDisk {
                continue
            } catch {
                XCTFail("Expected protected system disk error for \(action), got \(error)")
            }
        }

        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testDiskActionServiceUsesMountPointForNetworkUnmountAndOpenForMount() async throws {
        let runner = RecordingCommandRunner()
        let service = DiskActionService(runner: runner)
        var drive = Self.fixtureDrive(mountedAt: "/Volumes/Media")
        drive.isNetwork = true
        drive.protocolName = "SMB"
        drive.deviceNode = "//lex@nas.local/Media"

        try await service.perform(.mount, on: drive)
        try await service.perform(.unmount, on: drive)
        try await service.perform(.disconnect, on: drive)

        XCTAssertEqual(runner.calls.map(\.executable), [
            "/usr/bin/open",
            "/usr/sbin/diskutil",
            "/usr/sbin/diskutil"
        ])
        XCTAssertEqual(runner.calls.map(\.arguments), [
            ["smb://lex@nas.local/Media"],
            ["unmount", "/Volumes/Media"],
            ["unmount", "/Volumes/Media"]
        ])
    }

    func testDiskCheckServiceRunsOrdinaryDiskutilVerificationAndKeepsNonZeroOutput() async throws {
        let runner = RecordingDiskCheckRunner(stdout: "Checking file system\nProblem found\n", stderr: "Exit code warning\n", terminationStatus: 8)
        let service = DiskCheckService(runner: runner, updateIntervalNanoseconds: 1_000_000)
        var drive = Self.fixtureDrive(mountedAt: "/Volumes/Unit")
        drive.isInternal = false
        drive.isSystemDisk = false
        drive.volumes[0].deviceIdentifier = "disk9s1"
        drive.volumes[0].fileSystemType = "APFS"

        let report = await service.check(.ordinary, drive: drive)

        XCTAssertEqual(report.mode, .ordinary)
        XCTAssertEqual(runner.calls.map(\.executable), ["/usr/sbin/diskutil", "/usr/sbin/diskutil"])
        XCTAssertEqual(runner.calls.map(\.arguments), [
            ["verifyDisk", "disk0"],
            ["verifyVolume", "/Volumes/Unit"]
        ])
        XCTAssertEqual(report.entries.map(\.terminationStatus), [8, 8])
        XCTAssertTrue(report.entries.allSatisfy(\.hasIssue))
        XCTAssertTrue(report.entries.first?.stdout.contains("Problem found") == true)
        XCTAssertTrue(report.entries.first?.stderr.contains("Exit code warning") == true)
    }

    func testDiskCheckServiceRunsDetailedFilesystemChecksByVolumeType() async throws {
        let runner = RecordingDiskCheckRunner(stdout: "<plist><string>ok</string></plist>")
        let service = DiskCheckService(runner: runner, updateIntervalNanoseconds: 1_000_000)
        var drive = Self.fixtureDrive(mountedAt: "/Volumes/APFS")
        drive.isInternal = false
        drive.isSystemDisk = false
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "disk9s1", name: "APFS", mountPoint: "/Volumes/APFS", sizeBytes: 1_000, isWritable: true, isSystem: false, fileSystemType: "APFS"),
            DriveDevice.Volume(deviceIdentifier: "disk9s2", name: "ExFAT", mountPoint: "/Volumes/EXFAT", sizeBytes: 1_000, isWritable: true, isSystem: false, fileSystemType: "ExFAT"),
            DriveDevice.Volume(deviceIdentifier: "disk9s3", name: "HFS", mountPoint: "/Volumes/HFS", sizeBytes: 1_000, isWritable: true, isSystem: false, fileSystemType: "HFS+"),
            DriveDevice.Volume(deviceIdentifier: "disk9s4", name: "FAT", mountPoint: "/Volumes/FAT", sizeBytes: 1_000, isWritable: true, isSystem: false, fileSystemType: "FAT32")
        ]

        let report = await service.check(.detailed, drive: drive)

        XCTAssertEqual(report.mode, .detailed)
        XCTAssertEqual(runner.calls.map(\.executable), ["/sbin/fsck_apfs", "/sbin/fsck_exfat", "/sbin/fsck_hfs", "/sbin/fsck_msdos"])
        XCTAssertEqual(runner.calls.map(\.arguments), [
            ["-n", "-x", "/dev/rdisk9s1"],
            ["-n", "-x", "/dev/rdisk9s2"],
            ["-n", "-x", "/dev/rdisk9s3"],
            ["-n", "/dev/rdisk9s4"]
        ])
        XCTAssertEqual(report.entries.count, 4)
        XCTAssertFalse(report.entries.contains(where: \.hasIssue))
    }

    func testDiskCheckServiceReportsUnsupportedDetailedFileSystemsWithoutRunningCommand() async throws {
        let runner = RecordingDiskCheckRunner()
        let service = DiskCheckService(runner: runner, updateIntervalNanoseconds: 1_000_000)
        var drive = Self.fixtureDrive(mountedAt: "/Volumes/NTFS")
        drive.isInternal = false
        drive.isSystemDisk = false
        drive.volumes[0].deviceIdentifier = "disk9s1"
        drive.volumes[0].fileSystemType = "NTFS"

        let report = await service.check(.detailed, drive: drive)

        XCTAssertTrue(runner.calls.isEmpty)
        XCTAssertEqual(report.entries.count, 1)
        XCTAssertNil(report.entries[0].terminationStatus)
        XCTAssertTrue(report.entries[0].hasIssue)
        XCTAssertTrue(report.entries[0].stderr.contains("No native detailed checker"))
    }

    func testDiskCheckServiceSkipsProtectedSystemDiskWithoutRunningCommands() async throws {
        let runner = RecordingDiskCheckRunner()
        let service = DiskCheckService(runner: runner, updateIntervalNanoseconds: 1_000_000)
        var drive = Self.fixtureDrive(mountedAt: "/")
        drive.isInternal = true
        drive.isSystemDisk = true

        let report = await service.check(.ordinary, drive: drive)

        XCTAssertTrue(runner.calls.isEmpty)
        XCTAssertEqual(report.entries.count, 1)
        XCTAssertTrue(report.entries[0].hasIssue)
        XCTAssertTrue(report.entries[0].stderr.contains("System internal disks are protected"))
    }

    func testDiskCheckServicePublishesProgressBeforeAndAfterEachCommand() async throws {
        let runner = RecordingDiskCheckRunner(stdout: "Verified\n")
        let service = DiskCheckService(runner: runner, updateIntervalNanoseconds: 1_000_000)
        var drive = Self.fixtureDrive(mountedAt: "/Volumes/Unit")
        drive.isInternal = false
        drive.isSystemDisk = false
        drive.volumes[0].deviceIdentifier = "disk9s1"
        drive.volumes[0].fileSystemType = "APFS"
        let updates = LockedArray<DiskCheckReport>()

        let final = await service.check(.ordinary, drive: drive) { report in
            updates.append(report)
        }

        XCTAssertGreaterThanOrEqual(updates.snapshot.count, 4)
        XCTAssertEqual(updates.snapshot.first?.entries.count, 1)
        XCTAssertTrue(updates.snapshot.first?.entries.first?.isRunning == true)
        XCTAssertEqual(final.entries.count, 2)
        XCTAssertFalse(final.entries.contains(where: \.isRunning))
        XCTAssertEqual(final.completedEntryCount, 2)
        XCTAssertEqual(final.totalEntryCount, 2)
    }

    func testDiskCheckServiceStreamsOutputBeforeCommandCompletes() async throws {
        let runner = DelayedDiskCheckRunner(
            stdout: "Checking live volume\n",
            stderr: "Scanning catalog\n",
            delayNanoseconds: 30_000_000
        )
        let service = DiskCheckService(runner: runner, updateIntervalNanoseconds: 1_000_000)
        var drive = Self.fixtureDrive(mountedAt: "/Volumes/Unit")
        drive.isInternal = false
        drive.isSystemDisk = false
        drive.bsdName = ""
        drive.volumes[0].deviceIdentifier = "disk9s1"
        drive.volumes[0].fileSystemType = "APFS"
        let updates = LockedArray<DiskCheckReport>()

        let final = await service.check(.ordinary, drive: drive) { report in
            updates.append(report)
        }

        let streamedWhileRunning = updates.snapshot.contains { report in
            guard let entry = report.entries.first else { return false }
            return entry.isRunning && entry.stdout.contains("Checking live volume")
        }
        XCTAssertTrue(streamedWhileRunning)
        XCTAssertEqual(final.entries.count, 1)
        XCTAssertFalse(final.entries[0].isRunning)
        XCTAssertTrue(final.entries[0].stdout.contains("Checking live volume"))
        XCTAssertTrue(final.entries[0].stderr.contains("Scanning catalog"))
    }

    func testDiskOpenFileParserReadsLsofColumnOutput() {
        let output = """
        COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        Finder    123  lex  cwd    DIR   1,23      512  456 /Volumes/Media
        qlmanage 4567  lex  txt    REG   1,23     2048  789 /Volumes/Media/Clip A.mov
        """

        let processes = DiskOpenFileParser.parse(output)

        XCTAssertEqual(processes, [
            DiskOpenFileProcess(command: "Finder", pid: 123, user: "lex", path: "/Volumes/Media"),
            DiskOpenFileProcess(command: "qlmanage", pid: 4567, user: "lex", path: "/Volumes/Media/Clip A.mov")
        ])
    }

    func testDiskOpenFileServiceUsesFilesystemLsofQuery() async throws {
        let runner = RecordingCommandRunner(stdout: "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\nFinder 123 lex cwd DIR 1,23 512 456 /Volumes/Media\n")
        let service = DiskOpenFileService(runner: runner)
        var drive = Self.fixtureDrive(mountedAt: "/Volumes/Media")
        drive.isInternal = false
        drive.isSystemDisk = false

        let inspection = try await service.inspectOpenFiles(on: drive)

        XCTAssertEqual(inspection.mountPoint, "/Volumes/Media")
        XCTAssertEqual(inspection.processes.map(\.command), ["Finder"])
        XCTAssertEqual(runner.calls.map(\.executable), ["/usr/sbin/lsof"])
        XCTAssertEqual(runner.calls.map(\.arguments), [["+f", "--", "/Volumes/Media"]])
    }

    func testDiskOpenFileTableLayoutAllowsHorizontalPathScrolling() {
        XCTAssertEqual(DiskOpenFileTableLayout.columnWidths, [150, 80, 110, 900])
        XCTAssertEqual(DiskOpenFileTableLayout.contentWidth, 1_276)
        XCTAssertGreaterThan(DiskOpenFileTableLayout.contentWidth, 680)
    }

    func testRefreshCommandShortcutUsesCommandR() {
        XCTAssertEqual(AppCommandShortcut.refreshDisks.key, "r")
        XCTAssertTrue(AppCommandShortcut.refreshDisks.modifiers.contains(.command))
    }

    func testSettingsShortcutUsesCommandP() {
        XCTAssertEqual(AppCommandShortcut.settings.key, "p")
        XCTAssertTrue(AppCommandShortcut.settings.modifiers.contains(.command))
        XCTAssertEqual(AppCommandShortcut.settingsKeyEquivalent, KeyEquivalent("p"))
    }

    func testDriveFeatureTabsCycleThroughFiveModules() {
        XCTAssertEqual(DriveFeatureTab.allCases, [.overview, .smart, .benchmark, .liveActivity, .history])
        XCTAssertEqual(DriveFeatureTab.next(after: .overview), .smart)
        XCTAssertEqual(DriveFeatureTab.next(after: .smart), .benchmark)
        XCTAssertEqual(DriveFeatureTab.next(after: .benchmark), .liveActivity)
        XCTAssertEqual(DriveFeatureTab.next(after: .liveActivity), .history)
        XCTAssertEqual(DriveFeatureTab.next(after: .history), .overview)
        XCTAssertEqual(DriveFeatureTab.previous(before: .overview), .history)
        XCTAssertEqual(DriveFeatureTab.previous(before: .history), .liveActivity)
    }

    func testFeatureTabSwitchShortcutsUsePlainTab() {
        XCTAssertEqual(AppCommandShortcut.nextFeatureTab.key, "tab")
        XCTAssertEqual(AppCommandShortcut.previousFeatureTab.key, "tab")
        XCTAssertTrue(AppCommandShortcut.nextFeatureTab.modifiers.contains(.control))
        XCTAssertFalse(AppCommandShortcut.nextFeatureTab.modifiers.contains(.shift))
        XCTAssertTrue(AppCommandShortcut.previousFeatureTab.modifiers.contains(.control))
        XCTAssertTrue(AppCommandShortcut.previousFeatureTab.modifiers.contains(.shift))
    }

    func testFeatureTabKeyRouterHandlesPlainTabBeforeFocusTraversal() {
        XCTAssertEqual(
            AppFeatureTabKeyRouter.action(
                charactersIgnoringModifiers: "\t",
                hasShift: false,
                hasDisqualifyingModifiers: false
            ),
            .next
        )
        XCTAssertEqual(
            AppFeatureTabKeyRouter.action(
                charactersIgnoringModifiers: "\t",
                hasShift: true,
                hasDisqualifyingModifiers: false
            ),
            .previous
        )
        XCTAssertNil(
            AppFeatureTabKeyRouter.action(
                charactersIgnoringModifiers: "\t",
                hasShift: false,
                hasDisqualifyingModifiers: true
            )
        )
        XCTAssertNil(
            AppFeatureTabKeyRouter.action(
                charactersIgnoringModifiers: "r",
                hasShift: false,
                hasDisqualifyingModifiers: false
            )
        )
    }

    @MainActor
    func testViewModelCyclesSelectedFeatureTab() {
        let model = DITViewModel()

        XCTAssertEqual(model.selectedFeatureTab, .overview)
        model.selectNextFeatureTab()
        XCTAssertEqual(model.selectedFeatureTab, .smart)
        model.selectPreviousFeatureTab()
        XCTAssertEqual(model.selectedFeatureTab, .overview)
        model.selectPreviousFeatureTab()
        XCTAssertEqual(model.selectedFeatureTab, .history)
    }

    func testDrivePageHeaderTextMatchesOverviewSubtitle() {
        var drive = Self.fixtureDrive()

        XCTAssertEqual(DrivePageHeaderText.subtitle(for: drive, language: .simplifiedChinese), "disk0 · NVMe · SSD")

        drive.isNetwork = true
        drive.protocolName = "SMB"
        XCTAssertEqual(DrivePageHeaderText.subtitle(for: drive, language: .simplifiedChinese), "disk0 · SMB · 网络硬盘")

        drive.isNetwork = false
        drive.isMemoryCard = true
        drive.protocolName = "Secure Digital"
        XCTAssertEqual(DrivePageHeaderText.subtitle(for: drive, language: .english), "disk0 · Secure Digital · SD Card")
    }

    func testDrivePageHeaderTextShowsFullSerialOrNil() {
        var drive = Self.fixtureDrive()
        drive.serialNumber = "ZR51JYMS"
        XCTAssertEqual(DrivePageHeaderText.serialNumber(for: drive), "ZR51JYMS")

        drive.serialNumber = nil
        XCTAssertEqual(DrivePageHeaderText.serialNumber(for: drive), "nil")
    }

    @MainActor
    func testViewModelCreatesDiskActionFailureWithOpenFilesWhenUnmountFails() async {
        let diskActionService = DiskActionService(runner: StaticCommandRunner(stdout: "", stderr: "Resource busy", terminationStatus: 16))
        let openFileService = DiskOpenFileService(runner: StaticCommandRunner(stdout: """
        COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
        Finder 123 lex cwd DIR 1,23 512 456 /Volumes/Media
        """))
        let model = DITViewModel(diskActionService: diskActionService, openFileService: openFileService)
        var drive = Self.fixtureDrive(mountedAt: "/Volumes/Media")
        drive.isInternal = false
        drive.isSystemDisk = false
        model.drives = [drive]

        await model.performDiskAction(.unmount, on: drive)

        XCTAssertEqual(model.diskActionFailure?.action, .unmount)
        XCTAssertEqual(model.diskActionFailure?.drive.id, drive.id)
        XCTAssertEqual(model.diskActionFailure?.openFiles.processes, [
            DiskOpenFileProcess(command: "Finder", pid: 123, user: "lex", path: "/Volumes/Media")
        ])
        XCTAssertTrue(model.diskActionFailure?.canForceUnmount == true)
    }

    func testDiskutilParserMarksSecureDigitalReaderAsMemoryCard() throws {
        let drive = try XCTUnwrap(DiskutilPlistParser.parseDevice(
            infoData: Self.sdxcInfoFixture.data(using: .utf8)!,
            volumes: [],
            showVirtual: false
        ))

        XCTAssertEqual(drive.bsdName, "disk10")
        XCTAssertEqual(drive.protocolName, "Secure Digital")
        XCTAssertEqual(drive.displayName, "Built In SDXC Reader")
        XCTAssertTrue(drive.isMemoryCard)
        XCTAssertFalse(drive.isSolidState)
    }

    func testNetworkDriveSmartProvidersReturnUnavailableReason() async throws {
        var drive = Self.fixtureDrive()
        drive.isNetwork = true
        drive.bsdName = "network-smb-media"
        drive.deviceNode = "//lex@nas.local/Media"
        drive.protocolName = "SMB"

        let nativeSnapshotValue = await NativeSmartProvider().snapshot(for: drive)
        let smartctlSnapshotValue = await SmartctlSmartProvider().snapshot(for: drive)
        let nativeSnapshot = try XCTUnwrap(nativeSnapshotValue)
        let smartctlSnapshot = try XCTUnwrap(smartctlSnapshotValue)

        XCTAssertEqual(nativeSnapshot.health, .unavailable)
        XCTAssertEqual(smartctlSnapshot.health, .unavailable)
        XCTAssertEqual(nativeSnapshot.summary, "Network volumes do not expose local SMART data.")
        XCTAssertEqual(smartctlSnapshot.summary, "Network volumes do not expose local SMART data.")
    }

    func testMemoryCardSmartProvidersReturnUnavailableReason() async throws {
        var drive = Self.fixtureDrive()
        drive.bsdName = "disk10"
        drive.displayName = "Built In SDXC Reader"
        drive.protocolName = "Secure Digital"
        drive.isMemoryCard = true
        drive.isInternal = true
        drive.isRemovable = true
        drive.isSolidState = false
        drive.smartStatusRaw = "Verified"

        let nativeSnapshotValue = await NativeSmartProvider().snapshot(for: drive)
        let smartctlSnapshotValue = await SmartctlSmartProvider().snapshot(for: drive)
        let nativeSnapshot = try XCTUnwrap(nativeSnapshotValue)
        let smartctlSnapshot = try XCTUnwrap(smartctlSnapshotValue)

        XCTAssertEqual(nativeSnapshot.health, .unavailable)
        XCTAssertEqual(smartctlSnapshot.health, .unavailable)
        XCTAssertEqual(nativeSnapshot.summary, "SD cards do not expose standard SMART health data on macOS.")
        XCTAssertEqual(smartctlSnapshot.summary, "SD cards do not expose standard SMART health data on macOS.")
    }

    func testSmartctlNVMeParserExtractsHealthFields() {
        let drive = Self.fixtureDrive()
        let snapshot = SmartctlParser.parseSnapshot(Self.smartctlNVMeFixture.data(using: .utf8)!, drive: drive, providerName: "smartctl", exitStatus: 0)

        XCTAssertEqual(snapshot.health, .good)
        XCTAssertEqual(snapshot.temperatureCelsius, 35)
        XCTAssertEqual(snapshot.lifeRemainingPercent, 98)
        XCTAssertEqual(snapshot.mediaErrors, 0)
        XCTAssertTrue(snapshot.attributes.contains(where: { $0.name == "Available Spare" }))

        let read = snapshot.attributes.first(where: { $0.name == "Data Units Read" })
        let written = snapshot.attributes.first(where: { $0.name == "Data Units Written" })
        XCTAssertEqual(read?.rawValue, formatSmartDataUnits(180246471))
        XCTAssertEqual(written?.rawValue, formatSmartDataUnits(85848679))
        XCTAssertTrue(read?.rawValue.contains("TB") == true)
        XCTAssertTrue(written?.rawValue.contains("TB") == true)
    }

    func testSmartctlATAParserExtractsStructuredSelfTestLogAndRawOutput() {
        let drive = Self.fixtureDrive()
        let snapshot = SmartctlParser.parseSnapshot(
            Self.smartctlATASelfTestFixture.data(using: .utf8)!,
            drive: drive,
            providerName: "smartctl",
            exitStatus: 0,
            stderr: Data("smartctl diagnostic note".utf8)
        )

        XCTAssertEqual(snapshot.selfTestReport?.state, .passed)
        XCTAssertEqual(snapshot.selfTestReport?.entries.count, 2)
        XCTAssertEqual(snapshot.selfTestReport?.entries.first?.kind, .short)
        XCTAssertEqual(snapshot.selfTestReport?.entries.first?.lifetimeHours, 123)
        XCTAssertEqual(snapshot.selfTestReport?.entries.first?.failingLBA, 0)
        XCTAssertTrue(snapshot.selfTestReport?.rawOutput?.contains("smartctl diagnostic note") == true)
        XCTAssertTrue(snapshot.selfTestStatus?.contains("Short") == true)
    }

    func testSmartctlNVMeSelfTestParserHandlesNoCurrentTestAndCompletedResult() {
        let drive = Self.fixtureDrive()
        let snapshot = SmartctlParser.parseSnapshot(
            Self.smartctlNVMeSelfTestFixture.data(using: .utf8)!,
            drive: drive,
            providerName: "smartctl",
            exitStatus: 0
        )

        XCTAssertEqual(snapshot.selfTestReport?.state, .passed)
        XCTAssertEqual(snapshot.selfTestReport?.entries.first?.kind, .long)
        XCTAssertEqual(snapshot.selfTestReport?.entries.first?.lifetimeHours, 456)
    }

    func testSmartctlTargetDescriptorsPreserveSATDeviceType() async {
        let scan = """
        {"devices":[{"name":"/dev/disk0","type":"sat","protocol":"ATA","open_error":"permission denied"}]}
        """
        let provider = SmartctlSmartProvider(
            runner: StaticCommandRunner(stdout: scan),
            configuredPath: "/usr/bin/true"
        )
        let target = await provider.resolvedTargetDescriptors(for: [Self.fixtureDrive()])

        XCTAssertEqual(target[Self.fixtureDrive().id]?.path, "/dev/disk0")
        XCTAssertEqual(target[Self.fixtureDrive().id]?.type, "sat")
        XCTAssertEqual(target[Self.fixtureDrive().id]?.protocolName, "ATA")
        XCTAssertEqual(target[Self.fixtureDrive().id]?.openError, "permission denied")
    }

    func testSmartctlTargetDescriptorsMapBSDNameToNVMeIOServicePath() async {
        let path = "IOService:/AppleARMPE/IONVMeController/IONVMeBlockStorageDevice@1"
        let scan = """
        {"devices":[{"name":"\(path)","type":"nvme","protocol":"NVMe"}]}
        """
        let provider = SmartctlSmartProvider(
            runner: StaticCommandRunner(stdout: scan),
            configuredPath: "/usr/bin/true",
            ioServiceTargetResolver: StaticSmartctlTargetResolver(
                descriptor: SmartctlTargetDescriptor(path: path, type: "nvme")
            )
        )

        let target = await provider.resolvedTargetDescriptors(for: [Self.fixtureDrive()])

        XCTAssertEqual(target[Self.fixtureDrive().id]?.path, path)
        XCTAssertEqual(target[Self.fixtureDrive().id]?.type, "nvme")
    }

    func testSmartctlNVMeCapabilityParserRequiresSelfTestFlag() throws {
        let supported = CommandResult(
            stdout: Data(Self.smartctlNVMeCapabilityFixture.utf8),
            stderr: Data(),
            terminationStatus: 0
        )
        let capability = try XCTUnwrap(SmartctlParser.parseSelfTestCapability(supported))

        XCTAssertTrue(capability.shortSupported)
        XCTAssertTrue(capability.longSupported)
    }

    func testSmartctlMessagesOpenFailureIsNotTreatedAsLimitedData() {
        let fixture = """
        {
          "smartctl": {
            "exit_status": 2,
            "messages": [{"string": "Smartctl open device failed: IOCreatePlugInInterfaceForService failed", "severity": "error"}]
          }
        }
        """
        let snapshot = SmartctlParser.parseSnapshot(
            Data(fixture.utf8),
            drive: Self.fixtureDrive(),
            providerName: "smartctl",
            exitStatus: 2
        )

        XCTAssertEqual(snapshot.providerStatuses.first?.state, .failed)
        XCTAssertEqual(snapshot.providerStatuses.first?.message, "The device could not be opened by smartctl.")
    }

    func testSmartctlCommandFailureExtractsMessageFromAppleScriptErrorJSON() {
        let stderr = """
        0:112: execution error: {
          "smartctl": {
            "exit_status": 2,
            "messages": [{"string": "Smartctl open device failed: IOCreatePlugInInterfaceForService failed", "severity": "error"}]
          }
        } (1)
        """
        let result = CommandResult(stdout: Data(), stderr: Data(stderr.utf8), terminationStatus: 1)

        XCTAssertEqual(SmartctlParser.commandFailureMessage(result), "The device could not be opened by smartctl.")
    }

    func testSmartctlCommandFailureExplainsMacOSNativeNVMeTransportLimit() {
        let result = CommandResult(
            stdout: Data(),
            stderr: Data("NVMe Self-test cmd failed: NVMe admin command 0x14 is not supported".utf8),
            terminationStatus: 1
        )

        XCTAssertEqual(
            SmartctlParser.commandFailureMessage(result),
            SmartSelfTestService.macOSNativeNVMeUnavailableMessage
        )
    }

    func testSmartSelfTestServiceRejectsMacOSNativeNVMeAfterReadingCapability() async {
        let path = "IOService:/AppleARMPE/IONVMeController/IONVMeBlockStorageDevice@1"
        let scan = """
        {"devices":[{"name":"\(path)","type":"nvme","protocol":"NVMe"}]}
        """
        let adminRunner = SequencedCommandRunner(results: [
            CommandResult(stdout: Data(Self.smartctlNVMeCapabilityFixture.utf8), stderr: Data(), terminationStatus: 0)
        ])
        let provider = SmartctlSmartProvider(
            runner: StaticCommandRunner(stdout: scan),
            configuredPath: "/usr/bin/true",
            ioServiceTargetResolver: StaticSmartctlTargetResolver(
                descriptor: SmartctlTargetDescriptor(path: path, type: "nvme")
            )
        )
        let service = SmartSelfTestService(
            smartctlProvider: provider,
            administratorRunner: adminRunner
        )

        do {
            _ = try await service.start(kind: .short, drive: Self.fixtureDrive())
            XCTFail("Expected the macOS native NVMe transport to reject Device Self-test command 0x14")
        } catch {
            XCTAssertEqual(error.localizedDescription, SmartSelfTestService.macOSNativeNVMeUnavailableMessage)
        }

        XCTAssertEqual(adminRunner.calls.count, 1)
        XCTAssertTrue(adminRunner.calls[0].arguments.contains("-c"))
        XCTAssertFalse(adminRunner.calls[0].arguments.contains("-t"))
    }

    func testMacOSNativeNVMeSnapshotKeepsReadOnlySmartctlAccess() async throws {
        let path = "IOService:/AppleARMPE/IONVMeController/IONVMeBlockStorageDevice@1"
        let scan = """
        {"devices":[{"name":"\(path)","type":"nvme","protocol":"NVMe"}]}
        """
        let runner = SequencedCommandRunner(results: [
            CommandResult(stdout: Data(scan.utf8), stderr: Data(), terminationStatus: 0),
            CommandResult(stdout: Data(Self.smartctlNVMeFixture.utf8), stderr: Data(), terminationStatus: 0)
        ])
        let provider = SmartctlSmartProvider(
            runner: runner,
            configuredPath: "/usr/bin/true",
            ioServiceTargetResolver: StaticSmartctlTargetResolver(
                descriptor: SmartctlTargetDescriptor(path: path, type: "nvme")
            ),
            avoidsWakingSleepingDisks: { true }
        )

        let snapshotValue = await provider.snapshot(for: Self.fixtureDrive())
        let snapshot = try XCTUnwrap(snapshotValue)

        XCTAssertEqual(snapshot.health, .good)
        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertEqual(runner.calls[0].arguments, ["--scan", "--json"])
        XCTAssertTrue(runner.calls[1].arguments.contains("-a"))
        XCTAssertTrue(runner.calls[1].arguments.contains("--json"))
        XCTAssertTrue(runner.calls[1].arguments.contains("nvme"))
        XCTAssertTrue(runner.calls[1].arguments.contains(path))
        XCTAssertFalse(runner.calls[1].arguments.contains("-t"))
    }

    func testSmartSelfTestServiceUsesShortTestCommandAndEstimatedDuration() async throws {
        let adminRunner = SequencedCommandRunner(results: [
            CommandResult(stdout: Data(Self.smartctlATACapabilityFixture.utf8), stderr: Data(), terminationStatus: 0),
            CommandResult(stdout: Data("Please wait 2 minutes for test to complete.".utf8), stderr: Data(), terminationStatus: 0)
        ])
        let provider = SmartctlSmartProvider(
            runner: StaticCommandRunner(stdout: #"{"devices":[{"name":"/dev/disk0","type":"sat","protocol":"ATA"}]}"#),
            configuredPath: "/usr/bin/true"
        )
        let service = SmartSelfTestService(
            smartctlProvider: provider,
            administratorRunner: adminRunner
        )

        let result = try await service.start(kind: SmartSelfTestKind.short, drive: Self.fixtureDrive())

        XCTAssertEqual(result.estimatedDurationSeconds, 120)
        XCTAssertEqual(adminRunner.calls.count, 2)
        XCTAssertTrue(adminRunner.calls[0].arguments.contains("-c"))
        XCTAssertTrue(adminRunner.calls[1].arguments.contains("-t"))
        XCTAssertTrue(adminRunner.calls[1].arguments.contains("short"))
    }

    @MainActor
    func testSystemDiskSelfTestIsBlockedWhenPreferenceIsDisabled() {
        let adminRunner = SequencedCommandRunner(results: [])
        let provider = SmartctlSmartProvider(
            runner: StaticCommandRunner(stdout: ""),
            configuredPath: "/usr/bin/true"
        )
        let service = SmartSelfTestService(
            smartctlProvider: provider,
            administratorRunner: adminRunner
        )
        let model = AppModel(
            smartSelfTestService: service,
            allowsSystemDiskSelfTests: { false }
        )
        var drive = Self.fixtureDrive()
        drive.isSystemDisk = true
        model.smartSelfTestCapabilities[drive.id] = .supported(SmartSelfTestCapability(
            shortSupported: true,
            longSupported: true,
            message: "Self-test capability confirmed."
        ))

        model.startSmartSelfTest(kind: .short, drive: drive)

        XCTAssertEqual(model.smartSelfTestSession, .failed("System-disk self-tests are disabled in Settings."))
        XCTAssertTrue(adminRunner.calls.isEmpty)
    }

    @MainActor
    func testClearingSmartSelfTestMessageKeepsSessionState() {
        let model = AppModel()
        let failure = "Self-test command failed."
        model.smartSelfTestSession = .failed(failure)
        model.smartSelfTestMessage = failure

        model.clearSmartSelfTestMessage()

        XCTAssertNil(model.smartSelfTestMessage)
        XCTAssertEqual(model.smartSelfTestSession, .failed(failure))
    }

    func testNativeSmartFormatsKelvinTemperatureAndDataUnitsAsTB() async throws {
        var drive = Self.fixtureDrive()
        drive.nativeSmartKeys = [
            "TEMPERATURE": 312,
            "DATA_UNITS_READ": 189403549,
            "DATA_UNITS_WRITTEN": 95506302
        ]

        let snapshotValue = await NativeSmartProvider().snapshot(for: drive)
        let snapshot = try XCTUnwrap(snapshotValue)
        XCTAssertEqual(snapshot.temperatureCelsius ?? 0, 38.85, accuracy: 0.001)
        XCTAssertEqual(snapshot.attributes.first(where: { $0.name == "Temperature" })?.rawValue, "312 K (39 °C)")
        XCTAssertEqual(snapshot.attributes.first(where: { $0.name == "Data Units Read" })?.rawValue, formatSmartDataUnits(189403549))
        XCTAssertEqual(snapshot.attributes.first(where: { $0.name == "Data Units Written" })?.rawValue, formatSmartDataUnits(95506302))
    }

    func testSmartctlATAParserFormatsTotalLBAsUsingReportedLogicalBlockSize() throws {
        let fixture = """
        {
          "smartctl": {"exit_status": 0},
          "smart_status": {"passed": true},
          "logical_block_size": 512,
          "ata_smart_attributes": {
            "table": [
              {"id": 241, "name": "Total_LBAs_Written", "value": 100, "worst": 253, "thresh": 0, "raw": {"value": 7574194599, "string": "7574194599"}},
              {"id": 242, "name": "Total_LBAs_Read", "value": 100, "worst": 253, "thresh": 0, "raw": {"value": 7426501503, "string": "7426501503"}},
              {"id": 241, "name": "Lifetime_Writes_GiB", "value": 100, "worst": 100, "thresh": 0, "raw": {"value": 12, "string": "12"}},
              {"id": 190, "name": "Airflow_Temperature_Cel", "value": 54, "worst": 48, "thresh": 40, "raw": {"value": 874250286, "string": "46 (Min/Max 28/52)"}},
              {"id": 240, "name": "Head_Flying_Hours", "value": 100, "worst": 253, "thresh": 0, "raw": {"value": 2332072752447503, "string": "15h+09m+02.978s"}}
            ]
          }
        }
        """
        var drive = Self.fixtureDrive()
        drive.blockSize = 4_096

        let snapshot = SmartctlParser.parseSnapshot(
            Data(fixture.utf8),
            drive: drive,
            providerName: "smartctl",
            exitStatus: 0
        )

        let written = try XCTUnwrap(snapshot.attributes.first(where: { $0.name == "Total_LBAs_Written" }))
        let read = try XCTUnwrap(snapshot.attributes.first(where: { $0.name == "Total_LBAs_Read" }))
        let vendorSpecific = try XCTUnwrap(snapshot.attributes.first(where: { $0.name == "Lifetime_Writes_GiB" }))
        let airflowTemperature = try XCTUnwrap(snapshot.attributes.first(where: { $0.name == "Airflow_Temperature_Cel" }))
        let headFlyingHours = try XCTUnwrap(snapshot.attributes.first(where: { $0.name == "Head_Flying_Hours" }))
        XCTAssertEqual(written.rawValue, formatSmartLogicalBlocks(7_574_194_599, blockSizeBytes: 512))
        XCTAssertEqual(read.rawValue, formatSmartLogicalBlocks(7_426_501_503, blockSizeBytes: 512))
        XCTAssertTrue(written.rawValue.contains("TB"))
        XCTAssertTrue(written.rawValue.contains("512 B/LBA"))
        XCTAssertEqual(vendorSpecific.rawValue, "12")
        XCTAssertEqual(airflowTemperature.rawValue, "46 (Min/Max 28/52)")
        XCTAssertEqual(headFlyingHours.rawValue, "15h+09m+02.978s")
    }

    func testSmartctlATAParserFallsBackToInventoryBlockSizeForTotalLBAs() throws {
        let fixture = """
        {
          "smartctl": {"exit_status": 0},
          "smart_status": {"passed": true},
          "ata_smart_attributes": {
            "table": [
              {"id": 241, "name": "Total_LBAs_Written", "value": 100, "worst": 100, "thresh": 0, "raw": {"value": 250000000}}
            ]
          }
        }
        """
        var drive = Self.fixtureDrive()
        drive.blockSize = 4_096

        let snapshot = SmartctlParser.parseSnapshot(
            Data(fixture.utf8),
            drive: drive,
            providerName: "smartctl",
            exitStatus: 0
        )

        let written = try XCTUnwrap(snapshot.attributes.first)
        XCTAssertEqual(written.rawValue, formatSmartLogicalBlocks(250_000_000, blockSizeBytes: 4_096))
        XCTAssertTrue(written.rawValue.contains("4096 B/LBA"))
    }

    func testSmartctl75UnifiedHealthFieldsPopulateCanonicalMetrics() throws {
        let fixture = """
        {
          "smartctl": {
            "version": [7, 5],
            "exit_status": 0,
            "drive_database_version": {"string": "7.5/5706"}
          },
          "device": {"name": "/dev/disk8", "type": "sat", "protocol": "ATA"},
          "smart_status": {"passed": true},
          "endurance_used": {"current_percent": 7},
          "spare_available": {"current_percent": 94, "threshold_percent": 10}
        }
        """

        let snapshot = SmartctlParser.parseSnapshot(
            Data(fixture.utf8),
            drive: Self.fixtureDrive(),
            providerName: "smartctl",
            exitStatus: 0
        )

        XCTAssertEqual(snapshot.enduranceUsedPercent, 7)
        XCTAssertEqual(snapshot.lifeRemainingPercent, 93)
        XCTAssertEqual(snapshot.spareAvailablePercent, 94)
        XCTAssertEqual(snapshot.spareAvailableThresholdPercent, 10)
        XCTAssertEqual(snapshot.attributes.first(where: { $0.id == "smartctl.endurance_used" })?.rawValue, "7%")
        XCTAssertEqual(snapshot.attributes.first(where: { $0.id == "smartctl.spare_available" })?.rawValue, "94%")
        XCTAssertEqual(snapshot.smartctlDiagnostics?.version, "7.5")
        XCTAssertEqual(snapshot.smartctlDiagnostics?.driveDatabaseVersion, "7.5/5706")
        XCTAssertEqual(snapshot.smartctlDiagnostics?.targetPath, "/dev/disk8")
        XCTAssertEqual(snapshot.smartctlDiagnostics?.deviceType, "sat")
        XCTAssertEqual(snapshot.smartctlDiagnostics?.protocolName, "ATA")
    }

    func testSmartctlStandbyResultRetainsPreviousSnapshotData() {
        let fixture = """
        {
          "smartctl": {"version": [7, 5], "exit_status": 0},
          "device": {"name": "/dev/disk8", "type": "sat", "protocol": "ATA"},
          "power_mode": {"ata_value": 0, "name": "STANDBY"}
        }
        """
        let drive = Self.fixtureDrive()
        let skipped = SmartctlParser.parseSnapshot(
            Data(fixture.utf8),
            drive: drive,
            providerName: "smartctl",
            exitStatus: 0
        )
        let previous = Self.fixtureSnapshot(for: drive)
        let retained = skipped.retainingSMARTData(from: previous)

        XCTAssertTrue(skipped.smartReadSkippedToAvoidWake)
        XCTAssertEqual(skipped.providerStatuses.first?.state, .limited)
        XCTAssertEqual(skipped.smartctlDiagnostics?.powerMode, "STANDBY")
        XCTAssertEqual(retained.capturedAt, previous.capturedAt)
        XCTAssertEqual(retained.temperatureCelsius, previous.temperatureCelsius)
        XCTAssertEqual(retained.lifeRemainingPercent, previous.lifeRemainingPercent)
        XCTAssertEqual(retained.smartctlDiagnostics?.powerMode, "STANDBY")
    }

    func testSmartctlReadArgumentsAvoidWakeForATAOnly() {
        var ataDrive = Self.fixtureDrive()
        ataDrive.protocolName = "ATA"
        ataDrive.isSolidState = false
        let enabled = SmartctlSmartProvider(
            configuredPath: "/usr/bin/true",
            avoidsWakingSleepingDisks: { true }
        )
        let disabled = SmartctlSmartProvider(
            configuredPath: "/usr/bin/true",
            avoidsWakingSleepingDisks: { false }
        )

        let ataArguments = enabled.smartReadArguments(
            for: ataDrive,
            target: SmartctlTargetDescriptor(path: "/dev/disk8", type: "sat", protocolName: "ATA"),
            fallback: "/dev/disk8"
        )
        let nvmeArguments = enabled.smartReadArguments(
            for: Self.fixtureDrive(),
            target: SmartctlTargetDescriptor(path: "/dev/disk0", type: "nvme", protocolName: "NVMe"),
            fallback: "/dev/disk0"
        )
        let disabledArguments = disabled.smartReadArguments(
            for: ataDrive,
            target: SmartctlTargetDescriptor(path: "/dev/disk8", type: "sat", protocolName: "ATA"),
            fallback: "/dev/disk8"
        )

        XCTAssertEqual(Array(ataArguments.prefix(4)), ["-n", "standby,0", "-a", "--json"])
        XCTAssertFalse(nvmeArguments.contains("-n"))
        XCTAssertFalse(disabledArguments.contains("-n"))
    }

    func testSmartctlSleepProtectionSkipsUnresolvedRotationalDiskWithoutOpeningIt() async throws {
        var drive = Self.fixtureDrive()
        drive.protocolName = "SATA"
        drive.isSolidState = false
        let runner = SequencedCommandRunner(results: [])
        let provider = SmartctlSmartProvider(
            runner: runner,
            configuredPath: "/usr/bin/true",
            avoidsWakingSleepingDisks: { true }
        )

        let snapshotValue = await provider.snapshot(for: drive, resolvedTargetDescriptor: nil)
        let snapshot = try XCTUnwrap(snapshotValue)

        XCTAssertTrue(snapshot.smartReadSkippedToAvoidWake)
        XCTAssertEqual(snapshot.providerStatuses.first?.state, .limited)
        XCTAssertTrue(snapshot.summary.contains("safe device type"))
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testLegacySmartSnapshotJSONDecodesWithoutSmartctl75Fields() throws {
        let previous = Self.fixtureSnapshot(for: Self.fixtureDrive())
        let data = try JSONEncoder.dit.encode(previous)
        let decoded = try JSONDecoder.dit.decode(SmartSnapshot.self, from: data)

        XCTAssertNil(decoded.enduranceUsedPercent)
        XCTAssertNil(decoded.spareAvailablePercent)
        XCTAssertNil(decoded.spareAvailableThresholdPercent)
        XCTAssertNil(decoded.smartctlDiagnostics)
    }

    func testSmartctlOpenErrorBecomesUnavailable() {
        let snapshot = SmartctlParser.parseSnapshot(Self.smartctlOpenErrorFixture.data(using: .utf8)!, drive: Self.fixtureDrive(), providerName: "smartctl", exitStatus: 2)

        XCTAssertEqual(snapshot.health, .unavailable)
        XCTAssertEqual(snapshot.providerStatuses.first?.state, .failed)
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

    func testSmartAttributeDisplayTranslatesCommonExternalATAFields() {
        let expectedTitles = [
            "Raw_Read_Error_Rate": "原始读取错误率",
            "Throughput_Performance": "吞吐性能",
            "Spin_Up_Time": "启动旋转时间",
            "Start_Stop_Count": "启停次数",
            "Seek_Error_Rate": "寻道错误率",
            "Seek_Time_Performance": "寻道时间性能",
            "Spin_Retry_Count": "启动重试次数",
            "Head_Health": "磁头健康",
            "Helium_Level": "内部环境（氦气）状态",
            "End-to-End_Error": "端到端数据路径错误",
            "Reported_Uncorrect": "已报告不可校正错误",
            "Command_Timeout": "命令超时",
            "Airflow_Temperature_Cel": "气流温度",
            "Power-Off_Retract_Count": "断电磁头回收次数",
            "Load_Cycle_Count": "磁头加载循环次数",
            "Temperature_Celsius": "磁盘温度",
            "Hardware_ECC_Recovered": "硬件 ECC 已校正",
            "Head_Flying_Hours": "磁头工作时间",
            "Reallocated_Event_Count": "扇区重映射事件数"
        ]

        for (name, expectedTitle) in expectedTitles {
            let attribute = SmartAttribute(
                id: "fixture.\(name)",
                name: name,
                rawValue: "0",
                current: 100,
                worst: 100,
                threshold: 0,
                status: .good,
                source: "Fixture"
            )
            let display = AppLanguage.simplifiedChinese.smartAttributeDisplay(attribute)
            XCTAssertEqual(display.title, expectedTitle, name)
            XCTAssertFalse(display.subtitle.contains("扩展 SMART 字段"), name)
        }
    }

    func testSmartAttributeDisplayExplainsUnknownUltrastarAttributeWithoutClaimingConfirmation() {
        let attribute = SmartAttribute(
            id: "0x52",
            name: "Unknown_Attribute",
            rawValue: "16711935",
            current: 100,
            worst: 100,
            threshold: 0,
            status: .good,
            source: "smartctl"
        )

        let display = AppLanguage.simplifiedChinese.smartAttributeDisplay(attribute)

        XCTAssertEqual(display.title, "未知厂商属性 0x52")
        XCTAssertTrue(display.subtitle.contains("磁头健康评分"))
        XCTAssertTrue(display.subtitle.contains("尚未"))
        XCTAssertFalse(display.subtitle.contains("扩展 SMART 字段"))
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

    func testBenchmarkProfileConfigurationAppliesRunSizeAndDataPattern() {
        let fileSize: Int64 = 4 * 1_024 * 1_024 * 1_024
        let profile = BenchmarkProfile.default.configured(runs: 5, fileSizeBytes: fileSize, dataPattern: .zeroFill)

        XCTAssertEqual(profile.runs, 5)
        XCTAssertEqual(profile.testFileSizeBytes, fileSize)
        XCTAssertTrue(profile.tests.allSatisfy { $0.testSizeBytes == fileSize })
        XCTAssertTrue(profile.tests.allSatisfy { $0.dataPattern == .zeroFill })
        XCTAssertFalse(profile.usesTrimmedAverage)
        XCTAssertTrue(profile.id.contains("r5"))
        XCTAssertTrue(profile.id.contains("zeroFill"))
        XCTAssertTrue(profile.id.contains("plain"))
    }

    func testSmallBlockEfficiencyScalesOnlySupportedBlockSizes() throws {
        let fileSize: Int64 = 2 * 1_024 * 1_024 * 1_024
        let rows = [4_096, 16_384, 65_536, 131_072].enumerated().map { index, blockSize in
            BenchmarkCustomRow(
                id: "small-block-\(index)",
                accessPattern: .random,
                blockSizeBytes: blockSize,
                queueDepth: 1,
                threads: 1,
                includeMixed: false
            )
        }
        let profile = BenchmarkProfile.custom(rows: rows).configured(
            runs: 1,
            fileSizeBytes: fileSize,
            dataPattern: .random,
            usesSmallBlockEfficiency: true,
            smallBlockFileSizePercent: 20
        )
        let reducedSize = fileSize * 20 / 100

        XCTAssertTrue(profile.id.contains("small-20"))
        XCTAssertTrue(profile.tests.filter { [4_096, 16_384, 65_536].contains($0.blockSizeBytes) }.allSatisfy {
            $0.testSizeBytes == reducedSize
        })
        XCTAssertTrue(profile.tests.filter { $0.blockSizeBytes == 131_072 }.allSatisfy {
            $0.testSizeBytes == fileSize
        })

        let smallBlockRow = try XCTUnwrap(profile.tests.first { $0.blockSizeBytes == 4_096 }?.rowLabel)
        let singleProfile = try XCTUnwrap(profile.singleRunProfile(forRowLabel: smallBlockRow))
        XCTAssertTrue(singleProfile.tests.allSatisfy { $0.testSizeBytes == reducedSize })
    }

    func testDisabledSmallBlockEfficiencyPreservesExistingConfiguration() {
        let legacy = BenchmarkProfile.default.configured(
            runs: 3,
            fileSizeBytes: BenchmarkProfile.defaultTestSize,
            dataPattern: .random
        )
        let disabled = BenchmarkProfile.default.configured(
            runs: 3,
            fileSizeBytes: BenchmarkProfile.defaultTestSize,
            dataPattern: .random,
            usesSmallBlockEfficiency: false,
            smallBlockFileSizePercent: 50
        )

        XCTAssertEqual(disabled, legacy)
        XCTAssertFalse(disabled.id.contains("small-"))
        XCTAssertTrue(disabled.tests.allSatisfy { $0.testSizeBytes == BenchmarkProfile.defaultTestSize })
    }

    func testInvalidSmallBlockEfficiencyPercentFallsBackToTwentyPercent() {
        let invalid = BenchmarkProfile.default.configured(
            runs: 1,
            fileSizeBytes: BenchmarkProfile.defaultTestSize,
            dataPattern: .random,
            usesSmallBlockEfficiency: true,
            smallBlockFileSizePercent: 12
        )
        let expected = BenchmarkProfile.default.configured(
            runs: 1,
            fileSizeBytes: BenchmarkProfile.defaultTestSize,
            dataPattern: .random,
            usesSmallBlockEfficiency: true,
            smallBlockFileSizePercent: 20
        )

        XCTAssertEqual(invalid, expected)
    }

    func testSmallBlockEfficiencyDoesNotChangeProfilesWithoutSupportedBlocks() {
        let legacy = BenchmarkProfile.loop.configured(
            runs: 1,
            fileSizeBytes: BenchmarkProfile.defaultTestSize,
            dataPattern: .random
        )
        let enabled = BenchmarkProfile.loop.configured(
            runs: 1,
            fileSizeBytes: BenchmarkProfile.defaultTestSize,
            dataPattern: .random,
            usesSmallBlockEfficiency: true,
            smallBlockFileSizePercent: 20
        )

        XCTAssertEqual(enabled, legacy)
    }

    func testSingleBenchmarkRowUsesCurrentSettingsWithOnePlainRun() throws {
        let fileSize: Int64 = 4 * 1_024 * 1_024 * 1_024
        let configured = BenchmarkProfile.realWorld
            .applying(engine: .asyncQueue)
            .configured(runs: 7, fileSizeBytes: fileSize, dataPattern: .zeroFill, usesTrimmedAverage: true)
        let selectedRow = try XCTUnwrap(configured.tests.first?.rowLabel)
        let single = try XCTUnwrap(configured.singleRunProfile(forRowLabel: selectedRow))

        XCTAssertEqual(single.id, configured.id)
        XCTAssertEqual(single.engine, configured.engine)
        XCTAssertEqual(single.testFileSizeBytes, fileSize)
        XCTAssertEqual(single.runs, 1)
        XCTAssertFalse(single.usesTrimmedAverage)
        XCTAssertEqual(single.executionMode, .finite)
        XCTAssertFalse(single.tests.isEmpty)
        XCTAssertTrue(single.tests.allSatisfy { $0.rowLabel == selectedRow })
        XCTAssertTrue(single.tests.allSatisfy { $0.testSizeBytes == fileSize })
        XCTAssertTrue(single.tests.allSatisfy { $0.dataPattern == .zeroFill })
    }

    func testSingleBenchmarkRowTurnsLoopModeIntoOneFiniteRun() throws {
        let configured = BenchmarkProfile.loop.configured(
            runs: 9,
            fileSizeBytes: BenchmarkProfile.defaultTestSize,
            dataPattern: .random,
            usesTrimmedAverage: true
        )
        let selectedRow = try XCTUnwrap(configured.tests.first?.rowLabel)
        let single = try XCTUnwrap(configured.singleRunProfile(forRowLabel: selectedRow))

        XCTAssertEqual(single.runs, 1)
        XCTAssertFalse(single.usesTrimmedAverage)
        XCTAssertEqual(single.executionMode, .finite)
    }

    func testSingleBenchmarkMergesSelectedRowWithoutClearingOtherResults() async throws {
        let drive = Self.fixtureDrive(mountedAt: "/Volumes/Unit")
        let configured = BenchmarkProfile.default.configured(
            runs: 3,
            fileSizeBytes: BenchmarkProfile.defaultTestSize,
            dataPattern: .random
        )
        let selectedRow = try XCTUnwrap(configured.tests.first?.rowLabel)
        let single = try XCTUnwrap(configured.singleRunProfile(forRowLabel: selectedRow))
        let originalResults = configured.tests.enumerated().map { index, test in
            BenchmarkResult(
                driveID: drive.id,
                volumePath: "/Volumes/Unit",
                profileID: configured.id,
                profileName: configured.name,
                testID: test.id,
                testLabel: test.label,
                operation: test.operation,
                measuredAt: Date(timeIntervalSince1970: Double(index)),
                bestMegabytesPerSecond: Double(index + 1),
                iops: 1,
                latencyMicroseconds: 1,
                bytesTransferred: test.testSizeBytes
            )
        }
        let runner = ImmediateBenchmarkRunner()
        let provider = FakeDiskActivityProvider(reader: FakeDiskActivityReader(counters: []))
        let model = await MainActor.run {
            let model = DITViewModel(benchmarkRunner: runner, diskActivityProvider: provider)
            model.drives = [drive]
            model.selectedDriveID = drive.id
            model.benchmarkResults = originalResults
            return model
        }

        let started = await MainActor.run {
            model.startBenchmark(
                profile: single,
                volumePath: "/Volumes/Unit",
                resultUpdatePolicy: .mergeTests
            )
        }
        XCTAssertTrue(started)
        let finished = await AsyncTestWaiter.wait {
            let isBenchmarking = await MainActor.run { model.isBenchmarking }
            return runner.runCount == 1 && !isBenchmarking
        }
        XCTAssertTrue(finished)

        let finalResults = await MainActor.run { model.benchmarkResults }
        XCTAssertEqual(finalResults.count, originalResults.count)
        for original in originalResults {
            let updated = try XCTUnwrap(finalResults.first { $0.testID == original.testID })
            if BenchmarkTest.rowLabel(for: original.testLabel) == selectedRow {
                XCTAssertGreaterThanOrEqual(updated.bestMegabytesPerSecond, 1_000)
            } else {
                XCTAssertEqual(updated, original)
            }
        }

        let receivedProfile = try XCTUnwrap(runner.receivedProfiles.first)
        XCTAssertEqual(receivedProfile.id, configured.id)
        XCTAssertEqual(receivedProfile.runs, 1)
        XCTAssertFalse(receivedProfile.usesTrimmedAverage)
        XCTAssertTrue(receivedProfile.tests.allSatisfy { $0.rowLabel == selectedRow })
    }

    func testBenchmarkProfileConfigurationSeparatesResultIDs() {
        let random = BenchmarkProfile.default.configured(runs: 3, fileSizeBytes: BenchmarkProfile.defaultTestSize, dataPattern: .random)
        let zeroFill = BenchmarkProfile.default.configured(runs: 3, fileSizeBytes: BenchmarkProfile.defaultTestSize, dataPattern: .zeroFill)
        let larger = BenchmarkProfile.default.configured(runs: 3, fileSizeBytes: 4 * 1_024 * 1_024 * 1_024, dataPattern: .random)
        let trimmedAverage = BenchmarkProfile.default.configured(runs: 3, fileSizeBytes: BenchmarkProfile.defaultTestSize, dataPattern: .random, usesTrimmedAverage: true)

        XCTAssertNotEqual(random.id, zeroFill.id)
        XCTAssertNotEqual(random.id, larger.id)
        XCTAssertNotEqual(random.id, trimmedAverage.id)
        XCTAssertEqual(random.baseProfileID, BenchmarkProfile.default.id)
        XCTAssertFalse(random.usesTrimmedAverage)
        XCTAssertTrue(trimmedAverage.usesTrimmedAverage)
    }

    func testBenchmarkCustomRowsDefaultGenerateCurrentCustomTests() {
        let profile = BenchmarkProfile.custom(rows: BenchmarkCustomRow.defaultRows)

        XCTAssertEqual(profile.baseProfileID, "custom")
        XCTAssertEqual(profile.tests.map(\.label), [
            "SEQ1MiB Q1T1",
            "SEQ1MiB Q1T1",
            "SEQ1MiB Q1T1 Mix",
            "RND4KiB Q4T1",
            "RND4KiB Q4T1",
            "RND4KiB Q4T1 Mix"
        ])
        XCTAssertEqual(profile.tests.map(\.operation), [.read, .write, .mixed, .read, .write, .mixed])
        XCTAssertEqual(profile.tests.filter { $0.operation == .mixed }.map(\.writePercentForMixed), [30, 30])
    }

    func testBenchmarkCustomRowsGenerateMixedPerGroup() {
        let rows = [
            BenchmarkCustomRow(id: "a", accessPattern: .sequential, blockSizeBytes: 1_048_576, queueDepth: 1, threads: 1, includeMixed: false),
            BenchmarkCustomRow(id: "b", accessPattern: .random, blockSizeBytes: 4_096, queueDepth: 8, threads: 2, includeMixed: true)
        ]

        let profile = BenchmarkProfile.custom(rows: rows)

        XCTAssertEqual(profile.tests.map(\.label), [
            "SEQ1MiB Q1T1",
            "SEQ1MiB Q1T1",
            "RND4KiB Q8T2",
            "RND4KiB Q8T2",
            "RND4KiB Q8T2 Mix"
        ])
        XCTAssertEqual(profile.tests.map(\.operation), [.read, .write, .read, .write, .mixed])
    }

    func testBenchmarkCustomRowsAreLimitedAndFallbackToDefaults() {
        let fiveRows = (0..<5).map { index in
            BenchmarkCustomRow(id: "row-\(index)", accessPattern: .sequential, blockSizeBytes: 1_048_576, queueDepth: 1, threads: 1, includeMixed: false)
        }

        XCTAssertEqual(BenchmarkCustomRow.sanitized(fiveRows).count, BenchmarkCustomRow.maxRows)
        XCTAssertEqual(BenchmarkCustomRow.sanitized([]), BenchmarkCustomRow.defaultRows)
    }

    func testBenchmarkCustomRowsPersistThroughJSONAndFallbackOnInvalidJSON() {
        let rows = [
            BenchmarkCustomRow(id: "a", accessPattern: .random, blockSizeBytes: 65_536, queueDepth: 16, threads: 4, includeMixed: true)
        ]

        let encoded = BenchmarkCustomRow.encodeList(rows)
        XCTAssertEqual(BenchmarkCustomRow.decodeList(from: encoded), rows)
        XCTAssertEqual(BenchmarkCustomRow.decodeList(from: "not-json"), BenchmarkCustomRow.defaultRows)
    }

    func testBenchmarkCustomProfileIDChangesWhenRowsChange() {
        let baseRows = [
            BenchmarkCustomRow(id: "a", accessPattern: .sequential, blockSizeBytes: 1_048_576, queueDepth: 1, threads: 1, includeMixed: true)
        ]
        let changedRows = [
            BenchmarkCustomRow(id: "a", accessPattern: .sequential, blockSizeBytes: 4_194_304, queueDepth: 1, threads: 1, includeMixed: true)
        ]

        let first = BenchmarkProfile.custom(rows: baseRows).configured(runs: 3, fileSizeBytes: BenchmarkProfile.defaultTestSize, dataPattern: .random)
        let second = BenchmarkProfile.custom(rows: changedRows).configured(runs: 3, fileSizeBytes: BenchmarkProfile.defaultTestSize, dataPattern: .random)

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertTrue(first.id.contains("rows-"))
        XCTAssertEqual(first.baseProfileID, "custom")
    }

    func testBenchmarkCustomProfileAppliesEngineAndLoopOptions() {
        let rows = [
            BenchmarkCustomRow(id: "a", accessPattern: .sequential, blockSizeBytes: 1_048_576, queueDepth: 8, threads: 2, includeMixed: false)
        ]

        let asyncLoop = BenchmarkProfile.custom(
            rows: rows,
            engine: .asyncQueue,
            executionMode: .loopUntilCancelled
        ).configured(
            runs: 9,
            fileSizeBytes: 2 * 1_024 * 1_024 * 1_024,
            dataPattern: .zeroFill,
            usesTrimmedAverage: true
        )

        XCTAssertEqual(asyncLoop.engine, .asyncQueue)
        XCTAssertEqual(asyncLoop.executionMode, .loopUntilCancelled)
        XCTAssertEqual(asyncLoop.runs, 1)
        XCTAssertFalse(asyncLoop.usesTrimmedAverage)
        XCTAssertTrue(asyncLoop.id.contains("rows-"))
        XCTAssertTrue(asyncLoop.id.contains("loop-s"))
        XCTAssertTrue(asyncLoop.id.contains("engine-asyncQueue"))
        XCTAssertTrue(asyncLoop.tests.allSatisfy { $0.dataPattern == .zeroFill })
    }

    func testBenchmarkCustomProfileIDChangesWhenEngineChanges() {
        let rows = [
            BenchmarkCustomRow(id: "a", accessPattern: .random, blockSizeBytes: 4_096, queueDepth: 8, threads: 1, includeMixed: true)
        ]

        let sync = BenchmarkProfile.custom(rows: rows, engine: .synchronous).configured(
            runs: 3,
            fileSizeBytes: BenchmarkProfile.defaultTestSize,
            dataPattern: .random
        )
        let async = BenchmarkProfile.custom(rows: rows, engine: .asyncQueue).configured(
            runs: 3,
            fileSizeBytes: BenchmarkProfile.defaultTestSize,
            dataPattern: .random
        )

        XCTAssertNotEqual(sync.id, async.id)
        XCTAssertEqual(sync.engine, .synchronous)
        XCTAssertEqual(async.engine, .asyncQueue)
    }

    func testBenchmarkExperimentalProfilesAreHiddenFromPresets() {
        let presetIDs = BenchmarkProfile.presets.map(\.baseProfileID)

        XCTAssertEqual(presetIDs, ["default", "peak-nvme", "real-world", "demo", "custom"])
        XCTAssertFalse(presetIDs.contains("test"))
        XCTAssertFalse(presetIDs.contains("loop"))
        XCTAssertFalse(presetIDs.contains("loop-extreme"))
    }

    func testBenchmarkPresetDefaultEnginesAreExplicitPerProfile() {
        XCTAssertEqual(BenchmarkProfile.default.engine, .asyncQueue)
        XCTAssertEqual(BenchmarkProfile.peakNVMe.engine, .asyncQueue)
        XCTAssertEqual(BenchmarkProfile.realWorld.engine, .synchronous)
        XCTAssertEqual(BenchmarkProfile.demoLight.engine, .synchronous)
        XCTAssertEqual(BenchmarkProfile.custom.engine, .synchronous)
    }

    func testBenchmarkProfileApplyingEngineChangesResultFingerprint() {
        let sync = BenchmarkProfile.default
            .applying(engine: .synchronous)
            .configured(runs: 3, fileSizeBytes: BenchmarkProfile.defaultTestSize, dataPattern: .random)
        let async = BenchmarkProfile.default
            .applying(engine: .asyncQueue)
            .configured(runs: 3, fileSizeBytes: BenchmarkProfile.defaultTestSize, dataPattern: .random)

        XCTAssertEqual(sync.engine, .synchronous)
        XCTAssertEqual(async.engine, .asyncQueue)
        XCTAssertNotEqual(sync.id, async.id)
    }

    func testBenchmarkTargetFolderMatcherDetectsFolderInsideSelectedDriveMount() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let target = root.appendingPathComponent("Benchmarks")
        let other = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: other)
        }

        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "unit", name: "Unit", mountPoint: root.path, sizeBytes: 1_000_000, isWritable: true, isSystem: false)
        ]

        XCTAssertTrue(BenchmarkTargetFolderMatcher.targetFolderBelongsToDrive(target.path, drive: drive))
        XCTAssertFalse(BenchmarkTargetFolderMatcher.targetFolderBelongsToDrive(other.path, drive: drive))
    }

    func testActivityWorkloadAutomaticTargetUsesFirstWritableMountedVolumeInDeviceOrder() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let readOnly = root.appendingPathComponent("ReadOnly")
        let firstWritable = root.appendingPathComponent("FirstWritable")
        let laterWritable = root.appendingPathComponent("LaterWritable")
        try FileManager.default.createDirectory(at: readOnly, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: firstWritable, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: laterWritable, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "disk9s10", name: "Later", mountPoint: laterWritable.path, sizeBytes: 1_000, isWritable: true, isSystem: false),
            DriveDevice.Volume(deviceIdentifier: "disk9s1", name: "Unmounted", mountPoint: nil, sizeBytes: 1_000, isWritable: true, isSystem: false),
            DriveDevice.Volume(deviceIdentifier: "disk9s2", name: "Read Only", mountPoint: readOnly.path, sizeBytes: 1_000, isWritable: false, isSystem: false),
            DriveDevice.Volume(deviceIdentifier: "disk9s3", name: "First", mountPoint: firstWritable.path, sizeBytes: 1_000, isWritable: true, isSystem: false)
        ]

        let resolved = DiskActivityWorkloadTargetResolver.resolve(.automatic, for: drive)

        XCTAssertEqual(resolved.volume?.deviceIdentifier, "disk9s3")
        XCTAssertEqual(resolved.folderURL?.path, firstWritable.path)
        XCTAssertFalse(resolved.didFallBackToAutomatic)
    }

    func testActivityWorkloadTargetResolvesVolumeAndFolderAndRejectsOtherDrive() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let firstVolume = root.appendingPathComponent("First")
        let secondVolume = root.appendingPathComponent("Second")
        let folder = firstVolume.appendingPathComponent("Workload")
        let outside = root.appendingPathComponent("Outside")
        for directory in [firstVolume, secondVolume, folder, outside] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: root) }

        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "disk9s1", name: "First", mountPoint: firstVolume.path, sizeBytes: 1_000, isWritable: true, isSystem: false),
            DriveDevice.Volume(deviceIdentifier: "disk9s2", name: "Second", mountPoint: secondVolume.path, sizeBytes: 1_000, isWritable: true, isSystem: false)
        ]

        let volumeTarget = DiskActivityWorkloadTargetResolver.resolve(.volume(deviceIdentifier: "disk9s2"), for: drive)
        XCTAssertEqual(volumeTarget.folderURL?.path, secondVolume.path)
        XCTAssertFalse(volumeTarget.didFallBackToAutomatic)

        let folderTarget = DiskActivityWorkloadTargetResolver.resolve(.folder(path: folder.path), for: drive)
        XCTAssertEqual(folderTarget.folderURL?.path, folder.path)
        XCTAssertEqual(folderTarget.volume?.deviceIdentifier, "disk9s1")

        let rejectedTarget = DiskActivityWorkloadTargetResolver.resolve(.folder(path: outside.path), for: drive)
        XCTAssertTrue(rejectedTarget.didFallBackToAutomatic)
        XCTAssertEqual(rejectedTarget.folderURL?.path, firstVolume.path)
    }

    func testActivityWorkloadTargetPreferencesPersistPerDriveAndMigrateValidLegacyFolder() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let firstVolume = root.appendingPathComponent("First")
        let firstFolder = firstVolume.appendingPathComponent("Folder")
        let secondVolume = root.appendingPathComponent("Second")
        let outside = root.appendingPathComponent("Outside")
        for directory in [firstVolume, firstFolder, secondVolume, outside] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: root) }

        var firstDrive = Self.fixtureDrive()
        firstDrive.bsdName = "disk8"
        firstDrive.serialNumber = "SERIAL-A"
        firstDrive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "disk8s1", name: "First", mountPoint: firstVolume.path, sizeBytes: 1_000, isWritable: true, isSystem: false)
        ]
        var secondDrive = Self.fixtureDrive()
        secondDrive.bsdName = "disk9"
        secondDrive.serialNumber = "SERIAL-B"
        secondDrive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "disk9s1", name: "Second", mountPoint: secondVolume.path, sizeBytes: 1_000, isWritable: true, isSystem: false)
        ]

        var preferences = DiskActivityWorkloadTargetPreferences()
        XCTAssertTrue(preferences.migrateLegacyFolder(firstFolder.path, to: firstDrive))
        preferences.setSelection(.volume(deviceIdentifier: "disk9s1"), for: secondDrive)

        let restored = DiskActivityWorkloadTargetPreferences.decode(preferences.encoded())
        XCTAssertEqual(restored.selection(for: firstDrive), .folder(path: firstFolder.path))
        XCTAssertEqual(restored.selection(for: secondDrive), .volume(deviceIdentifier: "disk9s1"))

        var rejected = DiskActivityWorkloadTargetPreferences()
        XCTAssertFalse(rejected.migrateLegacyFolder(outside.path, to: firstDrive))
        XCTAssertEqual(rejected.selection(for: firstDrive), .automatic)
    }

    func testActivityWorkloadAutomaticTargetIsEmptyWithoutWritableMountedVolume() {
        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "disk9s1", name: "Unmounted", mountPoint: nil, sizeBytes: 1_000, isWritable: true, isSystem: false),
            DriveDevice.Volume(deviceIdentifier: "disk9s2", name: "Read Only", mountPoint: "/missing", sizeBytes: 1_000, isWritable: false, isSystem: false)
        ]

        let resolved = DiskActivityWorkloadTargetResolver.resolve(.automatic, for: drive)

        XCTAssertNil(resolved.volume)
        XCTAssertNil(resolved.folderURL)
    }

    func testBenchmarkDefaultsMatchDiskMarkControls() {
        XCTAssertEqual(BenchmarkProfile.defaultRuns, 3)
        XCTAssertEqual(BenchmarkProfile.defaultTestSize, 1_073_741_824)
        XCTAssertEqual(BenchmarkProfile.defaultDataPattern, .random)
        XCTAssertFalse(BenchmarkProfile.defaultUsesTrimmedAverage)
        XCTAssertEqual(BenchmarkProfile.defaultSmallBlockFileSizePercent, 20)
        XCTAssertEqual(BenchmarkProfile.smallBlockFileSizePercentOptions, [5, 10, 20, 30, 50])
        XCTAssertEqual(BenchmarkProfile.smallBlockEfficiencyBlockSizes, [4_096, 16_384, 65_536])
        XCTAssertEqual(BenchmarkProfile.runCountOptions, Array(1...9))
        XCTAssertEqual(BenchmarkProfile.fileSizeOptions.first, BenchmarkProfile.defaultTestSize)
        XCTAssertTrue(BenchmarkProfile.fileSizeOptions.contains(BenchmarkProfile.defaultTestSize))
        XCTAssertTrue(BenchmarkProfile.fileSizeOptions.allSatisfy { $0 >= BenchmarkProfile.defaultTestSize })
        XCTAssertTrue(BenchmarkProfile.presets.allSatisfy { $0.testFileSizeBytes >= BenchmarkProfile.defaultTestSize })
        XCTAssertTrue(BenchmarkProfile.presets.flatMap(\.tests).allSatisfy { $0.testSizeBytes >= BenchmarkProfile.defaultTestSize })
    }

    func testBenchmarkProfileConfigurationClampsSubGigabyteFileSize() {
        let profile = BenchmarkProfile.default.configured(
            runs: 3,
            fileSizeBytes: 256 * 1_024 * 1_024,
            dataPattern: .random
        )

        XCTAssertEqual(profile.testFileSizeBytes, BenchmarkProfile.defaultTestSize)
        XCTAssertTrue(profile.tests.allSatisfy { $0.testSizeBytes == BenchmarkProfile.defaultTestSize })
    }

    func testBenchmarkProgressIncludesCurrentPhaseBytesInFraction() {
        let progress = BenchmarkProgress(
            currentTestLabel: "RND4K Q1T1",
            completed: 2,
            total: 10,
            message: "Read run 1/3",
            phaseCompletedBytes: 512,
            phaseTotalBytes: 1_024
        )

        XCTAssertEqual(progress.fraction, 0.25, accuracy: 0.0001)
    }

    func testBenchmarkProgressUpdateGateThrottlesSamePhaseByteUpdates() {
        let start = Date(timeIntervalSince1970: 1_000)
        let previous = BenchmarkProgress(
            currentTestLabel: "SEQ1M Q1T1",
            completed: 0,
            total: 4,
            message: "Read run 1/1",
            phaseCompletedBytes: 0,
            phaseTotalBytes: 1_000
        )
        let byteOnlyUpdate = BenchmarkProgress(
            currentTestLabel: "SEQ1M Q1T1",
            completed: 0,
            total: 4,
            message: "Read run 1/1",
            phaseCompletedBytes: 200,
            phaseTotalBytes: 1_000
        )
        let nextStage = BenchmarkProgress(
            currentTestLabel: "SEQ1M Q1T1",
            completed: 1,
            total: 4,
            message: "Write run 1/1",
            phaseCompletedBytes: 0,
            phaseTotalBytes: 1_000
        )

        XCTAssertTrue(BenchmarkProgressUpdateGate.shouldPublish(previous: nil, candidate: previous, now: start, lastPublishedAt: nil, minimumInterval: 0.25))
        XCTAssertFalse(BenchmarkProgressUpdateGate.shouldPublish(previous: previous, candidate: byteOnlyUpdate, now: start.addingTimeInterval(0.1), lastPublishedAt: start, minimumInterval: 0.25))
        XCTAssertTrue(BenchmarkProgressUpdateGate.shouldPublish(previous: previous, candidate: byteOnlyUpdate, now: start.addingTimeInterval(0.25), lastPublishedAt: start, minimumInterval: 0.25))
        XCTAssertTrue(BenchmarkProgressUpdateGate.shouldPublish(previous: previous, candidate: nextStage, now: start.addingTimeInterval(0.1), lastPublishedAt: start, minimumInterval: 0.25))
    }

    func testDiskActivityRateCalculatorComputesDecimalMegabytesPerSecond() {
        let start = Date(timeIntervalSince1970: 1_000)
        let previous = DiskActivityCounters(timestamp: start, readBytes: 1_000, writeBytes: 2_000)
        let current = DiskActivityCounters(
            timestamp: start.addingTimeInterval(1),
            readBytes: 1_001_000,
            writeBytes: 2_002_000
        )

        let sample = DiskActivityRateCalculator.sample(previous: previous, current: current)

        XCTAssertEqual(sample.readMegabytesPerSecond, 1.0, accuracy: 0.0001)
        XCTAssertEqual(sample.writeMegabytesPerSecond, 2.0, accuracy: 0.0001)
    }

    func testDiskActivityRateCalculatorClampsCounterResetToZero() {
        let start = Date(timeIntervalSince1970: 1_000)
        let previous = DiskActivityCounters(timestamp: start, readBytes: 4_000, writeBytes: 8_000)
        let current = DiskActivityCounters(timestamp: start.addingTimeInterval(0.5), readBytes: 3_000, writeBytes: 7_000)

        let sample = DiskActivityRateCalculator.sample(previous: previous, current: current)

        XCTAssertEqual(sample.readMegabytesPerSecond, 0)
        XCTAssertEqual(sample.writeMegabytesPerSecond, 0)
    }

    func testDiskActivitySeriesKeepsLatestSamplesInsideLimit() {
        let start = Date(timeIntervalSince1970: 1_000)
        var samples: [DiskActivitySample] = []

        for index in 0..<5 {
            let sample = DiskActivitySample(
                timestamp: start.addingTimeInterval(Double(index)),
                readMegabytesPerSecond: Double(index),
                writeMegabytesPerSecond: Double(index * 2)
            )
            samples = DiskActivitySeries.appending(sample, to: samples, limit: 3)
        }

        XCTAssertEqual(samples.map(\.readMegabytesPerSecond), [2, 3, 4])
        XCTAssertEqual(samples.map(\.writeMegabytesPerSecond), [4, 6, 8])
    }

    func testDiskActivitySampleIntervalsAreFixed() {
        XCTAssertEqual(DiskActivitySampleInterval.allCases.map(\.seconds), [0.1, 0.2, 0.5, 1.0])
        XCTAssertEqual(DiskActivitySampleInterval.default, .half)
        XCTAssertEqual(DITViewModel.benchmarkActivityInterval, .fifth)
    }

    func testDiskActivityMonitorUsesSelectedIntervalAndCachedReader() async {
        let start = Date(timeIntervalSince1970: 1_000)
        let reader = FakeDiskActivityReader(counters: [
            DiskActivityCounters(timestamp: start, readBytes: 0, writeBytes: 0),
            DiskActivityCounters(timestamp: start.addingTimeInterval(0.1), readBytes: 100_000, writeBytes: 200_000)
        ])
        let provider = FakeDiskActivityProvider(reader: reader)
        let waitRequests = LockedArray<UInt64>()
        let samples = LockedArray<DiskActivitySample>()
        let monitor = DiskActivityMonitor(provider: provider) { nanoseconds in
            waitRequests.append(nanoseconds)
            if waitRequests.snapshot.count >= 2 {
                throw CancellationError()
            }
        }

        await monitor.run(bsdName: "disk0", interval: .tenth) { sample in
            samples.append(sample)
        }
        for _ in 0..<20 where samples.snapshot.count < 2 {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }

        XCTAssertEqual(provider.readerCallCount, 1)
        XCTAssertEqual(provider.fallbackCounterCallCount, 0)
        XCTAssertEqual(waitRequests.snapshot, [100_000_000, 100_000_000])
        XCTAssertEqual(samples.snapshot.count, 2)
        XCTAssertEqual(samples.snapshot.last?.readMegabytesPerSecond ?? 0, 1.0, accuracy: 0.0001)
        XCTAssertEqual(samples.snapshot.last?.writeMegabytesPerSecond ?? 0, 2.0, accuracy: 0.0001)
    }

    func testDiskActivityMonitorIntervalIsNotDelayedBySampleDelivery() async {
        let start = Date(timeIntervalSince1970: 1_000)
        let reader = FakeDiskActivityReader(counters: [
            DiskActivityCounters(timestamp: start, readBytes: 0, writeBytes: 0)
        ])
        let provider = FakeDiskActivityProvider(reader: reader)
        let events = LockedArray<String>()
        let monitor = DiskActivityMonitor(provider: provider) { nanoseconds in
            events.append("sleep-\(nanoseconds)")
            throw CancellationError()
        }

        await monitor.run(bsdName: "disk0", interval: .tenth) { _ in
            events.append("sample-start")
            try? await Task.sleep(nanoseconds: 50_000_000)
            events.append("sample-end")
        }
        try? await Task.sleep(nanoseconds: 70_000_000)

        let snapshot = events.snapshot
        XCTAssertNotNil(snapshot.firstIndex(of: "sample-start"))
        XCTAssertNotNil(snapshot.firstIndex(of: "sample-end"))
        XCTAssertLessThan(
            try XCTUnwrap(snapshot.firstIndex(of: "sleep-100000000")),
            try XCTUnwrap(snapshot.firstIndex(of: "sample-end"))
        )
    }

    func testDiskActivityChartScaleCreatesDurationAndSpeedTicks() {
        let start = Date(timeIntervalSince1970: 1_000)
        let samples = [
            DiskActivitySample(timestamp: start, readMegabytesPerSecond: 0, writeMegabytesPerSecond: 0),
            DiskActivitySample(timestamp: start.addingTimeInterval(45), readMegabytesPerSecond: 300, writeMegabytesPerSecond: 120),
            DiskActivitySample(timestamp: start.addingTimeInterval(90), readMegabytesPerSecond: 432, writeMegabytesPerSecond: 60)
        ]

        XCTAssertEqual(DiskActivityChartScale.durationSeconds(for: samples), 90, accuracy: 0.0001)
        XCTAssertEqual(DiskActivityChartScale.xTicks(for: samples).map(\.label), ["0s", "45s", "1m30s"])
        let yTicks = DiskActivityChartScale.yTicks(maxSpeed: 432)
        XCTAssertEqual(yTicks.count, 10)
        XCTAssertEqual(yTicks.first ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(yTicks.last ?? -1, 500, accuracy: 0.0001)
        XCTAssertEqual(yTicks[1], 500.0 / 9.0, accuracy: 0.0001)
    }

    func testBenchmarkActivityPanelKeepsChartVisibleOutsideBenchmark() {
        XCTAssertTrue(BenchmarkActivityPanelState.showsChart(isNetworkDrive: false))
        XCTAssertTrue(BenchmarkActivityPanelState.showsChart(isNetworkDrive: true))
        XCTAssertFalse(BenchmarkActivityPanelState.showsProgress(isBenchmarking: false, hasProgress: true))
        XCTAssertTrue(BenchmarkActivityPanelState.showsProgress(isBenchmarking: true, hasProgress: true))
    }

    func testBenchmarkCancelStopsMonitoringAndIgnoresLateCallbacks() async {
        let drive = Self.fixtureDrive(mountedAt: "/Volumes/Unit")
        let runner = LateCallbackBenchmarkRunner()
        let start = Date(timeIntervalSince1970: 1_000)
        var counters: [DiskActivityCounters] = []
        for index in 0..<20 {
            counters.append(DiskActivityCounters(
                timestamp: start.addingTimeInterval(Double(index) * DITViewModel.benchmarkActivityInterval.seconds),
                readBytes: UInt64(index * 1_000_000),
                writeBytes: UInt64(index * 2_000_000)
            ))
        }
        let reader = FakeDiskActivityReader(counters: counters)
        let provider = FakeDiskActivityProvider(reader: reader)
        let viewModel = await MainActor.run {
            let model = DITViewModel(benchmarkRunner: runner, diskActivityProvider: provider)
            model.drives = [drive]
            model.selectedDriveID = drive.id
            return model
        }

        await MainActor.run {
            XCTAssertTrue(viewModel.startBenchmark(profile: BenchmarkProfile.presets[0], volumePath: "/Volumes/Unit"))
        }
        let didStart = await runner.waitUntilStarted()
        XCTAssertTrue(didStart)

        await MainActor.run {
            XCTAssertFalse(viewModel.startBenchmark(profile: BenchmarkProfile.presets[0], volumePath: "/Volumes/Unit"))
        }

        await MainActor.run {
            viewModel.cancelBenchmark()
        }
        let sampleCountAfterCancel = await MainActor.run {
            viewModel.diskActivitySamples.count
        }

        let didFinish = await runner.waitUntilFinished()
        XCTAssertTrue(didFinish)
        try? await Task.sleep(nanoseconds: 350_000_000)

        let finalState = await MainActor.run {
            (
                isBenchmarking: viewModel.isBenchmarking,
                resultCount: viewModel.benchmarkResults.count,
                sampleCount: viewModel.diskActivitySamples.count,
                error: viewModel.benchmarkError,
                cancelCount: runner.cancelCount
            )
        }
        XCTAssertFalse(finalState.isBenchmarking)
        XCTAssertEqual(finalState.resultCount, 0)
        XCTAssertEqual(finalState.sampleCount, sampleCountAfterCancel)
        XCTAssertEqual(finalState.error, BenchmarkError.cancelled.localizedDescription)
        XCTAssertEqual(finalState.cancelCount, 1)
    }

    func testLateCallbackBenchmarkRunnerWaitsForCancellationBeforeFinishing() async {
        let runner = LateCallbackBenchmarkRunner()
        let drive = Self.fixtureDrive(mountedAt: "/Volumes/Unit")
        let task = Task {
            try? await runner.run(
                profile: BenchmarkProfile.presets[0],
                drive: drive,
                volumePath: "/Volumes/Unit",
                progress: { _ in },
                result: { _ in }
            )
        }

        let didStart = await runner.waitUntilStarted()
        XCTAssertTrue(didStart)
        let finishedBeforeCancellation = await runner.waitUntilFinished()

        runner.cancel()
        let finishedAfterCancellation = await runner.waitUntilFinished()
        _ = await task.result

        XCTAssertFalse(finishedBeforeCancellation)
        XCTAssertTrue(finishedAfterCancellation)
    }

    func testDiskActivityHistoryRecordEncodesSamplesAndSummary() {
        let drive = Self.fixtureDrive()
        let start = Date(timeIntervalSince1970: 1_000)
        let samples = [
            DiskActivitySample(timestamp: start, readMegabytesPerSecond: 10, writeMegabytesPerSecond: 20),
            DiskActivitySample(timestamp: start.addingTimeInterval(1), readMegabytesPerSecond: 30, writeMegabytesPerSecond: 50)
        ]

        let record = DiskActivityHistoryRecord(
            drive: drive,
            samples: samples,
            sampleInterval: .half,
            startedAt: start,
            endedAt: start.addingTimeInterval(1)
        )

        XCTAssertEqual(record.driveID, drive.id)
        XCTAssertEqual(record.sampleInterval, .half)
        XCTAssertEqual(record.durationSeconds, 1)
        XCTAssertEqual(record.peakReadMegabytesPerSecond, 30)
        XCTAssertEqual(record.peakWriteMegabytesPerSecond, 50)
        XCTAssertEqual(record.averageReadMegabytesPerSecond, 20)
        XCTAssertEqual(record.averageWriteMegabytesPerSecond, 35)
        XCTAssertEqual(record.samples, samples)
    }

    func testBenchmarkHistoryRecordStoresBenchmarkActivitySamples() {
        let drive = Self.fixtureDrive()
        let result = Self.fixtureBenchmarkResult(for: drive)
        let start = Date(timeIntervalSince1970: 1_000)
        let samples = [
            DiskActivitySample(timestamp: start, readMegabytesPerSecond: 1_200, writeMegabytesPerSecond: 200),
            DiskActivitySample(timestamp: start.addingTimeInterval(0.5), readMegabytesPerSecond: 300, writeMegabytesPerSecond: 1_400)
        ]

        let record = BenchmarkHistoryRecord(drive: drive, result: result, activitySamples: samples)

        XCTAssertEqual(record.activitySamples, samples)
    }

    func testDiskActivityWorkloadFullDiskUses95PercentOfAvailableCapacity() {
        let gib: Int64 = 1_024 * 1_024 * 1_024
        let mib: Int64 = 1_024 * 1_024
        let available = 100 * gib + DiskActivityWorkloadStorageValidator.safetyMarginBytes
        let usable = available - DiskActivityWorkloadStorageValidator.safetyMarginBytes
        let expectedSingle = (Int64(Double(usable) * 0.95) / mib) * mib
        let expectedMixed = ((Int64(Double(usable) * 0.95) / 2) / mib) * mib

        XCTAssertEqual(
            DiskActivityWorkloadStorageValidator.resolvedFileSize(for: .fullDisk95, operation: .write, availableCapacity: available),
            expectedSingle
        )
        XCTAssertEqual(
            DiskActivityWorkloadStorageValidator.resolvedFileSize(for: .fullDisk95, operation: .mixed, availableCapacity: available),
            expectedMixed
        )
        XCTAssertEqual(
            DiskActivityWorkloadStorageValidator.requiredSpace(fileSizeBytes: expectedSingle, operation: .write),
            expectedSingle + DiskActivityWorkloadStorageValidator.safetyMarginBytes
        )
        XCTAssertEqual(
            DiskActivityWorkloadStorageValidator.requiredSpace(fileSizeBytes: expectedMixed, operation: .mixed),
            expectedMixed * 2 + DiskActivityWorkloadStorageValidator.safetyMarginBytes
        )
    }

    func testDiskActivityWorkloadAvailabilityAccountsForMixedTwoFileFootprint() {
        let fileSize = DiskActivityWorkloadFileSize.gib32.fixedBytes!
        let required = DiskActivityWorkloadStorageValidator.requiredSpace(fileSizeBytes: fileSize, operation: .mixed)

        XCTAssertFalse(DiskActivityWorkloadStorageValidator.isFileSizeAvailable(.gib32, operation: .mixed, availableCapacity: required - 1))
        XCTAssertTrue(DiskActivityWorkloadStorageValidator.isFileSizeAvailable(.gib32, operation: .mixed, availableCapacity: required))
        XCTAssertEqual(required, fileSize * 2 + DiskActivityWorkloadStorageValidator.safetyMarginBytes)
    }

    func testDiskActivityWorkloadRunnerUsesExtremeSequentialSettings() {
        XCTAssertEqual(NativeDiskActivityWorkloadRunner.accessPatternLabel, "SEQ1M")
        XCTAssertEqual(NativeDiskActivityWorkloadRunner.queueDepth, 4)
        XCTAssertEqual(NativeDiskActivityWorkloadRunner.threadCount, 4)
        XCTAssertEqual(NativeDiskActivityWorkloadRunner.requestDepth, 16)
        XCTAssertEqual(NativeDiskActivityWorkloadRunner.transferChunkSizeBytes, 4 * 1_024 * 1_024)
        XCTAssertTrue(NativeDiskActivityWorkloadRunner.usesZeroFill)
    }

    func testDiskActivityWorkloadRunnerPreparesReadFileAndCleansUp() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let drive = Self.fixtureDrive(mountedAt: root.path)
        let names = LockedArray<String>()
        let progressValues = LockedArray<DiskActivityWorkloadProgress>()
        let runner = NativeDiskActivityWorkloadRunner(fileEventHandler: { url in
            names.append(url.lastPathComponent)
        })

        try await runner.run(
            configuration: DiskActivityWorkloadConfiguration(
                targetFolderURL: root,
                operation: .read,
                fileSizeOption: .gib32,
                fileSizeBytes: 32_768,
                loopEnabled: false
            ),
            drive: drive
        ) { progress in
            progressValues.append(progress)
        }

        XCTAssertEqual(names.snapshot.filter { $0.contains("read-source") }.count, 1)
        XCTAssertTrue(progressValues.snapshot.contains { $0.phase == .preparingReadFile })
        XCTAssertTrue(progressValues.snapshot.contains { $0.phase == .reading && $0.completedBytes == 32_768 })

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter {
            $0.hasPrefix("Capricorn-Activity-")
        }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testDiskActivityWorkloadRunnerMixedUsesSeparateReadAndWriteFiles() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let drive = Self.fixtureDrive(mountedAt: root.path)
        let names = LockedArray<String>()
        let progressValues = LockedArray<DiskActivityWorkloadProgress>()
        let runner = NativeDiskActivityWorkloadRunner(fileEventHandler: { url in
            names.append(url.lastPathComponent)
        })

        try await runner.run(
            configuration: DiskActivityWorkloadConfiguration(
                targetFolderURL: root,
                operation: .mixed,
                fileSizeOption: .gib32,
                fileSizeBytes: 65_536,
                loopEnabled: false
            ),
            drive: drive
        ) { progress in
            progressValues.append(progress)
        }

        let createdNames = names.snapshot
        XCTAssertEqual(createdNames.filter { $0.contains("read-source") }.count, 1)
        XCTAssertEqual(createdNames.filter { $0.contains("mixed-write") }.count, 1)
        XCTAssertEqual(Set(createdNames).count, createdNames.count)
        XCTAssertTrue(progressValues.snapshot.contains { $0.phase == .mixed && $0.totalBytes == 131_072 })

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter {
            $0.hasPrefix("Capricorn-Activity-")
        }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testDiskActivityWorkloadRunnerLoopCancelsAndCleansUp() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let drive = Self.fixtureDrive(mountedAt: root.path)
        let names = LockedArray<String>()
        let runner = NativeDiskActivityWorkloadRunner(fileEventHandler: { url in
            names.append(url.lastPathComponent)
        })

        do {
            try await runner.run(
                configuration: DiskActivityWorkloadConfiguration(
                    targetFolderURL: root,
                    operation: .write,
                    fileSizeOption: .gib32,
                    fileSizeBytes: 16_384,
                    loopEnabled: true
                ),
                drive: drive
            ) { progress in
                if progress.loopIndex >= 2, progress.phase == .writing {
                    runner.cancel()
                }
            }
            XCTFail("Expected cancellation")
        } catch BenchmarkError.cancelled {
        }

        XCTAssertGreaterThanOrEqual(names.snapshot.filter { $0.contains("-write-loop") }.count, 2)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter {
            $0.hasPrefix("Capricorn-Activity-")
        }
        XCTAssertTrue(leftovers.isEmpty)
    }








    func testBenchmarkSelectedRunCountAddsTwoMeasuredRunsWhenTrimmedAverageEnabled() {
        XCTAssertEqual(BenchmarkMeasurementReducer.measuredRunCount(for: 1, usesTrimmedAverage: true), 3)
        XCTAssertEqual(BenchmarkMeasurementReducer.measuredRunCount(for: 3, usesTrimmedAverage: true), 5)
        XCTAssertEqual(BenchmarkMeasurementReducer.measuredRunCount(for: 9, usesTrimmedAverage: true), 11)
    }

    func testBenchmarkSelectedRunCountIsExactWhenTrimmedAverageDisabled() {
        XCTAssertEqual(BenchmarkMeasurementReducer.measuredRunCount(for: 1, usesTrimmedAverage: false), 1)
        XCTAssertEqual(BenchmarkMeasurementReducer.measuredRunCount(for: 3, usesTrimmedAverage: false), 3)
        XCTAssertEqual(BenchmarkMeasurementReducer.measuredRunCount(for: 9, usesTrimmedAverage: false), 9)
    }

    func testBenchmarkMeasurementReducerDropsExtremesAndAverages() {
        let summary = BenchmarkMeasurementReducer.summarize([
            BenchmarkRunMeasurement(megabytesPerSecond: 100, iops: 10, latencyMicroseconds: 50, bytesTransferred: 1_000),
            BenchmarkRunMeasurement(megabytesPerSecond: 200, iops: 20, latencyMicroseconds: 40, bytesTransferred: 2_000),
            BenchmarkRunMeasurement(megabytesPerSecond: 300, iops: 30, latencyMicroseconds: 30, bytesTransferred: 3_000),
            BenchmarkRunMeasurement(megabytesPerSecond: 400, iops: 40, latencyMicroseconds: 20, bytesTransferred: 4_000),
            BenchmarkRunMeasurement(megabytesPerSecond: 900, iops: 90, latencyMicroseconds: 10, bytesTransferred: 9_000)
        ], usesTrimmedAverage: true)

        XCTAssertEqual(summary.megabytesPerSecond, 300, accuracy: 0.001)
        XCTAssertEqual(summary.iops, 30, accuracy: 0.001)
        XCTAssertEqual(summary.latencyMicroseconds, 30, accuracy: 0.001)
        XCTAssertEqual(summary.bytesTransferred, 3_000)
    }

    func testBenchmarkMeasurementReducerAveragesAllRunsWhenTrimmedAverageDisabled() {
        let summary = BenchmarkMeasurementReducer.summarize([
            BenchmarkRunMeasurement(megabytesPerSecond: 100, iops: 10, latencyMicroseconds: 50, bytesTransferred: 1_000),
            BenchmarkRunMeasurement(megabytesPerSecond: 200, iops: 20, latencyMicroseconds: 40, bytesTransferred: 2_000),
            BenchmarkRunMeasurement(megabytesPerSecond: 900, iops: 90, latencyMicroseconds: 10, bytesTransferred: 9_000)
        ], usesTrimmedAverage: false)

        XCTAssertEqual(summary.megabytesPerSecond, 400, accuracy: 0.001)
        XCTAssertEqual(summary.iops, 40, accuracy: 0.001)
        XCTAssertEqual(summary.latencyMicroseconds, 100.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(summary.bytesTransferred, 4_000)
    }

    func testBenchmarkMeasurementReducerAveragesAsyncTransferAndFlushMetrics() {
        let summary = BenchmarkMeasurementReducer.summarize([
            BenchmarkRunMeasurement(megabytesPerSecond: 100, iops: 10, latencyMicroseconds: 50, bytesTransferred: 1_000, transferMegabytesPerSecond: 140, flushMilliseconds: 20),
            BenchmarkRunMeasurement(megabytesPerSecond: 200, iops: 20, latencyMicroseconds: 40, bytesTransferred: 2_000, transferMegabytesPerSecond: 260, flushMilliseconds: 40)
        ])

        XCTAssertEqual(summary.megabytesPerSecond, 150, accuracy: 0.001)
        XCTAssertEqual(summary.transferMegabytesPerSecond ?? 0, 200, accuracy: 0.001)
        XCTAssertEqual(summary.flushMilliseconds ?? 0, 30, accuracy: 0.001)
    }

    func testBenchmarkConfigurationDescriptionIsLocalized() {
        let english = AppLanguage.english.benchmarkConfigurationDescription(
            profile: .default,
            runs: 3,
            fileSizeBytes: BenchmarkProfile.defaultTestSize,
            dataPattern: .random,
            usesTrimmedAverage: true
        )
        let chinese = AppLanguage.simplifiedChinese.benchmarkConfigurationDescription(
            profile: .default,
            runs: 3,
            fileSizeBytes: BenchmarkProfile.defaultTestSize,
            dataPattern: .random,
            usesTrimmedAverage: true
        )
        let plainChinese = AppLanguage.simplifiedChinese.benchmarkConfigurationDescription(
            profile: .default,
            runs: 3,
            fileSizeBytes: BenchmarkProfile.defaultTestSize,
            dataPattern: .random,
            usesTrimmedAverage: false
        )
        let efficientChinese = AppLanguage.simplifiedChinese.benchmarkConfigurationDescription(
            profile: .default,
            runs: 3,
            fileSizeBytes: BenchmarkProfile.defaultTestSize,
            dataPattern: .random,
            usesTrimmedAverage: false,
            usesSmallBlockEfficiency: true,
            smallBlockFileSizePercent: 20
        )

        XCTAssertTrue(english.profileUse.contains("Default"))
        XCTAssertTrue(english.dataPattern.contains("Random"))
        XCTAssertTrue(english.runs.contains("5"))
        XCTAssertTrue(english.fileSize.contains("full file"))
        XCTAssertTrue(english.testTerms.contains("POSIX AIO"))
        XCTAssertTrue(english.testTerms.contains("fsync"))
        XCTAssertTrue(english.testTerms.contains("SEQ"))
        XCTAssertFalse(english.testTerms.contains("1 second"))
        XCTAssertFalse(english.testTerms.contains("5 seconds"))
        XCTAssertTrue(chinese.profileUse.contains("默认"))
        XCTAssertTrue(chinese.runs.contains("3"))
        XCTAssertTrue(chinese.runs.contains("5"))
        XCTAssertTrue(plainChinese.runs.contains("普通平均"))
        XCTAssertTrue(chinese.fileSize.contains("1 GiB"))
        XCTAssertTrue(chinese.fileSize.contains("完整"))
        XCTAssertTrue(chinese.dataPattern.contains("随机"))
        XCTAssertTrue(chinese.testTerms.contains("SEQ"))
        XCTAssertTrue(chinese.testTerms.contains("POSIX AIO"))
        XCTAssertTrue(chinese.testTerms.contains("刷盘"))
        XCTAssertFalse(chinese.testTerms.contains("间隔"))
        XCTAssertTrue(efficientChinese.fileSize.contains("4 KiB、16 KiB 和 64 KiB"))
        XCTAssertTrue(efficientChinese.fileSize.contains("20%"))

        let confirmation = AppLanguage.simplifiedChinese.benchmarkConfirmationConfiguration(
            profile: .default,
            runs: 3,
            fileSizeBytes: BenchmarkProfile.defaultTestSize,
            dataPattern: .random,
            usesTrimmedAverage: false,
            usesSmallBlockEfficiency: true,
            smallBlockFileSizePercent: 20
        )
        XCTAssertTrue(confirmation.contains("提高小块文件测试效率"))
        XCTAssertTrue(confirmation.contains("4/16/64 KiB 项目使用 20%"))

        let asyncCustomChinese = AppLanguage.simplifiedChinese.benchmarkConfigurationDescription(
            profile: BenchmarkProfile.custom(rows: BenchmarkCustomRow.defaultRows, engine: .asyncQueue),
            runs: 3,
            fileSizeBytes: BenchmarkProfile.defaultTestSize,
            dataPattern: .random,
            usesTrimmedAverage: false
        )
        XCTAssertEqual(AppLanguage.simplifiedChinese.profileName(.custom), "自定义")
        XCTAssertTrue(asyncCustomChinese.profileUse.contains("自定义"))
        XCTAssertTrue(asyncCustomChinese.testTerms.contains("POSIX AIO"))
        XCTAssertTrue(asyncCustomChinese.testTerms.contains("刷盘"))

        let customLoopChinese = AppLanguage.simplifiedChinese.benchmarkConfigurationDescription(
            profile: BenchmarkProfile.custom(
                rows: BenchmarkCustomRow.defaultRows,
                executionMode: .loopUntilCancelled
            ),
            runs: 9,
            fileSizeBytes: BenchmarkProfile.defaultTestSize,
            dataPattern: .random,
            usesTrimmedAverage: true
        )
        XCTAssertTrue(customLoopChinese.profileUse.contains("自定义"))
        XCTAssertTrue(customLoopChinese.runs.contains("持续运行"))
        XCTAssertTrue(customLoopChinese.runs.contains("最新完成"))
        XCTAssertTrue(customLoopChinese.testTerms.contains("自定义循环"))

        XCTAssertEqual(
            AppLanguage.simplifiedChinese.progressLabel("Loop 3 - SEQ1MiB Q8T1 Write"),
            "循环第 3 轮 - SEQ1MiB Q8T1 写入"
        )
    }

    func testBenchmarkStorageValidatorFiltersUnavailableFileSizes() {
        let options: [Int64] = [
            16 * 1_024 * 1_024,
            64 * 1_024 * 1_024,
            256 * 1_024 * 1_024
        ]
        let available = BenchmarkStorageValidator.requiredSpace(for: options[1])

        XCTAssertEqual(BenchmarkStorageValidator.availableFileSizeOptions(from: options, availableCapacity: available), [options[0], options[1]])
        XCTAssertEqual(BenchmarkStorageValidator.largestAvailableFileSize(from: options, availableCapacity: available), options[1])
        XCTAssertFalse(BenchmarkStorageValidator.isFileSizeAvailable(options[2], availableCapacity: available))
    }

    func testBenchmarkStorageValidatorCountsLoopReadPreparationFiles() {
        let readA = BenchmarkTest(
            id: "loop-read-a",
            label: "SEQ1M Q1T1",
            accessPattern: .sequential,
            operation: .read,
            blockSizeBytes: 4_096,
            queueDepth: 1,
            threads: 1,
            durationSeconds: 0.001,
            testSizeBytes: 16_384,
            dataPattern: .zeroFill,
            writePercentForMixed: 0
        )
        var readB = readA
        readB.id = "loop-read-b"
        readB.testSizeBytes = 32_768
        var write = readA
        write.id = "loop-write"
        write.operation = .write
        write.testSizeBytes = 65_536
        write.writePercentForMixed = 100
        let profile = BenchmarkProfile(
            id: "loop-space",
            name: "Loop Space",
            testFileSizeBytes: 65_536,
            runs: 1,
            executionMode: .loopUntilCancelled,
            tests: [readA, readB, write]
        )
        let required = Int64(16_384 + 32_768 + 65_536) + BenchmarkStorageValidator.safetyMarginBytes

        XCTAssertEqual(BenchmarkStorageValidator.requiredSpace(for: profile), required)
        XCTAssertFalse(BenchmarkStorageValidator.isRequiredSpaceAvailable(for: profile, availableCapacity: required - 1))
        XCTAssertTrue(BenchmarkStorageValidator.isRequiredSpaceAvailable(for: profile, availableCapacity: required))
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

        let results = try await NativeBenchmarkRunner(operationIntervalSeconds: 0, passIntervalSeconds: 0).run(profile: profile, drive: drive, volumePath: root.path, progress: { _ in }, result: { _ in })
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.bytesTransferred, 65_536)

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter {
            $0.hasPrefix("Capricorn-") || $0.hasPrefix(".dit-benchmark-")
        }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testBenchmarkRunnerPublishesEachRowReadThenWrite() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "unit", name: "Unit", mountPoint: root.path, sizeBytes: 1_000_000, isWritable: true, isSystem: false)
        ]
        let read = BenchmarkTest(
            id: "unit-read-a",
            label: "SEQ1M Q1T1",
            accessPattern: .sequential,
            operation: .read,
            blockSizeBytes: 4_096,
            queueDepth: 1,
            threads: 1,
            durationSeconds: 0.05,
            testSizeBytes: 65_536,
            dataPattern: .zeroFill,
            writePercentForMixed: 0
        )
        var write = read
        write.id = "unit-write-a"
        write.operation = .write
        write.writePercentForMixed = 100
        var readB = read
        readB.id = "unit-read-b"
        readB.label = "RND4K Q1T1"
        readB.accessPattern = .random
        var writeB = readB
        writeB.id = "unit-write-b"
        writeB.operation = .write
        writeB.writePercentForMixed = 100

        let profile = BenchmarkProfile(id: "unit", name: "Unit", testFileSizeBytes: 65_536, runs: 1, tests: [read, write, readB, writeB])
        let publishedTestIDs = LockedArray<String>()

        let results = try await NativeBenchmarkRunner(operationIntervalSeconds: 0, passIntervalSeconds: 0).run(profile: profile, drive: drive, volumePath: root.path, progress: { _ in }) { result in
            publishedTestIDs.append(result.testID)
        }

        XCTAssertEqual(results.map(\.testID), ["unit-read-a", "unit-write-a", "unit-read-b", "unit-write-b"])
        XCTAssertEqual(publishedTestIDs.snapshot, ["unit-read-a", "unit-write-a", "unit-read-b", "unit-write-b"])
        XCTAssertTrue(results.allSatisfy { $0.bytesTransferred == 65_536 })
    }

    func testBenchmarkRunnerUsesUniqueFilesForWritePasses() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "unit", name: "Unit", mountPoint: root.path, sizeBytes: 1_000_000, isWritable: true, isSystem: false)
        ]
        let write = BenchmarkTest(
            id: "unit-write",
            label: "SEQ1M Q1T1",
            accessPattern: .sequential,
            operation: .write,
            blockSizeBytes: 4_096,
            queueDepth: 1,
            threads: 1,
            durationSeconds: 0.05,
            testSizeBytes: 32_768,
            dataPattern: .random,
            writePercentForMixed: 100
        )
        let profile = BenchmarkProfile(id: "unit", name: "Unit", testFileSizeBytes: 32_768, runs: 1, tests: [write])
        let createdNames = LockedArray<String>()
        let runner = NativeBenchmarkRunner(operationIntervalSeconds: 0, passIntervalSeconds: 0, fileEventHandler: { url in
            createdNames.append(url.lastPathComponent)
        })

        _ = try await runner.run(profile: profile, drive: drive, volumePath: root.path, progress: { _ in }, result: { _ in })

        let names = createdNames.snapshot
        XCTAssertEqual(names.count, 2)
        XCTAssertEqual(Set(names).count, 2)
        XCTAssertTrue(names.allSatisfy { $0.hasPrefix("Capricorn-") })
        XCTAssertTrue(names.allSatisfy { $0.contains("write-run") })
    }

    func testBenchmarkRunnerReusesPreparedFileForReadPasses() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "unit", name: "Unit", mountPoint: root.path, sizeBytes: 1_000_000, isWritable: true, isSystem: false)
        ]
        let read = BenchmarkTest(
            id: "unit-read",
            label: "SEQ4K Q1T1",
            accessPattern: .sequential,
            operation: .read,
            blockSizeBytes: 4_096,
            queueDepth: 1,
            threads: 1,
            durationSeconds: 0.001,
            testSizeBytes: 32_768,
            dataPattern: .zeroFill,
            writePercentForMixed: 0
        )
        let profile = BenchmarkProfile(id: "unit", name: "Unit", testFileSizeBytes: 32_768, runs: 3, tests: [read])
        let createdNames = LockedArray<String>()
        let runner = NativeBenchmarkRunner(operationIntervalSeconds: 0, passIntervalSeconds: 0, fileEventHandler: { url in
            createdNames.append(url.lastPathComponent)
        })

        let results = try await runner.run(profile: profile, drive: drive, volumePath: root.path, progress: { _ in }, result: { _ in })

        let names = createdNames.snapshot
        XCTAssertEqual(results.first?.bytesTransferred, 32_768)
        XCTAssertEqual(names.count, 1)
        XCTAssertTrue(names.first?.contains("read-run0") == true)

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter {
            $0.hasPrefix("Capricorn-") || $0.hasPrefix(".dit-benchmark-")
        }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testBenchmarkRunnerReusesReadFileButKeepsWriteAndMixedFilesPerPass() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "unit", name: "Unit", mountPoint: root.path, sizeBytes: 1_000_000, isWritable: true, isSystem: false)
        ]
        let read = BenchmarkTest(
            id: "unit-read",
            label: "SEQ4K Q1T1",
            accessPattern: .sequential,
            operation: .read,
            blockSizeBytes: 4_096,
            queueDepth: 1,
            threads: 1,
            durationSeconds: 0.001,
            testSizeBytes: 8_192,
            dataPattern: .zeroFill,
            writePercentForMixed: 0
        )
        var write = read
        write.id = "unit-write"
        write.operation = .write
        write.writePercentForMixed = 100
        var mixed = read
        mixed.id = "unit-mixed"
        mixed.operation = .mixed
        mixed.writePercentForMixed = 30
        let profile = BenchmarkProfile(id: "unit", name: "Unit", testFileSizeBytes: 8_192, runs: 2, tests: [read, write, mixed])
        let createdNames = LockedArray<String>()
        let runner = NativeBenchmarkRunner(operationIntervalSeconds: 0, passIntervalSeconds: 0, fileEventHandler: { url in
            createdNames.append(url.lastPathComponent)
        })

        let results = try await runner.run(profile: profile, drive: drive, volumePath: root.path, progress: { _ in }, result: { _ in })

        let names = createdNames.snapshot
        XCTAssertEqual(results.map(\.testID), ["unit-read", "unit-write", "unit-mixed"])
        XCTAssertEqual(names.filter { $0.contains("-read-run") }.count, 1)
        XCTAssertEqual(names.filter { $0.contains("-write-run") }.count, 3)
        XCTAssertEqual(names.filter { $0.contains("-mixed-run") }.count, 3)
    }

    func testAsyncQueueBenchmarkRunnerPublishesTransferAndFlushMetrics() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "unit", name: "Unit", mountPoint: root.path, sizeBytes: 1_000_000, isWritable: true, isSystem: false)
        ]
        let write = BenchmarkTest(
            id: "async-write",
            label: "SEQ4K Q2T1",
            accessPattern: .sequential,
            operation: .write,
            blockSizeBytes: 4_096,
            queueDepth: 2,
            threads: 1,
            durationSeconds: 0.001,
            testSizeBytes: 65_536,
            dataPattern: .zeroFill,
            writePercentForMixed: 100
        )
        let profile = BenchmarkProfile(
            id: "async-unit",
            name: "Async Unit",
            testFileSizeBytes: 65_536,
            runs: 1,
            engine: .asyncQueue,
            tests: [write]
        )
        let published = LockedArray<BenchmarkResult>()
        let runner = AsyncQueueBenchmarkRunner(operationIntervalSeconds: 0, passIntervalSeconds: 0)

        let results = try await runner.run(profile: profile, drive: drive, volumePath: root.path, progress: { _ in }) { result in
            published.append(result)
        }

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(published.snapshot.count, 1)
        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(result.bytesTransferred, 65_536)
        XCTAssertNotNil(result.transferMegabytesPerSecond)
        XCTAssertNotNil(result.flushMilliseconds)
        XCTAssertGreaterThanOrEqual(result.transferMegabytesPerSecond ?? 0, result.bestMegabytesPerSecond)

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter {
            $0.hasPrefix("Capricorn-") || $0.hasPrefix(".dit-benchmark-")
        }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testAsyncQueueBenchmarkRunnerReusesPreparedFileForReadPasses() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "unit", name: "Unit", mountPoint: root.path, sizeBytes: 1_000_000, isWritable: true, isSystem: false)
        ]
        let read = BenchmarkTest(
            id: "async-read",
            label: "SEQ4K Q2T1",
            accessPattern: .sequential,
            operation: .read,
            blockSizeBytes: 4_096,
            queueDepth: 2,
            threads: 1,
            durationSeconds: 0.001,
            testSizeBytes: 65_536,
            dataPattern: .zeroFill,
            writePercentForMixed: 0
        )
        let profile = BenchmarkProfile(
            id: "async-unit",
            name: "Async Unit",
            testFileSizeBytes: 65_536,
            runs: 2,
            engine: .asyncQueue,
            tests: [read]
        )
        let createdNames = LockedArray<String>()
        let runner = AsyncQueueBenchmarkRunner(operationIntervalSeconds: 0, passIntervalSeconds: 0, fileEventHandler: { url in
            createdNames.append(url.lastPathComponent)
        })

        let results = try await runner.run(profile: profile, drive: drive, volumePath: root.path, progress: { _ in }, result: { _ in })

        let names = createdNames.snapshot
        XCTAssertEqual(results.first?.bytesTransferred, 65_536)
        XCTAssertEqual(names.count, 1)
        XCTAssertTrue(names.first?.contains("read-run0") == true)
    }

    func testAsyncQueueBenchmarkRunnerLoopPublishesLatestPassAndStopsWithoutWaiting() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "unit", name: "Unit", mountPoint: root.path, sizeBytes: 1_000_000, isWritable: true, isSystem: false)
        ]
        let read = BenchmarkTest(
            id: "async-loop-read",
            label: "SEQ4K Q2T1",
            accessPattern: .sequential,
            operation: .read,
            blockSizeBytes: 4_096,
            queueDepth: 2,
            threads: 1,
            durationSeconds: 0.001,
            testSizeBytes: 8_192,
            dataPattern: .zeroFill,
            writePercentForMixed: 0
        )
        var write = read
        write.id = "async-loop-write"
        write.operation = .write
        write.writePercentForMixed = 100
        let profile = BenchmarkProfile(
            id: "async-loop-unit",
            name: "Async Loop Unit",
            testFileSizeBytes: 8_192,
            runs: 9,
            executionMode: .loopUntilCancelled,
            engine: .asyncQueue,
            tests: [read, write]
        )

        let requestedWaits = LockedArray<TimeInterval>()
        let published = LockedArray<BenchmarkResult>()
        let createdNames = LockedArray<String>()
        let runner = AsyncQueueBenchmarkRunner(
            operationIntervalSeconds: 5,
            passIntervalSeconds: 1,
            operationSleeper: { seconds, _ in
                requestedWaits.append(seconds)
            },
            fileEventHandler: { url in
                createdNames.append(url.lastPathComponent)
            }
        )

        let results = try await runner.run(profile: profile, drive: drive, volumePath: root.path, progress: { _ in }) { result in
            published.append(result)
            let shouldCancel = published.snapshot.count == 4
            if shouldCancel {
                runner.cancel()
            }
        }

        let waits = requestedWaits.snapshot
        let publishedIDs = published.snapshot.map(\.testID)
        let names = createdNames.snapshot

        let expectedCycle = ["async-loop-read", "async-loop-write"]
        XCTAssertEqual(publishedIDs, expectedCycle + expectedCycle)
        XCTAssertEqual(results.map(\.testID), expectedCycle)
        XCTAssertTrue(results.allSatisfy { $0.bytesTransferred == 8_192 })
        XCTAssertTrue(waits.isEmpty)
        XCTAssertEqual(names.filter { $0.contains("-read-run") }.count, 1)
        XCTAssertEqual(names.filter { $0.contains("-write-run") }.count, 2)

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter {
            $0.hasPrefix("Capricorn-") || $0.hasPrefix(".dit-benchmark-")
        }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testBenchmarkRunnerIgnoresFixedDurationAndTransfersCompleteFile() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "unit", name: "Unit", mountPoint: root.path, sizeBytes: 1_000_000, isWritable: true, isSystem: false)
        ]
        let read = BenchmarkTest(
            id: "unit-read",
            label: "SEQ4K Q1T1",
            accessPattern: .sequential,
            operation: .read,
            blockSizeBytes: 4_096,
            queueDepth: 1,
            threads: 1,
            durationSeconds: 0.001,
            testSizeBytes: 131_072,
            dataPattern: .zeroFill,
            writePercentForMixed: 0
        )
        let profile = BenchmarkProfile(id: "unit", name: "Unit", testFileSizeBytes: 131_072, runs: 1, tests: [read])

        let results = try await NativeBenchmarkRunner(operationIntervalSeconds: 0, passIntervalSeconds: 0).run(profile: profile, drive: drive, volumePath: root.path, progress: { _ in }, result: { _ in })

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.bytesTransferred, 131_072)
    }

    func testBenchmarkRunnerRequestsIntervalBetweenScoredTests() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "unit", name: "Unit", mountPoint: root.path, sizeBytes: 1_000_000, isWritable: true, isSystem: false)
        ]
        let read = BenchmarkTest(
            id: "unit-read",
            label: "SEQ4K Q1T1",
            accessPattern: .sequential,
            operation: .read,
            blockSizeBytes: 4_096,
            queueDepth: 1,
            threads: 1,
            durationSeconds: 0.001,
            testSizeBytes: 8_192,
            dataPattern: .zeroFill,
            writePercentForMixed: 0
        )
        var write = read
        write.id = "unit-write"
        write.operation = .write
        write.writePercentForMixed = 100
        let profile = BenchmarkProfile(id: "unit", name: "Unit", testFileSizeBytes: 8_192, runs: 1, tests: [read, write])
        let requestedWaits = LockedArray<TimeInterval>()
        let runner = NativeBenchmarkRunner(operationIntervalSeconds: 5, passIntervalSeconds: 0) { seconds, isCancelled in
            XCTAssertFalse(isCancelled())
            requestedWaits.append(seconds)
        }

        _ = try await runner.run(profile: profile, drive: drive, volumePath: root.path, progress: { _ in }, result: { _ in })

        let waits = requestedWaits.snapshot
        XCTAssertEqual(waits, [5])
    }

    func testBenchmarkRunnerRequestsOneSecondBetweenPasses() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "unit", name: "Unit", mountPoint: root.path, sizeBytes: 1_000_000, isWritable: true, isSystem: false)
        ]
        let write = BenchmarkTest(
            id: "unit-write",
            label: "SEQ4K Q1T1",
            accessPattern: .sequential,
            operation: .write,
            blockSizeBytes: 4_096,
            queueDepth: 1,
            threads: 1,
            durationSeconds: 0.001,
            testSizeBytes: 8_192,
            dataPattern: .zeroFill,
            writePercentForMixed: 100
        )
        let profile = BenchmarkProfile(id: "unit", name: "Unit", testFileSizeBytes: 8_192, runs: 1, tests: [write])
        let requestedWaits = LockedArray<TimeInterval>()
        let runner = NativeBenchmarkRunner(operationIntervalSeconds: 0, passIntervalSeconds: 1) { seconds, isCancelled in
            XCTAssertFalse(isCancelled())
            requestedWaits.append(seconds)
        }

        _ = try await runner.run(profile: profile, drive: drive, volumePath: root.path, progress: { _ in }, result: { _ in })

        let waits = requestedWaits.snapshot
        XCTAssertEqual(waits, [1])
    }

    func testBenchmarkLoopRunnerPublishesLatestPassAndStopsWithoutWaiting() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var drive = Self.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "unit", name: "Unit", mountPoint: root.path, sizeBytes: 1_000_000, isWritable: true, isSystem: false)
        ]
        let readQ1 = BenchmarkTest(
            id: "loop-read-q1",
            label: "SEQ1M Q1T1",
            accessPattern: .sequential,
            operation: .read,
            blockSizeBytes: 4_096,
            queueDepth: 1,
            threads: 1,
            durationSeconds: 0.001,
            testSizeBytes: 8_192,
            dataPattern: .zeroFill,
            writePercentForMixed: 0
        )
        var writeQ1 = readQ1
        writeQ1.id = "loop-write-q1"
        writeQ1.operation = .write
        writeQ1.writePercentForMixed = 100
        var readQ8 = readQ1
        readQ8.id = "loop-read-q8"
        readQ8.label = "SEQ1M Q8T1"
        readQ8.queueDepth = 8
        var writeQ8 = readQ8
        writeQ8.id = "loop-write-q8"
        writeQ8.operation = .write
        writeQ8.writePercentForMixed = 100
        let profile = BenchmarkProfile(
            id: "unit-loop",
            name: "Unit Loop",
            testFileSizeBytes: 8_192,
            runs: 9,
            usesTrimmedAverage: true,
            executionMode: .loopUntilCancelled,
            tests: [readQ1, writeQ1, readQ8, writeQ8]
        )

        let requestedWaits = LockedArray<TimeInterval>()
        let published = LockedArray<BenchmarkResult>()
        let createdNames = LockedArray<String>()
        let runner = NativeBenchmarkRunner(
            operationIntervalSeconds: 5,
            passIntervalSeconds: 1,
            operationSleeper: { seconds, _ in
                requestedWaits.append(seconds)
            },
            fileEventHandler: { url in
                createdNames.append(url.lastPathComponent)
            }
        )

        let results = try await runner.run(profile: profile, drive: drive, volumePath: root.path, progress: { _ in }) { result in
            published.append(result)
            let shouldCancel = published.snapshot.count == 8
            if shouldCancel {
                runner.cancel()
            }
        }

        let waits = requestedWaits.snapshot
        let publishedIDs = published.snapshot.map(\.testID)
        let names = createdNames.snapshot

        let expectedCycle = ["loop-read-q1", "loop-write-q1", "loop-read-q8", "loop-write-q8"]
        XCTAssertEqual(publishedIDs, expectedCycle + expectedCycle)
        XCTAssertEqual(results.map(\.testID), expectedCycle)
        XCTAssertTrue(results.allSatisfy { $0.bytesTransferred == 8_192 })
        XCTAssertTrue(waits.isEmpty)
        XCTAssertEqual(names.filter { $0.contains("-read-run") }.count, 2)
        XCTAssertEqual(names.filter { $0.contains("-write-run") }.count, 4)

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter {
            $0.hasPrefix("Capricorn-") || $0.hasPrefix(".dit-benchmark-")
        }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testHistoryVisibilitySeparatesVisibleAndHiddenSmartRecords() {
        let drive = Self.fixtureDrive()
        let snapshot = Self.fixtureSnapshot(for: drive)
        let visible = SmartHistoryRecord(drive: drive, snapshot: snapshot)
        let hidden = SmartHistoryRecord(drive: drive, snapshot: snapshot)

        HistoryVisibility.hide(hidden, at: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(HistoryVisibility.visible([visible, hidden]).map(\.id), [visible.id])
        XCTAssertEqual(HistoryVisibility.hidden([visible, hidden]).map(\.id), [hidden.id])
        XCTAssertNil(visible.hiddenAt)
        XCTAssertNotNil(hidden.hiddenAt)
    }

    func testHistoryVisibilitySeparatesVisibleAndHiddenBenchmarkRecords() {
        let drive = Self.fixtureDrive()
        let visible = BenchmarkHistoryRecord(drive: drive, result: Self.fixtureBenchmarkResult(for: drive))
        let hidden = BenchmarkHistoryRecord(drive: drive, result: Self.fixtureBenchmarkResult(for: drive))

        HistoryVisibility.hide(hidden, at: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(HistoryVisibility.visible([visible, hidden]).map(\.id), [visible.id])
        XCTAssertEqual(HistoryVisibility.hidden([visible, hidden]).map(\.id), [hidden.id])
    }

    func testHistoryVisibilitySeparatesVisibleAndHiddenActivityRecords() {
        let drive = Self.fixtureDrive()
        let visible = Self.fixtureActivityRecord(for: drive)
        let hidden = Self.fixtureActivityRecord(for: drive)

        HistoryVisibility.hide(hidden, at: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(HistoryVisibility.visible([visible, hidden]).map(\.id), [visible.id])
        XCTAssertEqual(HistoryVisibility.hidden([visible, hidden]).map(\.id), [hidden.id])
    }

    func testHistoryVisibilityRestoresSingleRecord() {
        let drive = Self.fixtureDrive()
        let record = SmartHistoryRecord(drive: drive, snapshot: Self.fixtureSnapshot(for: drive))

        HistoryVisibility.hide(record, at: Date(timeIntervalSince1970: 1))
        HistoryVisibility.restore(record)

        XCTAssertNil(record.hiddenAt)
        XCTAssertEqual(HistoryVisibility.visible([record]).map(\.id), [record.id])
    }

    func testHistoryVisibilityRestoreAllCanLimitToCurrentDrive() {
        let drive = Self.fixtureDrive()
        var otherDrive = drive
        otherDrive.bsdName = "disk9"
        let currentDriveRecord = SmartHistoryRecord(drive: drive, snapshot: Self.fixtureSnapshot(for: drive))
        let otherDriveRecord = SmartHistoryRecord(drive: otherDrive, snapshot: Self.fixtureSnapshot(for: otherDrive))

        HistoryVisibility.hide(currentDriveRecord, at: Date(timeIntervalSince1970: 1))
        HistoryVisibility.hide(otherDriveRecord, at: Date(timeIntervalSince1970: 2))
        HistoryVisibility.restoreAll([currentDriveRecord, otherDriveRecord], driveID: drive.id)

        XCTAssertNil(currentDriveRecord.hiddenAt)
        XCTAssertNotNil(otherDriveRecord.hiddenAt)
    }

    func testHistoryVisibilityHideAllCanLimitToCurrentDrive() {
        let drive = Self.fixtureDrive()
        var otherDrive = drive
        otherDrive.bsdName = "disk9"
        let currentDriveRecord = SmartHistoryRecord(drive: drive, snapshot: Self.fixtureSnapshot(for: drive))
        let otherDriveRecord = SmartHistoryRecord(drive: otherDrive, snapshot: Self.fixtureSnapshot(for: otherDrive))

        HistoryVisibility.hideAll([currentDriveRecord, otherDriveRecord], at: Date(timeIntervalSince1970: 1), driveID: drive.id)

        XCTAssertNotNil(currentDriveRecord.hiddenAt)
        XCTAssertNil(otherDriveRecord.hiddenAt)
        XCTAssertEqual(HistoryVisibility.visible([currentDriveRecord, otherDriveRecord]).map(\.id), [otherDriveRecord.id])
        XCTAssertEqual(HistoryVisibility.hidden([currentDriveRecord, otherDriveRecord]).map(\.id), [currentDriveRecord.id])
    }



    static func fixtureDrive() -> DriveDevice {
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

    static func externalCatalogDrive(model: String, protocolName: String = "USB") -> DriveDevice {
        DriveDevice(
            bsdName: "disk99",
            deviceNode: "/dev/disk99",
            displayName: model,
            mediaName: model,
            protocolName: protocolName,
            sizeBytes: 8_000_000_000_000,
            blockSize: 512,
            isInternal: false,
            isRemovable: true,
            isSolidState: false,
            isWritable: true,
            isVirtual: false,
            isSystemDisk: false,
            smartStatusRaw: "Verified",
            nativeSmartKeys: [:],
            volumes: [],
            model: model,
            serialNumber: "CATALOG"
        )
    }

    static func fixtureDrive(mountedAt mountPoint: String) -> DriveDevice {
        var drive = fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "unit", name: "Unit", mountPoint: mountPoint, sizeBytes: 1_000_000_000, isWritable: true, isSystem: false)
        ]
        return drive
    }

    static func fixtureSnapshot(for drive: DriveDevice) -> SmartSnapshot {
        SmartSnapshot(
            driveID: drive.id,
            capturedAt: Date(timeIntervalSince1970: 1_000),
            health: .good,
            summary: "OK",
            providerStatuses: [ProviderStatus(name: "Fixture", state: .available, message: "OK")],
            attributes: [],
            temperatureCelsius: 32,
            lifeRemainingPercent: 98,
            powerOnHours: 120,
            powerCycleCount: 4,
            mediaErrors: 0,
            unsafeShutdowns: 0,
            smartStatusRaw: "Verified",
            selfTestStatus: nil
        )
    }

    static func fixtureBenchmarkResult(for drive: DriveDevice) -> BenchmarkResult {
        BenchmarkResult(
            driveID: drive.id,
            volumePath: "/tmp",
            profileID: "unit",
            profileName: "Unit",
            testID: "unit-read",
            testLabel: "SEQ1M Q1T1",
            operation: .read,
            measuredAt: Date(timeIntervalSince1970: 1_000),
            bestMegabytesPerSecond: 1_234.5,
            iops: 100,
            latencyMicroseconds: 10,
            bytesTransferred: 65_536
        )
    }

    @MainActor
    static func createLegacyHistoryStore(at url: URL, drive: DriveDevice) throws {
        let schema = Schema([
            SmartHistoryRecord.self,
            BenchmarkHistoryRecord.self,
            DiskActivityHistoryRecord.self,
            AppSettingsRecord.self
        ])
        let configuration = ModelConfiguration(
            "LegacyCapricorn",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let snapshot = fixtureSnapshot(for: drive)
        let benchmark = fixtureBenchmarkResult(for: drive)
        let sample = DiskActivitySample(timestamp: Date(), readMegabytesPerSecond: 1, writeMegabytesPerSecond: 2)
        context.insert(SmartHistoryRecord(drive: drive, snapshot: snapshot))
        context.insert(BenchmarkHistoryRecord(drive: drive, result: benchmark, activitySamples: [sample]))
        context.insert(DiskActivityHistoryRecord(
            drive: drive,
            samples: [sample],
            sampleInterval: DiskActivitySampleInterval.default,
            startedAt: sample.timestamp,
            endedAt: sample.timestamp.addingTimeInterval(1)
        ))
        try context.save()
    }

    private static func fixtureActivityRecord(for drive: DriveDevice) -> DiskActivityHistoryRecord {
        let start = Date(timeIntervalSince1970: 1_000)
        return DiskActivityHistoryRecord(
            drive: drive,
            samples: [
                DiskActivitySample(timestamp: start, readMegabytesPerSecond: 1, writeMegabytesPerSecond: 2),
                DiskActivitySample(timestamp: start.addingTimeInterval(1), readMegabytesPerSecond: 3, writeMegabytesPerSecond: 4)
            ],
            sampleInterval: .half,
            startedAt: start,
            endedAt: start.addingTimeInterval(1)
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

    private static let diskutilExternalPartitionListFixture = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>WholeDisks</key><array><string>disk11</string></array>
      <key>AllDisksAndPartitions</key><array>
        <dict>
          <key>Content</key><string>GUID_partition_scheme</string>
          <key>DeviceIdentifier</key><string>disk11</string>
          <key>Partitions</key><array>
            <dict>
              <key>DeviceIdentifier</key><string>disk11s1</string>
              <key>Content</key><string>Microsoft Basic Data</string>
              <key>FilesystemName</key><string>NTFS</string>
              <key>VolumeName</key><string>40G4T_NTFS_E</string>
              <key>MountPoint</key><string>/Volumes/40G4T_NTFS_E</string>
              <key>Size</key><integer>4096000000000</integer>
              <key>ReadOnly</key><false/>
            </dict>
          </array>
          <key>Size</key><integer>4096000000000</integer>
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

    private static let disk11InfoFixture = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>BusProtocol</key><string>PCI-Express</string>
      <key>Content</key><string>GUID_partition_scheme</string>
      <key>DeviceBlockSize</key><integer>512</integer>
      <key>DeviceIdentifier</key><string>disk11</string>
      <key>DeviceNode</key><string>/dev/disk11</string>
      <key>IORegistryEntryName</key><string>GeIL P4S 4TB</string>
      <key>Internal</key><false/>
      <key>MediaName</key><string>GeIL P4S 4TB</string>
      <key>Removable</key><false/>
      <key>SMARTStatus</key><string>Verified</string>
      <key>SolidState</key><true/>
      <key>TotalSize</key><integer>4096000000000</integer>
      <key>VirtualOrPhysical</key><string>Physical</string>
      <key>WholeDisk</key><true/>
      <key>WritableMedia</key><true/>
    </dict></plist>
    """

    private static let sdxcInfoFixture = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>BusProtocol</key><string>Secure Digital</string>
      <key>Content</key><string>FDisk_partition_scheme</string>
      <key>DeviceBlockSize</key><integer>512</integer>
      <key>DeviceIdentifier</key><string>disk10</string>
      <key>DeviceNode</key><string>/dev/disk10</string>
      <key>IORegistryEntryName</key><string>Built In SDXC Reader</string>
      <key>Internal</key><true/>
      <key>MediaName</key><string>Built In SDXC Reader</string>
      <key>Removable</key><true/>
      <key>SMARTStatus</key><string>Verified</string>
      <key>SolidState</key><false/>
      <key>TotalSize</key><integer>255865241600</integer>
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

    private static let smartctlATASelfTestFixture = """
    {
      "smartctl": {"exit_status": 0},
      "smart_status": {"passed": true},
      "ata_smart_self_test_log": {
        "standard": {
          "revision": 1,
          "table": [
            {
              "type": {"value": 1, "string": "Short offline", "short": "Short"},
              "status": {"value": 0, "string": "Completed without error", "passed": true},
              "lifetime_hours": 123,
              "lba": 0
            },
            {
              "type": {"value": 2, "string": "Extended offline", "short": "Extended"},
              "status": {"value": 5, "string": "Completed: read failure", "passed": false},
              "lifetime_hours": 122,
              "lba": 987654
            }
          ]
        }
      }
    }
    """

    private static let smartctlNVMeSelfTestFixture = """
    {
      "smartctl": {"exit_status": 0},
      "smart_status": {"passed": true},
      "nvme_self_test_log": {
        "current_self_test_operation": "No self-test in progress",
        "self_test_results": [
          {
            "test_type": "Extended",
            "status": "Completed without error",
            "passed": true,
            "lifetime_hours": 456
          }
        ]
      }
    }
    """

    private static let smartctlNVMeCapabilityFixture = """
    {
      "smartctl": {"exit_status": 0},
      "device": {"type": "nvme", "protocol": "NVMe"},
      "nvme_optional_admin_commands": {"value": 16, "self_test": true}
    }
    """

    private static let smartctlATACapabilityFixture = """
    {
      "smartctl": {"exit_status": 0},
      "device": {"type": "sat", "protocol": "ATA"},
      "ata_smart_data": {
        "self_test": {
          "polling_minutes": {"short": 2, "extended": 30}
        }
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

private final class LockedArray<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Element] = []

    var snapshot: [Element] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    func append(_ value: Element) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }
}

private struct StaticCommandRunner: CommandRunning {
    var stdout: String
    var stderr: String = ""
    var terminationStatus: Int32 = 0

    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        CommandResult(
            stdout: Data(stdout.utf8),
            stderr: Data(stderr.utf8),
            terminationStatus: terminationStatus
        )
    }
}

private struct StaticSmartctlTargetResolver: SmartctlIOServiceTargetResolving {
    var descriptor: SmartctlTargetDescriptor?

    func targetDescriptor(for drive: DriveDevice) -> SmartctlTargetDescriptor? {
        descriptor
    }
}

private final class SequencedCommandRunner: CommandRunning, @unchecked Sendable {
    struct Call: Equatable {
        var executable: String
        var arguments: [String]
    }

    private let lock = NSLock()
    private var recordedCalls: [Call] = []
    private var results: [CommandResult]

    init(results: [CommandResult]) {
        self.results = results
    }

    var calls: [Call] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCalls
    }

    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        lock.lock()
        recordedCalls.append(Call(executable: executable, arguments: arguments))
        let result = results.isEmpty
            ? CommandResult(stdout: Data(), stderr: Data(), terminationStatus: 0)
            : results.removeFirst()
        lock.unlock()
        return result
    }
}

private final class RecordingCommandRunner: CommandRunning, @unchecked Sendable {
    struct Call: Equatable {
        var executable: String
        var arguments: [String]
    }

    private let recordedCalls = LockedArray<Call>()
    private let stdout: String
    private let stderr: String
    private let terminationStatus: Int32

    init(stdout: String = "", stderr: String = "", terminationStatus: Int32 = 0) {
        self.stdout = stdout
        self.stderr = stderr
        self.terminationStatus = terminationStatus
    }

    var calls: [Call] {
        recordedCalls.snapshot
    }

    func run(_ executable: String, arguments: [String]) async throws -> CommandResult {
        recordedCalls.append(Call(executable: executable, arguments: arguments))
        return CommandResult(
            stdout: Data(stdout.utf8),
            stderr: Data(stderr.utf8),
            terminationStatus: terminationStatus
        )
    }
}

private final class RecordingDiskCheckRunner: DiskCheckCommandRunning, @unchecked Sendable {
    private let recordedCalls = LockedArray<RecordingCommandRunner.Call>()
    private let stdout: String
    private let stderr: String
    private let terminationStatus: Int32
    private(set) var didCancel = false

    init(stdout: String = "", stderr: String = "", terminationStatus: Int32 = 0) {
        self.stdout = stdout
        self.stderr = stderr
        self.terminationStatus = terminationStatus
    }

    var calls: [RecordingCommandRunner.Call] {
        recordedCalls.snapshot
    }

    func run(
        _ executable: String,
        arguments: [String],
        stdout onStdout: @escaping @Sendable (String) -> Void,
        stderr onStderr: @escaping @Sendable (String) -> Void
    ) async throws -> CommandResult {
        recordedCalls.append(RecordingCommandRunner.Call(executable: executable, arguments: arguments))

        if !stdout.isEmpty {
            onStdout(stdout)
        }
        if !stderr.isEmpty {
            onStderr(stderr)
        }

        return CommandResult(
            stdout: Data(stdout.utf8),
            stderr: Data(stderr.utf8),
            terminationStatus: terminationStatus
        )
    }

    func cancel() {
        didCancel = true
    }
}

private final class DelayedDiskCheckRunner: DiskCheckCommandRunning, @unchecked Sendable {
    private let recordedCalls = LockedArray<RecordingCommandRunner.Call>()
    private let stdout: String
    private let stderr: String
    private let delayNanoseconds: UInt64
    private(set) var didCancel = false

    init(stdout: String, stderr: String = "", delayNanoseconds: UInt64) {
        self.stdout = stdout
        self.stderr = stderr
        self.delayNanoseconds = delayNanoseconds
    }

    var calls: [RecordingCommandRunner.Call] {
        recordedCalls.snapshot
    }

    func run(
        _ executable: String,
        arguments: [String],
        stdout onStdout: @escaping @Sendable (String) -> Void,
        stderr onStderr: @escaping @Sendable (String) -> Void
    ) async throws -> CommandResult {
        recordedCalls.append(RecordingCommandRunner.Call(executable: executable, arguments: arguments))

        onStdout(stdout)
        if !stderr.isEmpty {
            onStderr(stderr)
        }
        try? await Task.sleep(nanoseconds: delayNanoseconds)

        return CommandResult(
            stdout: Data(stdout.utf8),
            stderr: Data(stderr.utf8),
            terminationStatus: 0
        )
    }

    func cancel() {
        didCancel = true
    }
}

private final class LateCallbackBenchmarkRunner: BenchmarkRunning, @unchecked Sendable {
    private let events = LockedArray<String>()
    private let cancellationGate = AsyncGate()
    private let lock = NSLock()
    private var storedCancelCount = 0

    var cancelCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCancelCount
    }

    func run(
        profile: BenchmarkProfile,
        drive: DriveDevice,
        volumePath: String,
        progress: @escaping @Sendable (BenchmarkProgress) -> Void,
        result: @escaping @Sendable (BenchmarkResult) -> Void
    ) async throws -> [BenchmarkResult] {
        events.append("started")
        await cancellationGate.wait()

        let lateResult = BenchmarkResult(
            driveID: drive.id,
            volumePath: volumePath,
            profileID: profile.id,
            profileName: profile.name,
            testID: "late-read",
            testLabel: "SEQ1M Q1T1",
            operation: .read,
            measuredAt: Date(timeIntervalSince1970: 1_000),
            bestMegabytesPerSecond: 9_999,
            iops: 100,
            latencyMicroseconds: 10,
            bytesTransferred: 1_048_576
        )
        progress(BenchmarkProgress(currentTestLabel: "Late", completed: 1, total: 1, message: "Late callback"))
        result(lateResult)
        events.append("finished")
        return [lateResult]
    }

    func cancel() {
        lock.lock()
        storedCancelCount += 1
        lock.unlock()
        events.append("cancelled")
        cancellationGate.open()
    }

    func waitUntilStarted() async -> Bool {
        await waitForEvent("started")
    }

    func waitUntilFinished() async -> Bool {
        await waitForEvent("finished")
    }

    private func waitForEvent(_ event: String) async -> Bool {
        for _ in 0..<300 {
            if events.snapshot.contains(event) {
                return true
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }
}

private final class ImmediateBenchmarkRunner: BenchmarkRunning, @unchecked Sendable {
    private let profiles = LockedState<[BenchmarkProfile]>([])

    var receivedProfiles: [BenchmarkProfile] {
        profiles.snapshot()
    }

    var runCount: Int {
        receivedProfiles.count
    }

    func run(
        profile: BenchmarkProfile,
        drive: DriveDevice,
        volumePath: String,
        progress: @escaping @Sendable (BenchmarkProgress) -> Void,
        result: @escaping @Sendable (BenchmarkResult) -> Void
    ) async throws -> [BenchmarkResult] {
        profiles.withLock { $0.append(profile) }
        let results = profile.tests.enumerated().map { index, test in
            BenchmarkResult(
                driveID: drive.id,
                volumePath: volumePath,
                profileID: profile.id,
                profileName: profile.name,
                testID: test.id,
                testLabel: test.label,
                operation: test.operation,
                measuredAt: Date(timeIntervalSince1970: Double(10_000 + index)),
                bestMegabytesPerSecond: Double(1_000 + index),
                iops: 100,
                latencyMicroseconds: 10,
                bytesTransferred: test.testSizeBytes
            )
        }
        results.forEach(result)
        progress(BenchmarkProgress(
            currentTestLabel: "Complete",
            completed: results.count,
            total: results.count,
            message: "Benchmark complete"
        ))
        return results
    }

    func cancel() {}
}

private final class AsyncGate: @unchecked Sendable {
    private struct State {
        var isOpen = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = LockedState(State())

    func wait() async {
        await withCheckedContinuation { continuation in
            let shouldResumeImmediately = state.withLock { state in
                if state.isOpen {
                    return true
                }
                state.waiters.append(continuation)
                return false
            }
            if shouldResumeImmediately {
                continuation.resume()
            }
        }
    }

    func open() {
        let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            guard !state.isOpen else { return [] }
            state.isOpen = true
            defer { state.waiters.removeAll() }
            return state.waiters
        }
        waiters.forEach { $0.resume() }
    }
}

final class FakeDiskActivityProvider: DiskActivityProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let fakeReader: FakeDiskActivityReader
    private var readerCalls = 0
    private var fallbackCounterCalls = 0

    init(reader: FakeDiskActivityReader) {
        self.fakeReader = reader
    }

    var readerCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return readerCalls
    }

    var fallbackCounterCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return fallbackCounterCalls
    }

    func reader(forBSDName bsdName: String) -> DiskActivityCounterReading? {
        lock.lock()
        readerCalls += 1
        lock.unlock()
        return fakeReader
    }

    func counters(forBSDName bsdName: String) -> DiskActivityCounters? {
        lock.lock()
        fallbackCounterCalls += 1
        lock.unlock()
        return nil
    }
}

final class FakeDiskActivityReader: DiskActivityCounterReading, @unchecked Sendable {
    private let lock = NSLock()
    private let values: [DiskActivityCounters]
    private var index = 0

    init(counters: [DiskActivityCounters]) {
        self.values = counters
    }

    func counters() -> DiskActivityCounters? {
        lock.lock()
        defer { lock.unlock() }
        guard !values.isEmpty else { return nil }
        let value = values[min(index, values.count - 1)]
        index += 1
        return value
    }
}

final class FakeDiskActivityWorkloadRunner: DiskActivityWorkloadRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func run(
        configuration: DiskActivityWorkloadConfiguration,
        drive: DriveDevice,
        progress: @escaping @Sendable (DiskActivityWorkloadProgress) -> Void
    ) async throws {
        progress(DiskActivityWorkloadProgress(
            operation: configuration.operation,
            phase: .writing,
            loopIndex: 1,
            completedBytes: 0,
            totalBytes: configuration.fileSizeBytes,
            message: "Writing workload file"
        ))

        while !isCancelled {
            if Task.isCancelled {
                throw BenchmarkError.cancelled
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        throw BenchmarkError.cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}
