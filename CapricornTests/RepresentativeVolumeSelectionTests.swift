// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import Capricorn

final class RepresentativeVolumeSelectionTests: XCTestCase {
    func testFallbackUsesLargestSafeVolumeAndSkipsProtectedVolumes() {
        var drive = CapricornTests.fixtureDrive()
        drive.isInternal = false
        drive.isSystemDisk = false
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "disk9s1", name: "System", mountPoint: "/System", sizeBytes: 1_000, isWritable: true, isSystem: true),
            DriveDevice.Volume(deviceIdentifier: "disk9s2", name: "Archive", mountPoint: "/Volumes/Archive", sizeBytes: 900, isWritable: true, isSystem: false, apfsRole: "Backup"),
            DriveDevice.Volume(deviceIdentifier: "disk9s3", name: "Read Only", mountPoint: "/Volumes/Read Only", sizeBytes: 800, isWritable: false, isSystem: false),
            DriveDevice.Volume(deviceIdentifier: "disk9s4", name: "Unmounted", mountPoint: nil, sizeBytes: 700, isWritable: true, isSystem: false),
            DriveDevice.Volume(deviceIdentifier: "disk9s5", name: "Media", mountPoint: "/Volumes/Media", sizeBytes: 500, isWritable: true, isSystem: false),
            DriveDevice.Volume(deviceIdentifier: "disk9s6", name: "Projects", mountPoint: "/Volumes/Projects", sizeBytes: 600, isWritable: true, isSystem: false)
        ]

        XCTAssertEqual(RepresentativeVolumeResolver.fallbackVolume(for: drive)?.deviceIdentifier, "disk9s6")
        XCTAssertFalse(RepresentativeVolumeResolver.isSelectable(drive.volumes[0]))
        XCTAssertFalse(RepresentativeVolumeResolver.isSelectable(drive.volumes[1]))
        XCTAssertTrue(RepresentativeVolumeResolver.isSelectable(drive.volumes[5]))
    }

    func testStructuralEFIAndAPFSBackingEntriesAreHiddenFromVolumeChoices() {
        let efi = DriveDevice.Volume(
            deviceIdentifier: "disk10s1",
            name: "EFI",
            mountPoint: nil,
            sizeBytes: 209_715_200,
            isWritable: true,
            isSystem: false,
            fileSystemType: "EFI"
        )
        let apfsBacking = DriveDevice.Volume(
            deviceIdentifier: "disk10s2",
            name: "disk10s2",
            mountPoint: nil,
            sizeBytes: 4_100_000_000_000,
            isWritable: true,
            isSystem: false,
            fileSystemType: "APFS"
        )
        let data = DriveDevice.Volume(
            deviceIdentifier: "disk10s3",
            name: "40G4T_APFS_F",
            mountPoint: "/Volumes/40G4T_APFS_F",
            sizeBytes: 4_000_000_000_000,
            isWritable: true,
            isSystem: false,
            fileSystemType: "APFS",
            volumeUUID: "data-volume"
        )
        var drive = CapricornTests.fixtureDrive()
        drive.isInternal = false
        drive.isSystemDisk = false
        drive.volumes = [efi, apfsBacking, data]

        XCTAssertEqual(RepresentativeVolumeResolver.orderedVolumes(for: drive).map(\.deviceIdentifier), ["disk10s3"])
        XCTAssertEqual(drive.displayableVolumes.map(\.deviceIdentifier), ["disk10s3"])
        XCTAssertEqual(RepresentativeVolumeResolver.fallbackVolume(for: drive)?.deviceIdentifier, "disk10s3")
        XCTAssertFalse(RepresentativeVolumeResolver.isVisibleVolume(efi))
        XCTAssertFalse(RepresentativeVolumeResolver.isVisibleVolume(apfsBacking))
    }

    func testPreferencesFollowStableSerialInsteadOfChangingBSDName() {
        var drive = CapricornTests.fixtureDrive()
        drive.isInternal = false
        drive.isSystemDisk = false
        drive.bsdName = "disk9"
        drive.serialNumber = "  SERIAL-123  "
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "disk9s1", name: "Large", mountPoint: "/Volumes/Large", sizeBytes: 900, isWritable: true, isSystem: false, volumeUUID: "VOLUME-LARGE"),
            DriveDevice.Volume(deviceIdentifier: "disk9s2", name: "Chosen", mountPoint: "/Volumes/Chosen", sizeBytes: 200, isWritable: true, isSystem: false, volumeUUID: "VOLUME-CHOSEN")
        ]
        var preferences = RepresentativeVolumePreferences()
        preferences.setSelectedVolumeID("disk9s2", for: drive)

        var reattachedDrive = drive
        reattachedDrive.bsdName = "disk14"
        reattachedDrive.volumes[0].deviceIdentifier = "disk14s1"
        reattachedDrive.volumes[1].deviceIdentifier = "disk14s2"

        XCTAssertEqual(RepresentativeVolumeResolver.preferenceKey(for: drive), "serial:serial-123")
        XCTAssertEqual(preferences.selectedVolumeID(for: reattachedDrive), "disk14s2")
    }

    @MainActor
    func testStartupPreferenceUsesLargestOrLastSelectedVolume() {
        var drive = CapricornTests.fixtureDrive()
        drive.isInternal = false
        drive.isSystemDisk = false
        drive.serialNumber = "SERIAL-123"
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "disk9s1", name: "Largest", mountPoint: "/Volumes/Largest", sizeBytes: 900, isWritable: true, isSystem: false),
            DriveDevice.Volume(deviceIdentifier: "disk9s2", name: "Chosen", mountPoint: "/Volumes/Chosen", sizeBytes: 200, isWritable: true, isSystem: false)
        ]

        var persisted = RepresentativeVolumePreferences()
        persisted.setSelectedVolumeID("disk9s2", for: drive)

        let largestOnLaunch = AppModel()
        largestOnLaunch.drives = [drive]
        largestOnLaunch.configureRepresentativeVolumes(
            startupPreference: .largestCapacity,
            encodedPreferences: persisted.encoded()
        )
        XCTAssertEqual(largestOnLaunch.representativeVolume(for: drive)?.deviceIdentifier, "disk9s1")

        largestOnLaunch.selectRepresentativeVolume(drive.volumes[1], for: drive)
        XCTAssertEqual(largestOnLaunch.representativeVolume(for: drive)?.deviceIdentifier, "disk9s2")

        let lastSelectedOnLaunch = AppModel()
        lastSelectedOnLaunch.drives = [drive]
        lastSelectedOnLaunch.configureRepresentativeVolumes(
            startupPreference: .lastSelected,
            encodedPreferences: largestOnLaunch.encodedRepresentativeVolumePreferences
        )
        XCTAssertEqual(lastSelectedOnLaunch.representativeVolume(for: drive)?.deviceIdentifier, "disk9s2")
    }

    @MainActor
    func testSystemDiskDoesNotAllowRepresentativeVolumeSwitching() {
        var drive = CapricornTests.fixtureDrive()
        drive.volumes = [
            DriveDevice.Volume(deviceIdentifier: "disk0s1", name: "Largest", mountPoint: "/Volumes/Largest", sizeBytes: 900, isWritable: true, isSystem: false),
            DriveDevice.Volume(deviceIdentifier: "disk0s2", name: "Other", mountPoint: "/Volumes/Other", sizeBytes: 200, isWritable: true, isSystem: false)
        ]
        let model = AppModel()
        model.drives = [drive]
        model.configureRepresentativeVolumes(startupPreference: .largestCapacity, encodedPreferences: "")

        model.selectRepresentativeVolume(drive.volumes[1], for: drive)

        XCTAssertFalse(RepresentativeVolumeResolver.maySwitchVolume(for: drive))
        XCTAssertEqual(model.representativeVolume(for: drive)?.deviceIdentifier, "disk0s1")
    }
}
