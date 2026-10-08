// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import SwiftUI

extension AppLanguage {
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
