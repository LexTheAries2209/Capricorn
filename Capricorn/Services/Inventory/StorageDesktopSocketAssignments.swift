// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Darwin

/// Key a confirmed socket to the shared root device so all downstream disks
/// follow the same physical cable. Registry IDs can be reused after a reboot;
/// keep confirmations within the current boot session.
struct StorageDesktopSocketAssignments {
    private var values: [String: [String: String]]
    private let bootSession: String

    init(data: Data, bootSession: String = Self.currentBootSession()) {
        values = (try? JSONDecoder().decode([String: [String: String]].self, from: data)) ?? [:]
        self.bootSession = bootSession
    }

    var data: Data { (try? JSONEncoder().encode(values)) ?? Data() }

    func ports(for model: StorageHostModel?) -> [String: StorageHostPort] {
        guard let model, let profile = model.desktopPortLayout else { return [:] }
        return (values["\(bootSession):\(model.identifier)"] ?? [:]).compactMapValues { socketID in
            profile.sockets.first { $0.id == socketID }?.port
        }
    }

    mutating func assign(_ socketID: String?, to rootNodeID: String, model: StorageHostModel) {
        if let socketID, model.desktopPortLayout?.sockets.contains(where: { $0.id == socketID }) != true {
            return
        }
        let key = "\(bootSession):\(model.identifier)"
        var assignments = values[key] ?? [:]
        assignments[rootNodeID] = socketID
        values[key] = assignments
    }

    static func currentBootSession() -> String {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 1 else {
            return processSession
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else {
            return processSession
        }
        return String(cString: buffer)
    }

    private static let processSession = UUID().uuidString
}
