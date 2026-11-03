// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum SNTCaptureTimeMetadata {
    static let attributeID = "captured_at"
    static let source = "Capricorn metadata"

    static func isCaptureTime(_ attribute: SmartAttribute) -> Bool {
        attribute.id == attributeID && attribute.source == source
    }
}

extension SmartSnapshot {
    var attributesWithSNTCaptureTime: [SmartAttribute] {
        guard selectedProvider == USBRawSmartService.providerName, hasSMARTPayload else { return attributes }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
        // Derive metadata from the saved timestamp; never insert it into the
        // device attributes used to validate payloads or evaluate health.
        let timestamp = SmartAttribute(
            id: SNTCaptureTimeMetadata.attributeID,
            name: "Captured At",
            rawValue: formatter.string(from: capturedAt),
            current: nil, worst: nil, threshold: nil,
            status: .unavailable,
            source: SNTCaptureTimeMetadata.source
        )
        return attributes + [timestamp]
    }
}
