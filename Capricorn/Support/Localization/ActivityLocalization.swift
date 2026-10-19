// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import SwiftUI

extension AppLanguage {
    func activityWorkloadProgressText(_ progress: DiskActivityWorkloadProgress) -> String {
        var parts = [
            "\(t("Loop")) \(progress.loopIndex)",
            statusMessage(progress.message)
        ]
        if let failedPhase = progress.failedPhaseMessage {
            parts.append("\(t("Failed phase")): \(statusMessage(failedPhase))")
        }
        if progress.totalBytes > 0 {
            if progress.hasMeasurableByteProgress {
                parts.append("\(formatBenchmarkFileSize(progress.completedBytes)) / \(formatBenchmarkFileSize(progress.totalBytes))")
            } else {
                parts.append("\(t("Target size")): \(formatBenchmarkFileSize(progress.totalBytes))")
            }
        }
        return parts.joined(separator: " · ")
    }

    func aioQueueDescription(_ status: AIOTransferStatus) -> String {
        switch self {
        case .english:
            "Requested Q\(status.targetDepth) per path · active \(status.active) · peak \(status.peakActive) · shared \(status.processUsed)/\(min(status.processLimit, status.systemLimit))"
        case .simplifiedChinese:
            "每路目标 Q\(status.targetDepth) · 当前 \(status.active) · 实际峰值 \(status.peakActive) · 进程共享 \(status.processUsed)/\(min(status.processLimit, status.systemLimit))"
        }
    }

    func activityWorkloadConfirmationMessage(isNetworkDrive: Bool) -> String {
        t(isNetworkDrive
            ? "The workload creates temporary files in the selected target folder. Live activity monitoring is unavailable for network drives."
            : "The workload creates temporary files in the selected target folder. Starting the workload also starts live activity monitoring; existing monitoring continues.")
    }

    func activityWorkloadConfirmationWarning(_ operation: DiskActivityWorkloadOperation) -> String {
        t(operation == .read
            ? "Reading also writes a temporary source file before the read phase. Temporary files use free space and may stress or wear storage."
            : "Write workloads use temporary disk space and may cause sustained storage stress and write wear.")
    }

    func activityWorkloadConfirmationFields(
        configuration: DiskActivityWorkloadConfiguration,
        interval: DiskActivitySampleInterval
    ) -> [BenchmarkConfirmationField] {
        var size = formatBenchmarkFileSize(configuration.fileSizeBytes)
        if configuration.fileSizeOption == .fullDisk95 {
            size = "\(t("Full Disk (95%)")) · \(size)"
        }
        if configuration.operation == .mixed {
            size += " x2"
        }
        return [
            BenchmarkConfirmationField(title: t("Workload"), value: activityWorkloadOperationTitle(configuration.operation)),
            BenchmarkConfirmationField(title: t("Large File Size"), value: size),
            BenchmarkConfirmationField(title: t("Loop"), value: t(configuration.loopEnabled ? "Until stopped" : "Off")),
            BenchmarkConfirmationField(title: t("Sample Interval"), value: interval.title),
            BenchmarkConfirmationField(title: t("Engine"), value: t("SEQ1M Q4T4 async, 4 MiB chunks")),
            BenchmarkConfirmationField(title: t("Data Pattern"), value: benchmarkDataPatternTitle(.zeroFill))
        ]
    }

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
