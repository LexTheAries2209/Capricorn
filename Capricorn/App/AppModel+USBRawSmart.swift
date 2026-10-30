// SPDX-License-Identifier: GPL-3.0-only
import Foundation

extension AppModel {
    var canBeginUSBRawSmart: Bool {
        appUpdateConflicts.isEmpty && !isUSBRawSmartActive
    }

    func offersUSBRawSmart(for drive: DriveDevice) -> Bool {
        USBRawSmartPolicy.isEligible(drive: drive, snapshot: snapshots[drive.id])
    }

    func offersUSBRawSmartRefresh(for drive: DriveDevice) -> Bool {
        USBRawSmartPolicy.canRefresh(drive: drive, snapshot: snapshots[drive.id])
    }

    func requestUSBRawSmart(for drive: DriveDevice) {
        guard usbRawSmartSession == nil, canBeginUSBRawSmart,
              offersUSBRawSmart(for: drive) || offersUSBRawSmartRefresh(for: drive) else { return }
        do {
            let target = try usbRawSmartTarget(for: drive)
            selectedDriveID = drive.id
            usbRawSmartSession = USBRawSmartSession(drive: drive, target: target)
            isUSBRawSmartPresented = true
        } catch {
            refreshMessage = error.localizedDescription
        }
    }

    func closeUSBRawSmart() {
        guard !isUSBRawSmartActive else { return }
        isUSBRawSmartPresented = false
    }

    func finishUSBRawSmartDismissal() {
        guard !isUSBRawSmartActive, !isUSBRawSmartPresented else { return }
        // A fixed-size sheet must keep its content through the close animation.
        usbRawSmartSession = nil
    }

    func reconcileUSBRawSmartDrive(_ expected: DriveDevice, hasSMARTPayload: Bool) async -> DriveDevice? {
        // A restored Disk Arbitration mount can precede complete diskutil/IOKit
        // metadata. Retry absence, but never resolve an ambiguous identity.
        for attempt in 1...4 {
            await refresh(allowDuringUSBRawSmart: true)
            let matches = drives.filter { DriveStableIdentityMatcher.matches(expected, $0) }
            appendUSBRawSmartIdentityDiagnostic(expected: expected, matches: matches, attempt: attempt)
            if matches.count == 1 { return matches.first }
            guard hasSMARTPayload, matches.isEmpty, attempt < 4, !Task.isCancelled else { return nil }
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return nil
            }
        }
        return nil
    }

    private func appendUSBRawSmartIdentityDiagnostic(expected: DriveDevice, matches: [DriveDevice], attempt: Int) {
        func identity(_ drive: DriveDevice) -> [String: Any] {
            [
                "bsd": drive.bsdName, "media": drive.mediaName, "protocol": drive.protocolName,
                "serial": drive.serialNumber ?? "", "bytes": drive.sizeBytes, "block": drive.blockSize,
                "usb_vendor": drive.usbDevice?.vendorID ?? 0, "usb_product": drive.usbDevice?.productID ?? 0,
                "internal": drive.isInternal, "system": drive.isSystemDisk, "virtual": drive.isVirtual,
                "codex_name": CodexCompactDriveNameIdentity.volumeName(for: drive) ?? "",
                "volumes": drive.volumes.map {
                    ["bsd": $0.deviceIdentifier, "name": $0.name, "uuid": $0.volumeUUID ?? "",
                     "filesystem": $0.fileSystemType ?? "", "mount": $0.mountPoint ?? ""]
                }
            ]
        }
        let diagnostic: [String: Any] = [
            "attempt": attempt, "expected": identity(expected),
            "candidates": drives.filter { !$0.isInternal && !$0.isVirtual && !$0.isNetwork }.map(identity),
            "matches": matches.map(\.bsdName)
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: diagnostic, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return }
        usbRawSmartSession?.result?.transcript += "\nCAPRICORN_USBRAW_IDENTITY\t" + json
    }
}
