import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .english: "en"
        case .simplifiedChinese: "zh-Hans"
        }
    }

    var shortTitle: String {
        switch self {
        case .english: "EN"
        case .simplifiedChinese: "中文"
        }
    }

    func t(_ key: String) -> String {
        guard self == .simplifiedChinese else { return key }
        return Self.zhHans[key] ?? key
    }

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
            return switch profile.id {
            case "default": "默认"
            case "peak-nvme": "峰值 / NVMe"
            case "real-world": "真实场景"
            case "demo": "演示 / 轻量"
            case "custom": "自定义"
            default: profile.name
            }
        }
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

    func benchmarkFooter(testCount: Int, fileSize: Int64, runs: Int) -> String {
        switch self {
        case .english:
            return "\(testCount) tests · \(formatByteCount(fileSize)) file · \(runs) run\(runs == 1 ? "" : "s")"
        case .simplifiedChinese:
            return "\(testCount) 项测试 · \(formatByteCount(fileSize)) 文件 · \(runs) 轮"
        }
    }

    func statusMessage(_ message: String) -> String {
        guard self == .simplifiedChinese else { return message }

        if let exact = Self.zhHansMessages[message] {
            return exact
        }
        if message.hasPrefix("Last refreshed ") {
            return message.replacingOccurrences(of: "Last refreshed ", with: "上次刷新 ")
        }
        if message.hasPrefix("SMART data does not show immediate risk for "), message.hasSuffix(".") {
            let name = message
                .replacingOccurrences(of: "SMART data does not show immediate risk for ", with: "")
                .dropLast()
            return "SMART 数据未显示 \(name) 存在即时风险。"
        }
        if message.hasPrefix("Preparing ") {
            let operation = String(message.dropFirst("Preparing ".count))
            return "正在准备\(statusMessage(operation))"
        }
        if message.hasPrefix("Read run ") {
            return message.replacingOccurrences(of: "Read run ", with: "读取第 ")
                .replacingOccurrences(of: "/", with: "/")
        }
        if message.hasPrefix("Write run ") {
            return message.replacingOccurrences(of: "Write run ", with: "写入第 ")
                .replacingOccurrences(of: "/", with: "/")
        }
        if message.hasPrefix("Mixed run ") {
            return message.replacingOccurrences(of: "Mixed run ", with: "混合第 ")
                .replacingOccurrences(of: "/", with: "/")
        }
        if message.hasPrefix("Insufficient free space.") {
            return message
                .replacingOccurrences(of: "Insufficient free space.", with: "可用空间不足。")
                .replacingOccurrences(of: "Required", with: "需要")
                .replacingOccurrences(of: "available", with: "可用")
        }
        if message.hasPrefix("Could not save SMART snapshot to history: ") {
            return message.replacingOccurrences(of: "Could not save SMART snapshot to history: ", with: "无法将 SMART 快照保存到历史：")
        }
        if message.hasPrefix("SMART snapshot saved to history and "), message.hasSuffix(".") {
            let path = message
                .replacingOccurrences(of: "SMART snapshot saved to history and ", with: "")
                .dropLast()
            return "SMART 快照已保存到历史，并导出到 \(path)。"
        }
        if message.hasPrefix("SMART snapshot saved to history, but export failed: ") {
            return message.replacingOccurrences(of: "SMART snapshot saved to history, but export failed: ", with: "SMART 快照已保存到历史，但导出失败：")
        }
        if message.hasSuffix(" is not writable.") {
            return message.replacingOccurrences(of: " is not writable.", with: " 不可写。")
        }
        if message.hasPrefix("Could not create benchmark file at ") {
            return message.replacingOccurrences(of: "Could not create benchmark file at ", with: "无法创建测速文件：")
        }

        return message
    }

    func statusMessage(_ message: String?) -> String? {
        message.map(statusMessage)
    }

    func progressLabel(_ label: String) -> String {
        guard self == .simplifiedChinese else { return label }
        return Self.zhHansMessages[label] ?? label
    }

    func smartAttributeDisplay(_ attribute: SmartAttribute) -> SmartAttributeDisplay {
        SmartAttributeCatalog.display(for: attribute, language: self)
    }

    private static let zhHans: [String: String] = [
        "No Drives": "无磁盘",
        "Refresh to scan attached storage.": "刷新以扫描已连接的存储设备。",
        "Drives": "磁盘",
        "Show virtual disks": "显示虚拟磁盘",
        "Refresh disks and SMART data": "刷新磁盘和 SMART 数据",
        "Language": "语言",
        "Overview": "概览",
        "Benchmark": "测速",
        "Self-Tests": "自检",
        "External": "外接",
        "History": "历史",
        "Capacity": "容量",
        "Temperature": "温度",
        "Life Remaining": "剩余寿命",
        "Power-On Hours": "通电小时",
        "Media Errors": "介质错误",
        "Unavailable": "不可用",
        "Volumes": "卷宗",
        "No mounted volumes are mapped to this physical disk.": "没有挂载卷映射到这个物理磁盘。",
        "Providers": "数据来源",
        "Save SMART Snapshot": "保存 SMART 快照",
        "Choose Storage Folder": "选择存储文件夹",
        "Change Storage Folder": "更改存储文件夹",
        "Clear Storage Folder": "清除存储文件夹",
        "Default storage: App history database": "默认存储：应用历史数据库",
        "Selected storage:": "选择存储地址：",
        "Selected storage: Not selected": "选择存储地址：未选择",
        "Choose an optional folder for exported SMART snapshot JSON files.": "选择一个可选文件夹，用于导出 SMART 快照 JSON 文件。",
        "SMART Attributes": "SMART 属性",
        "ID": "ID",
        "Name": "名称",
        "Raw": "原始值",
        "Current": "当前",
        "Worst": "最差",
        "Threshold": "阈值",
        "Current, worst, and threshold are ATA normalized health values. NVMe and native macOS SMART usually do not provide them.": "当前、最差、阈值是 ATA SMART 的归一化健康分数；NVMe 和 macOS 原生 SMART 通常不提供这些值。",
        "Status": "状态",
        "Source": "来源",
        "No SMART Attributes": "无 SMART 属性",
        "SMART data is unavailable for this drive.": "此磁盘的 SMART 数据不可用。",
        "Profile": "配置",
        "No writable volume": "没有可写卷",
        "Run": "运行",
        "Cancel": "取消",
        "Save Results": "保存结果",
        "Target Folder": "目标文件夹",
        "Choose Target Folder": "选择目标文件夹",
        "Change Folder": "更改文件夹",
        "No target folder selected": "未选择目标文件夹",
        "Choose a writable target folder": "请选择可写目标文件夹",
        "Target folder is writable": "目标文件夹可写",
        "Target folder is not writable": "目标文件夹不可写",
        "Choose a writable folder where a temporary benchmark file can be created.": "选择一个可创建临时测速文件的可写文件夹。",
        "Use Folder": "使用文件夹",
        "Select a target folder before starting the speed test.": "开始测速前请选择目标文件夹。",
        "Benchmark writes a temporary test file to the selected volume.": "测速会在所选卷中写入一个临时测试文件。",
        "Benchmark writes a temporary test file to the selected target folder.": "测速会在所选目标文件夹中写入一个临时测试文件。",
        "Benchmark configuration and write target": "测速配置与写入目标",
        "Write target folder": "写入目标文件夹",
        "Write target folder:": "写入目标文件夹：",
        "Write tests can temporarily use free space and stress storage.": "写入测试会短暂占用可用空间并给存储带来压力。",
        "Write tests create a temporary file and may increase storage wear.": "写入测试会创建临时文件，并可能增加存储磨损。",
        "⚠️ Write tests create a temporary file and may increase storage wear. ⚠️": "⚠️ 写入测试会创建临时文件，并可能增加存储磨损。⚠️",
        "⚠️ Write test may increase storage wear. ⚠️": "⚠️ 写入测试可能增加存储磨损。⚠️",
        "Run Benchmark": "运行测速",
        "No Results": "无结果",
        "Run a benchmark profile to populate the read/write matrix.": "运行一个测速配置以生成读取/写入结果矩阵。",
        "Test": "测试",
        "Op": "操作",
        "Latency": "延迟",
        "Current Status": "当前状态",
        "Self-test log available": "有自检日志，点击展开",
        "No self-test log is available from current providers.": "当前数据来源没有提供自检日志。",
        "Provider Note": "数据来源说明",
        "Short and long self-test execution requires smartctl support for this drive. This version displays available logs and avoids starting destructive or vendor-specific tests automatically.": "短/长自检需要此磁盘支持 smartctl。当前版本只显示可用日志，避免自动启动破坏性或厂商专用测试。",
        "External Drive SMART": "外接磁盘 SMART",
        "Verify": "验证",
        "Driver Paths": "驱动路径",
        "No SAT SMART Driver bundle was detected in standard extension locations.": "标准扩展位置未检测到 SAT SMART Driver。",
        "Open SAT SMART Driver project": "打开 SAT SMART Driver 项目",
        "History & Reports": "历史与报告",
        "Include serials": "包含序列号",
        "Copy JSON": "复制 JSON",
        "Copy CSV": "复制 CSV",
        "Copy Text": "复制文本",
        "SMART Snapshots": "SMART 快照",
        "No saved snapshots yet.": "还没有保存的快照。",
        "Benchmark Runs": "测速记录",
        "No saved benchmark results yet.": "还没有保存的测速结果。",
        "Health": "健康",
        "Detected": "已检测",
        "Not detected": "未检测",
        "Refresh": "刷新",
        "SSD": "SSD",
        "HDD/Media": "HDD/介质"
    ]

    private static let zhHansMessages: [String: String] = [
        "No drives": "无磁盘",
        "Scanning disks...": "正在扫描磁盘...",
        "Reading SMART data...": "正在读取 SMART 数据...",
        "No physical drives found.": "未找到物理磁盘。",
        "Native SMART data is not exposed for this device.": "macOS 未暴露此设备的原生 SMART 数据。",
        "Native SMART keys parsed.": "已解析原生 SMART 键。",
        "SMART status not reported, device-specific keys available.": "未报告 SMART 状态，但存在设备专用键。",
        "smartctl was not found. Install smartmontools to enable deep SMART details.": "未找到 smartctl。安装 smartmontools 可启用更详细的 SMART 信息。",
        "smartctl not installed.": "未安装 smartctl。",
        "smartctl returned invalid JSON.": "smartctl 返回了无效 JSON。",
        "smartctl data parsed.": "已解析 smartctl 数据。",
        "Detailed SMART data available.": "可用详细 SMART 数据。",
        "smartctl returned partial data.": "smartctl 返回了部分数据。",
        "No SMART provider returned data.": "没有 SMART 数据来源返回数据。",
        "No SMART snapshot is available to save.": "没有可保存的 SMART 快照。",
        "SMART snapshot saved to history.": "SMART 快照已保存到历史。",
        "SMART snapshot saved to history, but the selected folder is unavailable.": "SMART 快照已保存到历史，但所选文件夹不可用。",
        "Warning indicators are present. Review highlighted attributes and keep backups current.": "检测到警告指标。请检查高亮属性并保持备份最新。",
        "Pre-fail indicators are present. Backup immediately and plan replacement.": "检测到预故障指标。请立即备份并计划更换磁盘。",
        "The drive reports failure. Stop non-essential writes and replace the drive.": "磁盘报告故障。请停止非必要写入并更换磁盘。",
        "SAT SMART Driver appears installed. Reconnect external USB-SATA drives after installation or reboot.": "已检测到 SAT SMART Driver。安装或重启后请重新连接外接 USB-SATA 磁盘。",
        "smartctl is installed. Some USB/SAT bridges may still require SAT SMART Driver on macOS.": "已安装 smartctl。部分 USB/SAT 桥接器在 macOS 上仍可能需要 SAT SMART Driver。",
        "External USB SMART often needs smartmontools and SAT SMART Driver; Thunderbolt/NVMe devices may expose data natively.": "外接 USB SMART 通常需要 smartmontools 和 SAT SMART Driver；Thunderbolt/NVMe 设备可能会原生暴露数据。",
        "Select a drive before running a benchmark.": "请先选择一个磁盘再运行测速。",
        "Select a target folder before running a benchmark.": "请先选择目标文件夹再运行测速。",
        "This drive has no mounted writable volume available for safe file-based benchmarking.": "此磁盘没有可用于安全文件测速的已挂载可写卷。",
        "Choose a writable target folder before starting.": "开始前请选择可写目标文件夹。",
        "Selected target folder no longer exists.": "所选目标文件夹已不存在。",
        "The benchmark target must be a folder.": "测速目标必须是文件夹。",
        "Selected target folder is not writable.": "所选目标文件夹不可写。",
        "Creating benchmark file": "正在创建测速文件",
        "Benchmark cancelled.": "测速已取消。",
        "Could not preallocate benchmark file.": "无法预分配测速文件。",
        "Could not prepare read-test data.": "无法准备读取测试数据。",
        "Write test failed.": "写入测试失败。",
        "Read test failed.": "读取测试失败。",
        "Benchmark complete": "测速完成",
        "Starting": "开始",
        "Complete": "完成",
        "Preview": "预览",
        "Preview complete": "预览完成",
        "Read": "读取",
        "Write": "写入",
        "Mixed": "混合",
        "Passed": "通过",
        "Failed": "失败",
        "Verified": "已验证"
    ]
}

