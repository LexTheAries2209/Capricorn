// SPDX-License-Identifier: GPL-3.0-only
import Foundation

extension AppModel {
    var canBeginUSBRawSmart: Bool {
        appUpdateConflicts.isEmpty && !isUSBRawSmartActive
    }

    func offersUSBRawSmart(for drive: DriveDevice) -> Bool {
        USBRawSmartPolicy.isEligible(drive: drive, snapshot: snapshots[drive.id])
    }

    func requestUSBRawSmart(for drive: DriveDevice) {
        guard usbRawSmartSession == nil, canBeginUSBRawSmart, offersUSBRawSmart(for: drive) else { return }
        do {
            let target = try usbRawSmartTarget(for: drive)
            selectedDriveID = drive.id
            usbRawSmartSession = USBRawSmartSession(drive: drive, target: target)
        } catch {
            refreshMessage = error.localizedDescription
        }
    }

    func closeUSBRawSmart() {
        guard !isUSBRawSmartActive else { return }
        usbRawSmartSession = nil
    }
}
