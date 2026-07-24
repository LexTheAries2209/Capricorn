// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import SwiftUI

extension AppLanguage {
    func operationTitle(_ operation: BenchmarkOperation) -> String {
        switch self {
        case .english:
            return operation.title
        case .simplifiedChinese:
            return switch operation {
            case .read: "读取"
            case .write: "写入"
            case .mixed: "混合"
            }
        }
    }

    func profileName(_ profile: BenchmarkProfile) -> String {
        switch self {
        case .english:
            return profile.name
        case .simplifiedChinese:
            return switch profile.baseProfileID {
            case "default": "默认"
            case "peak-nvme": "峰值 / NVMe"
            case "real-world": "真实场景"
            case "demo": "演示 / 轻量"
            case "custom": "自定义"
            case "test": "测试"
            case "loop": "循环"
            case "loop-extreme": "极限循环"
            default: profile.name
            }
        }
    }

    func benchmarkDataPatternTitle(_ pattern: BenchmarkDataPattern) -> String {
        switch self {
        case .english:
            return pattern.title
        case .simplifiedChinese:
            return switch pattern {
            case .random: "随机"
            case .zeroFill: "0 填充"
            }
        }
    }

    func benchmarkEngineTitle(_ engine: BenchmarkEngine) -> String {
        switch self {
        case .english:
            return engine == .asyncQueue ? "Async" : "Sync"
        case .simplifiedChinese:
            return engine == .asyncQueue ? "异步" : "同步"
        }
    }

