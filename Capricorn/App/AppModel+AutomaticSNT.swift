// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum AutomaticSNTStatus: String, Sendable {
    case waiting = "Waiting to read SNT"
    case reading = "Reading SNT automatically"
    case updated = "SNT health information updated"
    case cached = "Using cached SNT data"
    case busy = "SNT waiting for disk to become idle"
    case occupancyUnknown = "SNT waiting for a complete disk-use check"
    case authorization = "Automatic SNT requires system authorization"
    case retrying = "SNT read failed; waiting to retry"
    case stopped = "Automatic SNT paused; manual retry is available"
    case recovery = "Automatic SNT paused; check volume restoration"
    case unsupported = "This USB device is not eligible for automatic SNT"
}

struct AutomaticSNTConnection {
    let id: UUID
    var drive: DriveDevice
    var target: USBRawSmartTarget
    var completed = false
    var nextAttempt: Date
    var status: AutomaticSNTStatus = .waiting
}

extension AppModel {
    func configureAutomaticSNT(enabled: Bool) {
        let wasEnabled = automaticSNTEnabled
        automaticSNTEnabled = enabled
        guard enabled else { return }
        if !wasEnabled { automaticSNTConnections = [:] }
        synchronizeAutomaticSNTConnections()
        guard automaticSNTTask == nil else { return }
        automaticSNTTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.automaticSNTEnabled else { break }
                await self.processAutomaticSNTQueue()
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
            self?.automaticSNTTask = nil
        }
    }

    func automaticSNTStatus(for drive: DriveDevice) -> AutomaticSNTStatus? {
        guard automaticSNTEnabled else { return nil }
        return automaticSNTConnections.values.first { $0.drive.id == drive.id }?.status
    }

    func automaticSNTDiagnostic(for drive: DriveDevice) -> String? {
        guard let connection = automaticSNTConnections.values.first(where: { $0.drive.id == drive.id }) else { return nil }
        return automaticSNTCache.record(for: drive, connectionKey: connection.id.uuidString)?.diagnostic
    }

    /// Called only after a complete ordinary refresh. Capture reconciliation
    /// deliberately keeps the same connection token through USB re-enumeration.
    func synchronizeAutomaticSNTConnections(now: Date = Date()) {
        guard automaticSNTEnabled, !isUSBRawSmartActive else { return }
        var retained: [UUID: AutomaticSNTConnection] = [:]
        for drive in drives where USBRawSmartPolicy.supportsRead(drive) {
            guard let snapshot = snapshots[drive.id],
                  offersUSBRawSmart(for: drive) || offersUSBRawSmartRefresh(for: drive),
                  let target = try? usbRawSmartTarget(for: drive) else { continue }
            let key = AutomaticSNTCache.identityKey(for: drive)
            // Never apply a cached exclusion or reading to ambiguous media.
            if let key, drives.filter({ AutomaticSNTCache.identityKey(for: $0) == key }).count != 1 { continue }
            let matches = automaticSNTConnections.values.filter { connection in
                if let key { return key == AutomaticSNTCache.identityKey(for: connection.drive) }
                return connection.target == target
            }
            var connection = matches.count == 1 ? matches[0] : AutomaticSNTConnection(
                id: UUID(), drive: drive, target: target, nextAttempt: now.addingTimeInterval(2))
            connection.drive = drive
            connection.target = target
            if let cached = automaticSNTCache.record(for: drive, connectionKey: connection.id.uuidString) {
                if cached.status == .stopped {
                    connection.completed = true
                    connection.status = .stopped
                } else if cached.status == .needsRecovery {
                    connection.completed = true
                    connection.status = .recovery
                } else if !connection.completed, cached.hasFreshSnapshot(now: now) {
                    // Complete this connection so an ordinary refresh after expiry
                    // cannot trigger an unexpected USB capture.
                    connection.completed = true
                    connection.status = .cached
                }
                if snapshot.verifiedSource == nil, var previous = cached.lastSnapshot {
                    previous.driveID = drive.id
                    snapshots[drive.id] = previous
                }
            }
            retained[connection.id] = connection
        }
        automaticSNTConnections = retained
        automaticSNTCache.retainConnections(Set(retained.keys.map(\.uuidString)))
    }

    /// Processes one device at a time. Occupancy and missing prerequisites
    /// postpone the task without consuming its persistent failure budget.
    func processAutomaticSNTQueue(now: Date = Date()) async {
        guard automaticSNTEnabled, canBeginUSBRawSmart, usbRawSmartSession == nil else { return }
        let queued = automaticSNTConnections.values.filter {
            !$0.completed && $0.nextAttempt <= now
        }.sorted { $0.nextAttempt < $1.nextAttempt }
        guard var connection = queued.first else { return }
        guard let drive = drives.first(where: { $0.id == connection.drive.id }),
              let target = try? usbRawSmartTarget(for: drive), target == connection.target else {
            connection.status = .waiting
            connection.nextAttempt = now.addingTimeInterval(30)
            automaticSNTConnections[connection.id] = connection
            return
        }
        var record = automaticSNTCache.record(for: drive, connectionKey: connection.id.uuidString) ?? AutomaticSNTRecord()
        if record.status == .stopped || record.status == .needsRecovery {
            connection.completed = true
            connection.status = record.status == .stopped ? .stopped : .recovery
            automaticSNTConnections[connection.id] = connection
            return
        }
        if record.hasFreshSnapshot(now: now) {
            connection.completed = true
            connection.status = .cached
            automaticSNTConnections[connection.id] = connection
            return
        }
        if let retryAfter = record.retryAfter, retryAfter > now {
            connection.nextAttempt = retryAfter
            automaticSNTConnections[connection.id] = connection
            return
        }
        connection.status = .reading
        automaticSNTConnections[connection.id] = connection
        // If the GUI exits while a helper owns USB, the next launch must not
        // assume that cleanup completed. A normal result replaces this marker.
        var pending = record
        pending.status = .needsRecovery
        pending.checkedAt = now
        automaticSNTCache.store(pending, for: drive, connectionKey: connection.id.uuidString)
        do {
            let (result, restoredDrive) = try await performAutomaticSNTRead(
                drive: drive, target: target, preferredBridge: record.preferredBridge)
            record.apply(result, now: max(now, Date()))
            if let restoredDrive {
                connection.drive = restoredDrive
                if let current = try? usbRawSmartTarget(for: restoredDrive) { connection.target = current }
                if result.snapshot?.hasSMARTPayload != true,
                   snapshots[restoredDrive.id]?.verifiedSource == nil,
                   var previous = record.lastSnapshot {
                    previous.driveID = restoredDrive.id
                    snapshots[restoredDrive.id] = previous
                }
            } else if result.phases.contains(.capturing) {
                record.status = .needsRecovery
            }
            automaticSNTCache.store(record, for: drive, connectionKey: connection.id.uuidString)
            switch record.status {
            case .available where result.snapshot?.hasSMARTPayload == true && result.restorationConfirmed:
                connection.completed = true
                connection.status = .updated
            case .stopped:
                connection.completed = true
                connection.status = .stopped
            case .needsRecovery:
                connection.completed = true
                connection.status = .recovery
                refreshMessage = AutomaticSNTStatus.recovery.rawValue
            default:
                connection.status = result.unmountBusy ? .busy : .retrying
                connection.nextAttempt = record.retryAfter ?? now.addingTimeInterval(30)
            }
        } catch let deferral as AutomaticSNTDeferral {
            automaticSNTCache.store(record, for: drive, connectionKey: connection.id.uuidString)
            switch deferral {
            case .busy: connection.status = .busy
            case .occupancyUnknown: connection.status = .occupancyUnknown
            case .needsAuthorization: connection.status = .authorization
            case .identityChanged: connection.status = .waiting
            case .unsupported:
                connection.status = .unsupported
                connection.completed = true
            }
            connection.nextAttempt = now.addingTimeInterval(30)
        } catch {
            // XPC disconnection may leave a worker restoring mounts. Never
            // retry an operation whose cleanup evidence was lost.
            record.status = .needsRecovery
            record.diagnostic = error.localizedDescription
            record.checkedAt = now
            automaticSNTCache.store(record, for: drive, connectionKey: connection.id.uuidString)
            connection.status = .recovery
            connection.completed = true
            refreshMessage = AutomaticSNTStatus.recovery.rawValue
        }
        automaticSNTConnections[connection.id] = connection
    }

    func recordManualSNTResult(_ result: USBRawSmartResult, for drive: DriveDevice, restoredDrive: DriveDevice?) {
        let connection = automaticSNTConnections.values.first {
            $0.drive.id == drive.id || DriveStableIdentityMatcher.matches($0.drive, drive)
        }
        let token = connection?.id ?? UUID()
        var record = automaticSNTCache.record(for: drive, connectionKey: token.uuidString) ?? AutomaticSNTRecord()
        guard !result.phases.isEmpty else { return }
        record.apply(result, now: Date())
        if result.snapshot?.hasSMARTPayload == true, restoredDrive == nil { record.status = .needsRecovery }
        automaticSNTCache.store(record, for: drive, connectionKey: token.uuidString)
        if var connection {
            if let restoredDrive {
                connection.drive = restoredDrive
                if let target = try? usbRawSmartTarget(for: restoredDrive) { connection.target = target }
            }
            connection.completed = record.status != .retryable
            connection.status = record.status == .available ? .updated
                : record.status == .needsRecovery ? .recovery
                : record.status == .stopped ? .stopped : .retrying
            automaticSNTConnections[token] = connection
        }
    }
}