struct SmartAttributeDisplay: Equatable {
    var title: String
    var subtitle: String
    var help: String
}

enum SmartAttributeTableColumns {
    static func showsNormalizedColumns(for attributes: [SmartAttribute]) -> Bool {
        attributes.contains { $0.current != nil || $0.worst != nil || $0.threshold != nil }
    }
}

enum SmartAttributeCatalog {
    private struct Entry {
        var englishTitle: String
        var chineseTitle: String
        var englishDescription: String
        var chineseDescription: String
    }

    static func display(for attribute: SmartAttribute, language: AppLanguage) -> SmartAttributeDisplay {
        let entry = entry(for: attribute)
        switch language {
        case .english:
            return SmartAttributeDisplay(
                title: entry?.englishTitle ?? attribute.name,
                subtitle: entry?.englishDescription ?? "Vendor or provider specific SMART field.",
                help: entry?.englishDescription ?? "Vendor or provider specific SMART field."
            )
        case .simplifiedChinese:
            return SmartAttributeDisplay(
                title: entry?.chineseTitle ?? attribute.name,
                subtitle: entry?.chineseDescription ?? "厂商或数据源提供的扩展 SMART 字段",
                help: "\(attribute.name)\n\(entry?.chineseDescription ?? "厂商或数据源提供的扩展 SMART 字段")"
            )
        }
    }