    func benchmarkConfigurationDescription(
        profile: BenchmarkProfile,
        runs: Int,
        fileSizeBytes: Int64,
        dataPattern: BenchmarkDataPattern,
        usesTrimmedAverage: Bool,
        usesSmallBlockEfficiency: Bool = false,
        smallBlockFileSizePercent: Int = BenchmarkProfile.defaultSmallBlockFileSizePercent
    ) -> BenchmarkConfigurationDescription {
        let smallBlockPercent = BenchmarkProfile.smallBlockFileSizePercentOptions.contains(smallBlockFileSizePercent)
            ? smallBlockFileSizePercent
            : BenchmarkProfile.defaultSmallBlockFileSizePercent
        let fileSizeDescription: String
        switch self {
        case .english:
            if usesSmallBlockEfficiency {
                fileSizeDescription = "Test size: \(formatBenchmarkFileSize(fileSizeBytes)) base temporary file. 4 KiB, 16 KiB, and 64 KiB items transfer \(smallBlockPercent)% of that size; other items transfer the full file size."
            } else {
                fileSizeDescription = "Test size: \(formatBenchmarkFileSize(fileSizeBytes)) complete temporary file. Reads and writes transfer the full file size; elapsed time comes from the actual transfer."
            }
        case .simplifiedChinese:
            if usesSmallBlockEfficiency {
                fileSizeDescription = "测试文件大小：以 \(formatBenchmarkFileSize(fileSizeBytes)) 临时文件为基准；4 KiB、16 KiB 和 64 KiB 项目实际传输其 \(smallBlockPercent)%，其他项目仍传输完整文件大小。"
            } else {
                fileSizeDescription = "测试文件大小：使用完整的 \(formatBenchmarkFileSize(fileSizeBytes)) 临时文件。读取和写入都会传输完整文件大小，耗时由真实传输决定。"
            }
        }

        if profile.executionMode == .loopUntilCancelled {
            switch self {
            case .english:
                return BenchmarkConfigurationDescription(
                    profileUse: englishProfileUseDescription(profile),
                    runs: "Loop mode: runs continuously until you stop it manually. The matrix shows the latest completed pass for each read/write item.",
                    fileSize: fileSizeDescription,
                    dataPattern: "Data pattern: \(benchmarkDataPatternTitle(dataPattern)). Random is closer to incompressible real data; 0 Fill can expose compression, dedupe, or controller peak behavior.",
                    testTerms: englishLoopTestTermsDescription(profile)
                )
            case .simplifiedChinese:
                return BenchmarkConfigurationDescription(
                    profileUse: chineseProfileUseDescription(profile),
                    runs: "循环模式：会持续运行直到手动停止；矩阵显示每个读/写项目最新完成的一轮结果。",
                    fileSize: fileSizeDescription,
                    dataPattern: "数据模式：\(benchmarkDataPatternTitle(dataPattern))。随机数据更接近不可压缩真实负载；0 填充适合观察压缩、去重或控制器峰值，结果可能偏高。",
                    testTerms: chineseLoopTestTermsDescription(profile)
                )
            }
        }

        switch self {
        case .english:
            let measuredRuns = BenchmarkMeasurementReducer.measuredRunCount(for: runs, usesTrimmedAverage: usesTrimmedAverage)
            let runsDescription = usesTrimmedAverage
                ? "Runs: \(runs) selected, executed as 1 warm-up plus \(measuredRuns) measured passes. The fastest and slowest measured passes are removed, then the rest are averaged."
                : "Runs: \(runs) selected, executed as 1 warm-up plus \(measuredRuns) measured pass\(measuredRuns == 1 ? "" : "es"). All measured passes are averaged."
            let testTerms: String
            if profile.engine == .asyncQueue, profile.baseProfileID == "test" {
                testTerms = "Test labels: SEQ is continuous large-block access, Q is queue depth, and T is thread count. The Test profile compares Q1 and Q8 across T1/T2/T4 using POSIX AIO; write cells show durable speed after fsync, with transfer speed and fsync time underneath."
            } else if profile.engine == .asyncQueue {
                testTerms = "Test labels: SEQ is continuous large-block access, RND is scattered small-block access, Q is queue depth, and T is thread count. This profile uses POSIX AIO queue depth; write cells show durable speed after fsync, with transfer speed and fsync time underneath."
            } else {
                testTerms = "Test labels: SEQ is continuous large-block access, RND is scattered small-block access, Q is queue depth, and T is thread count. Each row runs read first, then write, before moving to the next row."
            }
            return BenchmarkConfigurationDescription(
                profileUse: englishProfileUseDescription(profile),
                runs: runsDescription,
                fileSize: fileSizeDescription,
                dataPattern: "Data pattern: \(benchmarkDataPatternTitle(dataPattern)). Random is closer to incompressible real data; 0 Fill can expose compression, dedupe, or controller peak behavior.",
                testTerms: testTerms
            )
        case .simplifiedChinese:
            let measuredRuns = BenchmarkMeasurementReducer.measuredRunCount(for: runs, usesTrimmedAverage: usesTrimmedAverage)
            let runsDescription = usesTrimmedAverage
                ? "测试次数：界面选择 \(runs)；实际执行 1 轮预热 + \(measuredRuns) 轮正式测量，去掉最高和最低后对剩余结果取平均。"
                : "测试次数：界面选择 \(runs)；实际执行 1 轮预热 + \(measuredRuns) 轮正式测量，对全部正式结果取普通平均。"
            let testTerms: String
            if profile.engine == .asyncQueue, profile.baseProfileID == "test" {
                testTerms = "测试项标记：SEQ 是连续大块读写，Q 是队列深度，T 是线程数。测试配置使用 POSIX AIO，对比 Q1 与 Q8 在 T1/T2/T4 下的表现；写入主数值为 fsync 后落盘速度，单元格下方显示传输速度和刷盘耗时。"
            } else if profile.engine == .asyncQueue {
                testTerms = "测试项标记：SEQ 是连续大块读写，RND 是分散小块随机读写，Q 是队列深度，T 是线程数。此配置使用 POSIX AIO 队列深度；写入主数值为 fsync 后落盘速度，单元格下方显示传输速度和刷盘耗时。"
            } else {
                testTerms = "测试项标记：SEQ 是连续大块读写，RND 是分散小块随机读写，Q 是队列深度，T 是线程数。每一行先读取、再写入，然后进入下一行。"
            }
            return BenchmarkConfigurationDescription(
                profileUse: chineseProfileUseDescription(profile),
                runs: runsDescription,
                fileSize: fileSizeDescription,
                dataPattern: "数据模式：\(benchmarkDataPatternTitle(dataPattern))。随机数据更接近不可压缩真实负载；0 填充适合观察压缩、去重或控制器峰值，结果可能偏高。",
                testTerms: testTerms
            )
        }
    }

