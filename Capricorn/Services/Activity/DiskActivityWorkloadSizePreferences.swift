import Foundation

struct DiskActivityWorkloadSizePreferences: Codable, Equatable, Sendable {
    static let defaultsKey = "diskActivityWorkloadSizesByDrive"
    static let defaultSelection = DiskActivityWorkloadFileSize.gib128
    private(set) var selectionsByDrive: [String: DiskActivityWorkloadFileSize] = [:]

    static func decode(_ encoded: String) -> Self {
        guard let data = encoded.data(using: .utf8),
              let preferences = try? JSONDecoder().decode(Self.self, from: data) else {
            return Self()
        }
        return preferences
    }

    func encoded() -> String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    func selection(for drive: DriveDevice) -> DiskActivityWorkloadFileSize {
        selectionsByDrive[DiskActivityWorkloadTargetResolver.preferenceKey(for: drive)] ?? Self.defaultSelection
    }

    mutating func setSelection(_ selection: DiskActivityWorkloadFileSize, for drive: DriveDevice) {
        selectionsByDrive[DiskActivityWorkloadTargetResolver.preferenceKey(for: drive)] = selection
    }

    func availableSelection(
        for drive: DriveDevice,
        operation: DiskActivityWorkloadOperation,
        availableCapacity: Int64?
    ) -> DiskActivityWorkloadFileSize {
        let preferred = selection(for: drive)
        guard let availableCapacity, let preferredBytes = preferred.fixedBytes,
              !DiskActivityWorkloadStorageValidator.isFileSizeAvailable(preferred, operation: operation, availableCapacity: availableCapacity) else {
            return preferred
        }
        // Capacity changes affect only the displayed choice, never the saved preference.
        return DiskActivityWorkloadFileSize.allCases.reversed().first {
            guard let bytes = $0.fixedBytes, bytes <= preferredBytes else { return false }
            return DiskActivityWorkloadStorageValidator.isFileSizeAvailable($0, operation: operation, availableCapacity: availableCapacity)
        } ?? preferred
    }
}
