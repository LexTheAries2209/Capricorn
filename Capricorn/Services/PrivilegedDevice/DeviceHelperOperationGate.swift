// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Serializes device ownership independently of XPC connection lifetimes.
final class DeviceHelperOperationGate: @unchecked Sendable {
    enum Admission {
        case accepted
        case cached(DeviceHelperResponse)
        case busy
    }

    private let lock = NSLock()
    private var active: (uid: UInt32, id: UUID)?
    private var stopping = false
    private var results: [(uid: UInt32, response: DeviceHelperResponse)] = []

    func begin(id: UUID, uid: UInt32) -> Admission {
        lock.lock()
        defer { lock.unlock() }
        if let previous = results.first(where: { $0.uid == uid && $0.response.requestID == id }) {
            return .cached(previous.response)
        }
        guard active == nil, !stopping else { return .busy }
        active = (uid, id)
        return .accepted
    }

    func finish(id: UUID, uid: UInt32, response: DeviceHelperResponse?) {
        lock.lock()
        defer { lock.unlock() }
        guard active?.uid == uid, active?.id == id else { return }
        if let response, response.requestID == id {
            results.append((uid, response))
            if results.count > 8 { results.removeFirst() }
        }
        active = nil
    }

    func result(id: String, uid: UInt32) -> DeviceHelperResponse? {
        lock.lock()
        defer { lock.unlock() }
        return results.first { $0.uid == uid && $0.response.requestID.uuidString == id }?.response
    }

    func prepareToStop() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard active == nil else { return false }
        stopping = true
        return true
    }

    func cancelStop() {
        lock.lock()
        stopping = false
        lock.unlock()
    }
}
