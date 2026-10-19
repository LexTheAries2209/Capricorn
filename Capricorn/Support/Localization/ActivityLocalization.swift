// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import SwiftUI

extension AppLanguage {
    func activityWorkloadProgressText(_ progress: DiskActivityWorkloadProgress) -> String {
        if progress.phase == .stopped {
            return statusMessage("Workload stopped")
        }
        var parts = [
            "\(t("Loop")) \(progress.loopIndex)",
            statusMessage(progress.message)
        ]
        if let failedPhase = progress.failedPhaseMessage {
            parts.append("\(t("Failed phase")): \(statusMessage(failedPhase))")
        }
        if progress.totalBytes > 0 && progress.stopRequestedAt == nil {
            if progress.hasMeasurableByteProgress {
                parts.append("\(formatBenchmarkFileSize(progress.completedBytes)) / \(formatBenchmarkFileSize(progress.totalBytes))")
            } else {
                parts.append("\(t("Target size")): \(formatBenchmarkFileSize(progress.totalBytes))")
            }
        }
        return parts.joined(separator: " · ")
    }

    func activityWorkloadStopElapsed(_ progress: DiskActivityWorkloadProgress, now: Date) -> String {
        let seconds = Int(max(0, now.timeIntervalSince(progress.stopRequestedAt ?? now)))
        switch self {
        case .english: return "Waiting to stop · \(seconds) s elapsed"
        case .simplifiedChinese: return "正在等待停止 · 已等待 \(seconds) 秒"
        }
    }

    func activityWorkloadStopExplanation(_ progress: DiskActivityWorkloadProgress) -> String {
        if progress.queueStatus?.draining == true || progress.phase == .cleaningUp {
            return self == .simplifiedChinese
                ? "已停止提交新的负载 I/O；等待已提交的请求结束并回收资源后，才能安全关闭临时文件。"
                : "No new workload I/O is being submitted. Pending requests must finish and be collected before temporary files can be safely closed."
        }
        switch progress.stopPhase {
        case .sizingFile:
            return self == .simplifiedChinese
                ? "正在等待文件系统完成当前文件准备操作，返回后会停止并清理本次临时文件。此阶段无法提供百分比，磁盘仍可能有写入。"
                : "Waiting for the current file preparation operation to return, then stopping and cleaning up this run's temporary files. Percentage progress is unavailable; disk writes may continue."
        case .flushing, .flushingReadFile:
            return self == .simplifiedChinese
                ? "正在等待当前刷盘操作返回，随后完成停止和清理。耗时取决于磁盘及文件系统，暂无法估算剩余时间。"
                : "Waiting for the current flush operation to return before completing stop and cleanup. The disk and file system determine the duration; time remaining is unavailable."
        default:
            return self == .simplifiedChinese
                ? "已请求停止，正在结束当前操作并清理本次临时文件。完成后会显示“负载已停止”；暂无法估算剩余时间。"
                : "Stop requested. Finishing the current operation and cleaning up this run's temporary files. The status will change to Stopped when complete; time remaining is unavailable."
        }
    }

    func activityWorkloadPendingIO(_ progress: DiskActivityWorkloadProgress) -> String? {
        guard let status = progress.queueStatus, status.draining else { return nil }
        if status.active == 0 {
            return self == .simplifiedChinese ? "已提交的 I/O 已结束，正在完成清理。" : "Submitted I/O has finished; completing cleanup."
        }
        return self == .simplifiedChinese
            ? "仍有 \(status.active) 个已提交的 I/O 等待结束"
            : "\(status.active) submitted I/O requests still pending"
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
