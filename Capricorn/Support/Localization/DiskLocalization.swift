// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import SwiftUI

extension AppLanguage {
    func healthTitle(_ status: HealthStatus) -> String {
        switch self {
        case .english:
            return status.title
        case .simplifiedChinese:
            return switch status {
            case .good: "良好"
            case .warning: "警告"
            case .preFail: "预故障"
            case .failed: "故障"
            case .unavailable: "不可用"
            }
        }
    }

    func healthBadgeTitle(_ status: HealthStatus, compact: Bool) -> String {
        let title = healthTitle(status)
        return compact ? title : "\(t("Health")): \(title)"
    }

    func healthSummary(driveCount: Int, warningCount: Int) -> String {
        switch self {
        case .english:
            guard driveCount > 0 else { return "No drives" }
            if warningCount == 0 {
                return "\(driveCount) drive\(driveCount == 1 ? "" : "s") monitored"
            }
            return "\(warningCount) drive\(warningCount == 1 ? "" : "s") need attention"
        case .simplifiedChinese:
            guard driveCount > 0 else { return "无磁盘" }
            if warningCount == 0 {
                return "正在监测 \(driveCount) 个磁盘"
            }
            return "\(warningCount) 个磁盘需要注意"
        }
    }
}
