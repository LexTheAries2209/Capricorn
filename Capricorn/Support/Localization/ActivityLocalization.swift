// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import SwiftUI

extension AppLanguage {
    func activityWorkloadOperationTitle(_ operation: DiskActivityWorkloadOperation) -> String {
        switch self {
        case .english:
            return switch operation {
            case .read: "Read"
            case .write: "Write"
            case .mixed: "Mixed"
            }
        case .simplifiedChinese:
            return switch operation {
            case .read: "读取"
            case .write: "写入"
            case .mixed: "读写混合"
            }
        }
    }
}
