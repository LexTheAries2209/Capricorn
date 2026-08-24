// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation
import IOKit
import IOKit.storage

enum DriveSystemEvent: String, Sendable {
    case volumeMounted
    case volumeUnmounted
    case deviceAppeared
    case deviceTerminated
}

protocol DriveSystemEventMonitoring: Sendable {
    func events() -> AsyncStream<DriveSystemEvent>
}

/// Merges volume-level workspace notifications with hardware-level IOKit
/// notifications. IOKit's initial iterator is drained without publishing so
/// launching Capricorn does not mistake every existing disk for a hot plug.
final class SystemDriveSystemEventMonitor: DriveSystemEventMonitoring, @unchecked Sendable {
    private struct ContinuationState {
        var continuations: [UUID: AsyncStream<DriveSystemEvent>.Continuation] = [:]
    }

    private let state = LockedState(ContinuationState())
    private let notificationQueue = DispatchQueue(label: "com.dit.capricorn.drive-system-events")
    private var workspaceObserverTokens: [NSObjectProtocol] = []
    private var notificationPort: IONotificationPortRef?
    private var matchedIterator: io_iterator_t = 0
    private var terminatedIterator: io_iterator_t = 0

    init() {
        startWorkspaceMonitoring()
        startIOKitMonitoring()
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObserverTokens.forEach(center.removeObserver)

        if let notificationPort {
            IONotificationPortSetDispatchQueue(notificationPort, nil)
        }
        if matchedIterator != 0 {
            IOObjectRelease(matchedIterator)
        }
        if terminatedIterator != 0 {
            IOObjectRelease(terminatedIterator)
        }
        if let notificationPort {
            IONotificationPortDestroy(notificationPort)
        }
    }

    func events() -> AsyncStream<DriveSystemEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            state.withLock { $0.continuations[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { $0.continuations.removeValue(forKey: id) }
            }
        }
    }

    fileprivate func consumeIOKitServices(
        from iterator: io_iterator_t,
        event: DriveSystemEvent,
        publishesEvent: Bool = true
    ) {
        var foundService = false
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            foundService = true
            IOObjectRelease(service)
        }

        if foundService && publishesEvent {
            publish(event)
        }
    }

    private func startWorkspaceMonitoring() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObserverTokens = [
            center.addObserver(
                forName: NSWorkspace.didMountNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.publish(.volumeMounted)
            },
            center.addObserver(
                forName: NSWorkspace.didUnmountNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.publish(.volumeUnmounted)
            }
        ]
    }

    private func startIOKitMonitoring() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notificationPort = port
        IONotificationPortSetDispatchQueue(port, notificationQueue)

        let context = Unmanaged.passUnretained(self).toOpaque()
        let matchedResult = IOServiceAddMatchingNotification(
            port,
            kIOMatchedNotification,
            IOServiceMatching(kIOMediaClass),
            driveSystemDeviceAppeared,
            context,
            &matchedIterator
        )
        if matchedResult == KERN_SUCCESS {
            consumeIOKitServices(from: matchedIterator, event: .deviceAppeared, publishesEvent: false)
        }

        let terminatedResult = IOServiceAddMatchingNotification(
            port,
            kIOTerminatedNotification,
            IOServiceMatching(kIOMediaClass),
            driveSystemDeviceTerminated,
            context,
            &terminatedIterator
        )
        if terminatedResult == KERN_SUCCESS {
            consumeIOKitServices(from: terminatedIterator, event: .deviceTerminated, publishesEvent: false)
        }
    }

    private func publish(_ event: DriveSystemEvent) {
        let continuations = state.snapshot().continuations.values
        continuations.forEach { $0.yield(event) }
    }
}

private func driveSystemDeviceAppeared(
    context: UnsafeMutableRawPointer?,
    iterator: io_iterator_t
) {
    guard let context else { return }
    Unmanaged<SystemDriveSystemEventMonitor>
        .fromOpaque(context)
        .takeUnretainedValue()
        .consumeIOKitServices(from: iterator, event: .deviceAppeared)
}

private func driveSystemDeviceTerminated(
    context: UnsafeMutableRawPointer?,
    iterator: io_iterator_t
) {
    guard let context else { return }
    Unmanaged<SystemDriveSystemEventMonitor>
        .fromOpaque(context)
        .takeUnretainedValue()
        .consumeIOKitServices(from: iterator, event: .deviceTerminated)
}