    private static func entry(for attribute: SmartAttribute) -> Entry? {
        let key = normalizedKey(attribute.name)
        if let entry = entriesByName[key] {
            return entry
        }
        return entriesByID[attribute.id.uppercased()]
    }

    private static func normalizedKey(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .lowercased()
            .split(separator: " ")
            .joined(separator: " ")
    }

    private static let entriesByName: [String: Entry] = {
        let entries: [(String, Entry)] = [
            ("Available Spare", Entry(
                englishTitle: "Available Spare",
                chineseTitle: "可用备用空间",
                englishDescription: "Remaining NVMe spare capacity.",
                chineseDescription: "NVMe 备用块剩余比例，低于阈值时需要关注。"
            )),
            ("Available Spare Threshold", Entry(
                englishTitle: "Available Spare Threshold",
                chineseTitle: "备用空间阈值",
                englishDescription: "Minimum spare capacity expected by the drive.",
                chineseDescription: "厂商设定的备用块最低健康阈值。"
            )),
            ("Percentage Used", Entry(
                englishTitle: "Percentage Used",
                chineseTitle: "寿命已用比例",
                englishDescription: "Estimated endurance consumed.",
                chineseDescription: "SSD 估算寿命消耗比例，数值越高表示磨损越多。"
            )),
            ("Temperature", Entry(
                englishTitle: "Temperature",
                chineseTitle: "温度",
                englishDescription: "Current device temperature.",
                chineseDescription: "磁盘当前温度，过高会影响性能和寿命。"
            )),
            ("Data Units Read", Entry(
                englishTitle: "Data Units Read",
                chineseTitle: "累计读取量",
                englishDescription: "Total host data read.",
                chineseDescription: "主机累计从磁盘读取的数据量。"
            )),
            ("Data Units Written", Entry(
                englishTitle: "Data Units Written",
                chineseTitle: "累计写入量",
                englishDescription: "Total host data written.",
                chineseDescription: "主机累计写入磁盘的数据量。"
            )),
            ("Media Errors", Entry(
                englishTitle: "Media Errors",
                chineseTitle: "介质错误",
                englishDescription: "Unrecovered media or data integrity errors.",
                chineseDescription: "无法恢复的介质或数据完整性错误计数。"
            )),
            ("Error Log Entries", Entry(
                englishTitle: "Error Log Entries",
                chineseTitle: "错误日志条目",
                englishDescription: "Number of controller error log entries.",
                chineseDescription: "控制器记录的错误日志条目数量。"
            )),
            ("Power-On Hours", Entry(
                englishTitle: "Power-On Hours",
                chineseTitle: "通电小时",
                englishDescription: "Total powered-on hours.",
                chineseDescription: "磁盘累计通电运行时间。"
            )),
            ("Power Cycles", Entry(
                englishTitle: "Power Cycles",
                chineseTitle: "通电次数",
                englishDescription: "Number of power cycle events.",
                chineseDescription: "磁盘累计上电/断电循环次数。"
            )),
            ("Power Cycle Count", Entry(
                englishTitle: "Power Cycle Count",
                chineseTitle: "通电次数",
                englishDescription: "Number of power cycle events.",
                chineseDescription: "磁盘累计上电/断电循环次数。"
            )),
            ("Unsafe Shutdowns", Entry(
                englishTitle: "Unsafe Shutdowns",
                chineseTitle: "异常断电次数",
                englishDescription: "Shutdowns without a clean notification.",
                chineseDescription: "未正常通知设备就断电或重启的次数。"
            )),
            ("Critical Warning", Entry(
                englishTitle: "Critical Warning",
                chineseTitle: "严重警告",
                englishDescription: "NVMe controller critical warning flags.",
                chineseDescription: "NVMe 控制器报告的严重健康警告标志。"
            )),
            ("Reallocated Sectors Count", Entry(
                englishTitle: "Reallocated Sectors Count",
                chineseTitle: "重映射扇区数",
                englishDescription: "Bad sectors remapped to spare area.",
                chineseDescription: "已被替换到备用区域的坏扇区数量。"
            )),
            ("Current Pending Sector", Entry(
                englishTitle: "Current Pending Sector",
                chineseTitle: "待定扇区数",
                englishDescription: "Unstable sectors waiting for remap.",
                chineseDescription: "读取不稳定、等待重映射确认的扇区数量。"
            )),
            ("Current Pending Sector Count", Entry(
                englishTitle: "Current Pending Sector Count",
                chineseTitle: "待定扇区数",
                englishDescription: "Unstable sectors waiting for remap.",
                chineseDescription: "读取不稳定、等待重映射确认的扇区数量。"
            )),
            ("Offline Uncorrectable", Entry(
                englishTitle: "Offline Uncorrectable",
                chineseTitle: "离线不可校正错误",
                englishDescription: "Uncorrectable errors found by offline scans.",
                chineseDescription: "离线扫描中发现且无法校正的错误数量。"
            )),
            ("Offline Uncorrectable Sector Count", Entry(
                englishTitle: "Offline Uncorrectable Sector Count",
                chineseTitle: "离线不可校正扇区",
                englishDescription: "Uncorrectable sectors found by offline scans.",
                chineseDescription: "离线扫描中发现且无法校正的扇区数量。"
            )),
            ("UDMA CRC Error Count", Entry(
                englishTitle: "UDMA CRC Error Count",
                chineseTitle: "传输 CRC 错误",
                englishDescription: "Interface data transfer CRC errors.",
                chineseDescription: "线缆、接口或桥接器传输中出现的 CRC 错误计数。"
            )),
            ("Wear Leveling Count", Entry(
                englishTitle: "Wear Leveling Count",
                chineseTitle: "磨损均衡计数",
                englishDescription: "SSD erase block wear indicator.",
                chineseDescription: "SSD 闪存擦写磨损均衡相关指标。"
            )),
            ("Media Wearout Indicator", Entry(
                englishTitle: "Media Wearout Indicator",
                chineseTitle: "介质磨损指标",
                englishDescription: "SSD media endurance indicator.",
                chineseDescription: "SSD 介质寿命和磨损程度指标。"
            )),
            ("Total LBAs Written", Entry(
                englishTitle: "Total LBAs Written",
                chineseTitle: "累计写入 LBA",
                englishDescription: "Total logical blocks written.",
                chineseDescription: "磁盘累计写入的逻辑块数量。"
            )),
            ("Total LBAs Read", Entry(
                englishTitle: "Total LBAs Read",
                chineseTitle: "累计读取 LBA",
                englishDescription: "Total logical blocks read.",
                chineseDescription: "磁盘累计读取的逻辑块数量。"
            ))
        ]
        return Dictionary(uniqueKeysWithValues: entries.map { (normalizedKey($0.0), $0.1) })
    }()

    private static let entriesByID: [String: Entry] = [
        "0X05": entriesByName[normalizedKey("Reallocated Sectors Count")]!,
        "0XC5": entriesByName[normalizedKey("Current Pending Sector Count")]!,
        "0XC6": entriesByName[normalizedKey("Offline Uncorrectable Sector Count")]!,
        "0XC7": entriesByName[normalizedKey("UDMA CRC Error Count")]!
    ]
}

private struct AppLanguageEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .english
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageEnvironmentKey.self] }
        set { self[AppLanguageEnvironmentKey.self] = newValue }
    }
}