    func benchmarkConfirmationConfiguration(
        profile: BenchmarkProfile,
        runs: Int,
        fileSizeBytes: Int64,
        dataPattern: BenchmarkDataPattern,
        usesTrimmedAverage: Bool,
        usesSmallBlockEfficiency: Bool = false,
        smallBlockFileSizePercent: Int = BenchmarkProfile.defaultSmallBlockFileSizePercent
    ) -> String {
        let safePercent = BenchmarkProfile.smallBlockFileSizePercentOptions.contains(smallBlockFileSizePercent)
            ? smallBlockFileSizePercent
            : BenchmarkProfile.defaultSmallBlockFileSizePercent
        let englishSmallBlockState = usesSmallBlockEfficiency ? "\(safePercent)% for 4/16/64 KiB items" : "Off"
        let chineseSmallBlockState = usesSmallBlockEfficiency ? "4/16/64 KiB 项目使用 \(safePercent)%" : "关闭"
        if profile.executionMode == .loopUntilCancelled {
            switch self {
            case .english:
                return "Benchmark settings\nProfile-\(profileName(profile)); engine-\(benchmarkEngineTitle(profile.engine)); runs-loop until stopped; test size-\(formatBenchmarkFileSize(fileSizeBytes)); data pattern-\(benchmarkDataPatternTitle(dataPattern)); extra trimmed testing-not used; small-block efficiency-\(englishSmallBlockState)"
            case .simplifiedChinese:
                return "测试配置\n配置-\(profileName(profile))；引擎-\(benchmarkEngineTitle(profile.engine))；测试次数-循环直到手动停止；测试文件大小-\(formatBenchmarkFileSize(fileSizeBytes))；数据模式-\(benchmarkDataPatternTitle(dataPattern))；加量测试去极值-不使用；提高小块文件测试效率-\(chineseSmallBlockState)"
            }
        }

        switch self {
        case .english:
            let trimState = usesTrimmedAverage ? "On" : "Off"
            return "Benchmark settings\nProfile-\(profileName(profile)); engine-\(benchmarkEngineTitle(profile.engine)); runs-\(runs); test size-\(formatBenchmarkFileSize(fileSizeBytes)); data pattern-\(benchmarkDataPatternTitle(dataPattern)); extra trimmed testing-\(trimState); small-block efficiency-\(englishSmallBlockState)"
        case .simplifiedChinese:
            let trimState = usesTrimmedAverage ? "开启" : "关闭"
            return "测试配置\n配置-\(profileName(profile))；引擎-\(benchmarkEngineTitle(profile.engine))；测试次数-\(runs)；测试文件大小-\(formatBenchmarkFileSize(fileSizeBytes))；数据模式-\(benchmarkDataPatternTitle(dataPattern))；加量测试去极值-\(trimState)；提高小块文件测试效率-\(chineseSmallBlockState)"
        }
    }

    func benchmarkFooter(testCount: Int, fileSize: Int64, runs: Int, dataPattern: BenchmarkDataPattern, usesTrimmedAverage: Bool, executionMode: BenchmarkExecutionMode = .finite, engine: BenchmarkEngine = .synchronous) -> String {
        let engineText = benchmarkEngineTitle(engine)
        if executionMode == .loopUntilCancelled {
            switch self {
            case .english:
                return "Loop · \(engineText) · \(formatBenchmarkFileSize(fileSize)) file · \(benchmarkDataPatternTitle(dataPattern)) · latest pass"
            case .simplifiedChinese:
                return "循环测试 · \(engineText) · \(formatBenchmarkFileSize(fileSize)) 文件 · \(benchmarkDataPatternTitle(dataPattern)) · 最新一轮"
            }
        }

        switch self {
        case .english:
            let averageText = usesTrimmedAverage ? "\(runs)+2 trimmed avg" : "\(runs) avg run\(runs == 1 ? "" : "s")"
            return "\(testCount) tests · \(engineText) · \(formatBenchmarkFileSize(fileSize)) file · \(averageText) · \(benchmarkDataPatternTitle(dataPattern))"
        case .simplifiedChinese:
            let averageText = usesTrimmedAverage ? "\(runs)+2 去极值平均" : "\(runs) 轮普通平均"
            return "\(testCount) 项测试 · \(engineText) · \(formatBenchmarkFileSize(fileSize)) 文件 · \(averageText) · \(benchmarkDataPatternTitle(dataPattern))"
        }
    }

