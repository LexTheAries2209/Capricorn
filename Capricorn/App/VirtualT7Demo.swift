// SPDX-License-Identifier: GPL-3.0-only
import Foundation

@MainActor
extension AppModel {
    static func virtualT7Demo(stepNanoseconds: UInt64 = 1_000_000_000) -> AppModel {
        let provider = VirtualT7DemoSmartProvider()
        let model = AppModel(
            inventoryProvider: VirtualT7DemoInventoryProvider(),
            smartService: SmartSnapshotService(
                nativeProvider: provider,
                smartctlProvider: provider
            ),
            virtualT7DemoMode: true,
            virtualT7DemoStepNanoseconds: stepNanoseconds
        )
        let drive = VirtualT7DemoFixture.drive
        model.drives = [drive]
        model.selectedDriveID = drive.id
        model.snapshots = [drive.id: VirtualT7DemoFixture.snapshot(for: drive)]
        model.smartSelfTestCapabilities[drive.id] = .supported(VirtualT7DemoFixture.selfTestCapability)
        model.smartErrorLogCapabilities[drive.id] = .unavailable(
            "Virtual T7 demo does not query a controller error log."
        )
        model.refreshMessage = "Virtual Samsung T7 demo is ready."
        return model
    }
}

enum VirtualT7DemoFixture {
    static let drive = DriveDevice(
        bsdName: "disk999",
        deviceNode: "/dev/disk999",
        displayName: "Samsung Portable SSD T7",
        mediaName: "Samsung PSSD T7 Media",
        protocolName: "USB",
        sizeBytes: 1_000_204_886_016,
        blockSize: 512,
        isInternal: false,
        isRemovable: true,
        isSolidState: true,
        isWritable: false,
        isVirtual: true,
        isSystemDisk: false,
        smartStatusRaw: "Verified",
        nativeSmartKeys: [:],
        volumes: [
            DriveDevice.Volume(
                deviceIdentifier: "disk999s1",
                name: "T7",
                mountPoint: nil,
                sizeBytes: 1_000_204_886_016,
                isWritable: false,
                isSystem: false,
                fileSystemType: "ExFAT",
                totalCapacityBytes: 1_000_204_886_016,
                availableCapacityBytes: 742_153_224_192,
                volumeUUID: "VIRTUAL-T7-DEMO"
            )
        ],
        model: "Samsung Portable SSD T7",
        serialNumber: "VIRTUAL-T7-DEMO",
        usbDevice: DriveUSBDeviceIdentity(
            vendorName: "Samsung",
            productName: "Portable SSD T7",
            vendorID: 0x04E8,
            productID: 0x4001
        )
    )

    static let selfTestCapability = SmartSelfTestCapability(
        shortSupported: true,
        longSupported: true,
        message: "Virtual T7 demo supports simulated quick and full self-tests.",
        shortPollingMinutes: 1,
        longPollingMinutes: 1
    )

    static func snapshot(
        for drive: DriveDevice,
        selfTestReport: SmartSelfTestReport? = nil
    ) -> SmartSnapshot {
        SmartSnapshot(
            driveID: drive.id,
            capturedAt: Date(),
            health: .good,
            summary: "Virtual SMART data reports no immediate risk for Samsung Portable SSD T7.",
            providerStatuses: [
                ProviderStatus(name: "Virtual T7 Demo", state: .available, message: "Simulated SMART fixture data")
            ],
            attributes: [
                attribute("nvme.critical_warning", "Critical Warning", "0", .good),
                attribute("nvme.available_spare", "Available Spare", "100%", .good),
                attribute("nvme.available_spare_threshold", "Available Spare Threshold", "10%", .good),
                attribute("nvme.percentage_used", "Percentage Used", "3%", .good),
                attribute("nvme.data_units_read", "Data Units Read", "26.41 TB", .good),
                attribute("nvme.data_units_written", "Data Units Written", "18.72 TB", .good),
                attribute("nvme.media_errors", "Media Errors", "0", .good),
                attribute("nvme.num_err_log_entries", "Error Log Entries", "0", .good),
                attribute("nvme.unsafe_shutdowns", "Unsafe Shutdowns", "2", .good)
            ],
            temperatureCelsius: 34,
            lifeRemainingPercent: 97,
            powerOnHours: 628,
            powerCycleCount: 214,
            mediaErrors: 0,
            unsafeShutdowns: 2,
            smartStatusRaw: "Verified",
            selfTestStatus: selfTestReport?.latestEntry?.status,
            selfTestReport: selfTestReport,
            enduranceUsedPercent: 3,
            spareAvailablePercent: 100,
            spareAvailableThresholdPercent: 10,
            nativeSmartCapturedAt: Date(),
            selectedProvider: "Virtual T7 Demo",
            selectedTransport: "USB/NVMe demo transport",
            fallbackUsed: false
        )
    }

    static func runningReport(kind: SmartSelfTestKind, remainingPercent: Int) -> SmartSelfTestReport {
        SmartSelfTestReport(
            state: .running,
            currentKind: kind,
            currentRemainingPercent: remainingPercent,
            entries: [],
            shortSupported: true,
            longSupported: true,
            capturedAt: Date()
        )
    }

    static func passedReport(kind: SmartSelfTestKind) -> SmartSelfTestReport {
        let status = kind == .short
            ? "Completed without error (virtual quick self-test)."
            : "Completed without error (virtual full self-test)."
        return SmartSelfTestReport(
            state: .passed,
            currentKind: nil,
            currentRemainingPercent: 0,
            entries: [
                SmartSelfTestEntry(
                    id: "virtual-t7-\(kind.rawValue)-passed",
                    kind: kind,
                    state: .passed,
                    status: status,
                    remainingPercent: 0,
                    lifetimeHours: 628,
                    failingLBA: nil,
                    rawStatus: status
                )
            ],
            shortSupported: true,
            longSupported: true,
            capturedAt: Date()
        )
    }

    static func abortedReport() -> SmartSelfTestReport {
        let status = "Aborted by user (virtual self-test)."
        return SmartSelfTestReport(
            state: .aborted,
            currentKind: nil,
            currentRemainingPercent: nil,
            entries: [
                SmartSelfTestEntry(
                    id: "virtual-t7-aborted",
                    kind: .unknown,
                    state: .aborted,
                    status: status,
                    remainingPercent: nil,
                    lifetimeHours: 628,
                    failingLBA: nil,
                    rawStatus: status
                )
            ],
            shortSupported: true,
            longSupported: true,
            capturedAt: Date()
        )
    }

    private static func attribute(
        _ id: String,
        _ name: String,
        _ rawValue: String,
        _ status: HealthStatus
    ) -> SmartAttribute {
        SmartAttribute(
            id: id,
            name: name,
            rawValue: rawValue,
            current: nil,
            worst: nil,
            threshold: nil,
            status: status,
            source: "Virtual T7 Demo"
        )
    }
}

private struct VirtualT7DemoInventoryProvider: DiskInventoryProviding {
    func loadDrives(showVirtual: Bool) async throws -> [DriveDevice] {
        [VirtualT7DemoFixture.drive]
    }
}

private struct VirtualT7DemoSmartProvider: SmartProviding {
    let providerName = "Virtual T7 Demo"

    func snapshot(for drive: DriveDevice) async -> SmartSnapshot? {
        VirtualT7DemoFixture.snapshot(for: drive)
    }
}