    private func englishProfileUseDescription(_ profile: BenchmarkProfile) -> String {
        switch profile.baseProfileID {
        case "default":
            return "Default: balanced general-purpose disk performance test for most SSDs, HDDs, and external drives."
        case "peak-nvme":
            return "Peak / NVMe: use for high-performance NVMe or Thunderbolt storage when you want controller peak throughput."
        case "real-world":
            return "RealWorld: lighter queue depths and mixed work for app launches, project folders, and everyday file activity."
        case "demo":
            return "Demo / Light: quick validation with low write volume; useful for a fast sanity check."
        case "custom":
            return "Custom: editable test groups for checking a specific SEQ/RND, block size, queue depth, thread count, and optional mixed workload."
        case "test":
            return "Test: experimental asynchronous profile for comparing Q1/Q8 and T1/T2/T4 behavior, transfer speed, and durable speed after fsync."
        case "loop":
            return "Loop: continuous SEQ1M Q1T1 and Q8T1 read/write pressure test for observing peak performance, heat, and sustained drop-off."
        case "loop-extreme":
            return "Extreme Loop: higher-pressure sequential profile for fast NVMe drives, using wider blocks and more worker threads to probe peak sustained throughput."
        default:
            return "\(profile.name): user-defined benchmark profile."
        }
    }

    private func chineseProfileUseDescription(_ profile: BenchmarkProfile) -> String {
        switch profile.baseProfileID {
        case "default":
            return "默认：均衡、通用的硬盘性能测试，适合大多数 SSD、HDD 和外接盘。"
        case "peak-nvme":
            return "峰值 / NVMe：适合高性能 NVMe 或雷电存储，用来看控制器峰值吞吐。"
        case "real-world":
            return "真实场景：队列深度更贴近日常使用，并包含混合负载，适合应用启动、项目目录和普通文件操作。"
        case "demo":
            return "演示 / 轻量：写入量低、完成快，适合快速确认目标文件夹和磁盘状态。"
        case "custom":
            return "自定义：可编辑测试项目组，用于指定 SEQ/RND、块大小、队列深度、线程数和可选混合负载。"
        case "test":
            return "测试：实验性的异步配置，用于对比 Q1/Q8 与 T1/T2/T4 表现、传输速度和 fsync 后落盘速度。"
        case "loop":
            return "循环：持续执行 SEQ1M Q1T1 和 Q8T1 读写压力测试，用于观察峰值性能、温度影响和持续掉速。"
        case "loop-extreme":
            return "极限循环：面向高性能 NVMe 的更高压力顺序读写配置，使用更大的块和更多工作线程来观察持续峰值吞吐。"
        default:
            return "\(profile.name)：用户定义的测速配置。"
        }
    }

    private func englishLoopTestTermsDescription(_ profile: BenchmarkProfile) -> String {
        if profile.baseProfileID == "custom" {
            let engineText = profile.engine == .asyncQueue ? " using POSIX AIO queue depth" : ""
            return "Test labels: SEQ is continuous large-block access, RND is scattered small-block access, Q is queue depth, and T is thread count. Custom Loop repeats the editable read/write groups\(engineText) until you stop it manually."
        }
        if profile.baseProfileID == "loop-extreme" {
            return "Test labels: SEQ is continuous large-block access, Q is queue depth, and T is thread count. Extreme Loop runs SEQ1M Q8T1, SEQ4M Q8T4, and SEQ1M Q32T4 read/write, then repeats without waiting."
        }
        return "Test labels: SEQ is continuous large-block access, Q is queue depth, and T is thread count. Loop runs SEQ1M Q1T1 read/write, then SEQ1M Q8T1 read/write, and repeats without waiting."
    }

    private func chineseLoopTestTermsDescription(_ profile: BenchmarkProfile) -> String {
        if profile.baseProfileID == "custom" {
            let engineText = profile.engine == .asyncQueue ? "，并使用 POSIX AIO 队列深度" : ""
            return "测试项标记：SEQ 是连续大块读写，RND 是分散小块随机读写，Q 是队列深度，T 是线程数。自定义循环会重复执行可编辑读写项目组\(engineText)，直到手动停止。"
        }
        if profile.baseProfileID == "loop-extreme" {
            return "测试项标记：SEQ 是连续大块读写，Q 是队列深度，T 是线程数。极限循环会依次执行 SEQ1M Q8T1、SEQ4M Q8T4、SEQ1M Q32T4 读取/写入，并且无间隔重复。"
        }
        return "测试项标记：SEQ 是连续大块读写，Q 是队列深度，T 是线程数。循环会依次执行 SEQ1M Q1T1 读取/写入、SEQ1M Q8T1 读取/写入，并且无间隔重复。"
    }
}
