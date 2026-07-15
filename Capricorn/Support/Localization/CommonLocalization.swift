// SPDX-License-Identifier: GPL-3.0-only
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
















    func statusMessage(_ message: String) -> String {
        guard self == .simplifiedChinese else { return message }

        if let exact = Self.zhHansMessages[message] {
            return exact
        }
        if message.hasPrefix("Last refreshed ") {
            return message.replacingOccurrences(of: "Last refreshed ", with: "上次刷新 ")
        }
        if message.hasPrefix("Disk action failed: ") {
            return message.replacingOccurrences(of: "Disk action failed: ", with: "磁盘操作失败：")
        }
        if message.hasPrefix("Open file inspection failed: ") {
            return message.replacingOccurrences(of: "Open file inspection failed: ", with: "查看占用程序失败：")
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
        if message == "Read warm-up" {
            return "读取预热"
        }
        if message == "Write warm-up" {
            return "写入预热"
        }
        if message == "Mixed warm-up" {
            return "混合预热"
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
        if message.hasPrefix("Loop "), let separatorRange = message.range(of: " - ") {
            let round = message[..<separatorRange.lowerBound].replacingOccurrences(of: "Loop ", with: "")
            var item = String(message[separatorRange.upperBound...])
            if item.hasSuffix(" Read") {
                item = String(item.dropLast(" Read".count)) + " 读取"
            } else if item.hasSuffix(" Write") {
                item = String(item.dropLast(" Write".count)) + " 写入"
            } else if item.hasSuffix(" Mixed") {
                item = String(item.dropLast(" Mixed".count)) + " 混合"
            }
            return "循环第 \(round) 轮 - \(item)"
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
        if message.hasPrefix("Async read test failed to submit: ") {
            return message.replacingOccurrences(of: "Async read test failed to submit: ", with: "异步读取请求提交失败：")
        }
        if message.hasPrefix("Async write test failed to submit: ") {
            return message.replacingOccurrences(of: "Async write test failed to submit: ", with: "异步写入请求提交失败：")
        }

        return message
    }

    func statusMessage(_ message: String?) -> String? {
        message.map(statusMessage)
    }

    func progressLabel(_ label: String) -> String {
        guard self == .simplifiedChinese else { return label }
        if label.hasPrefix("Loop "), let separatorRange = label.range(of: " - ") {
            let round = label[..<separatorRange.lowerBound].replacingOccurrences(of: "Loop ", with: "")
            var item = String(label[separatorRange.upperBound...])
            if item.hasSuffix(" Read") {
                item = String(item.dropLast(" Read".count)) + " 读取"
            } else if item.hasSuffix(" Write") {
                item = String(item.dropLast(" Write".count)) + " 写入"
            } else if item.hasSuffix(" Mixed") {
                item = String(item.dropLast(" Mixed".count)) + " 混合"
            }
            return "循环第 \(round) 轮 - \(item)"
        }
        return Self.zhHansMessages[label] ?? label
    }


    private static let zhHans: [String: String] = [
        "No Drives": "无磁盘",
        "Refresh to scan attached storage.": "刷新以扫描已连接的存储设备。",
        "Drives": "磁盘",
        "Refresh Disks": "刷新磁盘",
        "Next Function": "下一个功能",
        "Previous Function": "上一个功能",
        "Show virtual disks": "显示虚拟磁盘",
        "Refresh disks and SMART data": "刷新磁盘和 SMART 数据",
        "Language": "语言",
        "Settings": "设置",
        "Include serials in reports": "报告中包含序列号",
        "Use Tab to switch feature pages": "使用 Tab 切换功能页面",
        "Automatic detection": "自动检测",
        "Choose…": "选择…",
        "Automatic": "自动",
        "The selected smartctl path is not executable.": "所选 smartctl 路径不可执行。",
        "Control-Tab and Control-Shift-Tab always switch feature pages. Disable plain Tab switching to restore standard keyboard focus traversal.": "Control-Tab 和 Control-Shift-Tab 始终用于切换功能页面。关闭普通 Tab 切换后，可恢复标准键盘焦点遍历。",
        "Choose": "选择",
        "Choose the smartctl executable.": "选择 smartctl 可执行文件。",
        "Open Settings": "打开设置",
        "Open Capricorn GitHub repository": "打开 Capricorn GitHub 仓库",
        "Capricorn GitHub repository introduction": "GitHub 仓库：github.com/LexTheAries2209/Capricorn。代码、版本说明、发布包与问题反馈均在仓库维护，欢迎通过 Issue 或 Pull Request 参与改进。",
        "Overview": "概览",
        "Benchmark": "测速",
        "Live Activity": "实时活动",
        "Self-Tests": "自检",
        "External": "外接",
        "History": "历史",
        "Capacity": "容量",
        "Temperature": "温度",
        "Life Remaining": "剩余寿命",
        "Power-On Hours": "通电小时",
        "Media Errors": "介质错误",
        "Format": "格式",
        "Unavailable": "不可用",
        "Volumes": "卷宗",
        "No mounted volumes are mapped to this physical disk.": "没有挂载卷映射到这个物理磁盘。",
        "Network Drive": "网络硬盘",
        "Network volume": "网络卷",
        "SD Card": "SD 卡",
        "Disk Actions": "磁盘操作",
        "Mount": "装载",
        "Unmount": "卸载",
        "Force Unmount": "强制卸载",
        "Eject": "推出",
        "View Open Files": "查看占用程序",
        "Check Log": "检查日志",
        "Detailed Check": "详细检查",
        "First Aid…": "急救…",
        "Disk First Aid": "磁盘急救",
        "Preparing First Aid": "正在准备磁盘急救",
        "Capricorn is verifying current volume identities, formats, and repair eligibility.": "Capricorn 正在核对当前卷的身份、格式和急救资格。",
        "First Aid can modify filesystem metadata. It is not data recovery and cannot repair physical media failure.": "磁盘急救可能修改文件系统元数据。它不是数据恢复，也无法修复物理介质故障。",
        "First Aid modifies filesystem metadata on the selected volumes.": "磁盘急救会修改所选卷的文件系统元数据。",
        "Select Volumes": "选择卷宗",
        "No volume is selected by default. Only external APFS and ExFAT volumes can run direct First Aid.": "默认不会选择任何卷。只有外接 APFS 和 ExFAT 卷可以直接执行磁盘急救。",
        "Required Confirmations": "必要确认",
        "Important data is backed up, or I accept the risk of proceeding without a backup.": "重要数据已有备份，或我接受没有备份就继续的风险。",
        "All transfers, benchmarks, and disk writes are stopped, and power and cables are stable.": "所有传输、测速和磁盘写入都已停止，供电与线缆连接稳定。",
        "SMART shows a warning. I understand First Aid cannot repair physical media problems.": "SMART 显示警告。我理解磁盘急救无法修复物理介质问题。",
        "Run First Aid": "运行磁盘急救",
        "Direct First Aid Unavailable": "无法直接执行磁盘急救",
        "First Aid Unavailable": "磁盘急救不可用",
        "Open Disk Utility": "打开磁盘工具",
        "Recovery Instructions": "恢复模式说明",
        "Copy CHKDSK Example": "复制 CHKDSK 示例",
        "Windows CHKDSK Guide": "Windows CHKDSK 指南",
        "Select": "选择",
        "for First Aid": "进行磁盘急救",
        "Unknown": "未知",
        "Ready for First Aid": "可执行磁盘急救",
        "This filesystem is not supported for native First Aid on macOS.": "macOS 不支持对该文件系统执行原生磁盘急救。",
        "macOS cannot natively repair NTFS. Use Windows CHKDSK or the filesystem vendor's tool.": "macOS 无法原生修复 NTFS。请使用 Windows CHKDSK 或文件系统厂商提供的工具。",
        "Startup and system volumes must be repaired from macOS Recovery.": "启动卷和系统卷必须在 macOS 恢复模式中修复。",
        "Direct First Aid is limited to external or removable disks.": "直接磁盘急救仅适用于外接或可移除磁盘。",
        "Network volumes do not expose a local repair target.": "网络卷没有可供本机修复的目标。",
        "Virtual disks are not eligible for direct First Aid.": "虚拟磁盘不具备直接磁盘急救资格。",
        "The volume or media is read-only and cannot be repaired.": "卷或介质为只读，无法修复。",
        "Unlock the volume before running First Aid.": "请先解锁卷，再运行磁盘急救。",
        "The volume has no stable local device identifier.": "该卷没有稳定的本地设备标识。",
        "The current disk information could not be verified. Refresh and try again.": "无法验证当前磁盘信息，请刷新后重试。",
        "The volume identifier changed before First Aid started.": "磁盘急救启动前，卷设备标识发生了变化。",
        "The volume UUID changed before First Aid started.": "磁盘急救启动前，卷 UUID 发生了变化。",
        "The volume is no longer attached to the selected physical disk.": "该卷已不再连接到所选物理磁盘。",
        "The volume format changed before First Aid started.": "磁盘急救启动前，卷格式发生了变化。",
        "The disk information could not be refreshed before First Aid.": "磁盘急救启动前无法刷新磁盘信息。",
        "System disks must be repaired from macOS Recovery.": "系统磁盘必须在 macOS 恢复模式中修复。",
        "SMART reports a failing device. Back up data and replace the disk instead of repairing it here.": "SMART 报告设备正在故障。请备份数据并更换磁盘，不要在此处修复。",
        "No external APFS or ExFAT volume is eligible for direct First Aid.": "没有符合条件的外接 APFS 或 ExFAT 卷可直接执行磁盘急救。",
        "First Aid preflight did not produce a repair plan.": "磁盘急救预检没有生成修复计划。",
        "First Aid is unavailable.": "磁盘急救不可用。",
        "First Aid is running. Do not disconnect the disk or quit Capricorn.": "磁盘急救正在运行。请勿断开磁盘或退出 Capricorn。",
        "First Aid Progress": "磁盘急救进度",
        "The current volume will finish safely; remaining volumes will be skipped.": "当前卷会安全完成，剩余卷将跳过。",
        "Refreshing disk and SMART information after First Aid.": "磁盘急救完成后正在刷新磁盘和 SMART 信息。",
        "First Aid completed with issues.": "磁盘急救完成，但存在问题。",
        "First Aid completed.": "磁盘急救已完成。",
        "First Aid Succeeded": "急救成功",
        "First Aid Failed": "急救失败",
        "Skipped": "已跳过",
        "System Output": "系统输出",
        "Open Files Found": "发现占用文件的程序",
        "Close these applications before First Aid. Capricorn will not terminate processes or force-unmount the disk.": "请在磁盘急救前关闭这些应用。Capricorn 不会终止进程或强制卸载磁盘。",
        "Back": "返回",
        "Check Again": "重新检查",
        "Try Anyway": "仍然尝试",
        "Stop After Current Volume": "完成当前卷后停止",
        "Stopping after the current volume finishes…": "当前卷完成后停止…",
        "Disk Check Report": "磁盘检查报告",
        "Runs diskutil verification and shows the complete system log.": "运行 diskutil 验证并显示完整系统日志。",
        "Runs read-only filesystem-specific fsck checks where macOS provides a checker.": "在 macOS 提供检查器的格式上运行只读文件系统详细检查。",
        "Disk check is running. Keep this window open to monitor progress.": "磁盘检查正在运行。请保持此窗口打开以查看进度。",
        "The check reported issues or unsupported targets.": "检查报告了问题或不支持的目标。",
        "No issues were reported by the completed checks.": "已完成的检查未报告问题。",
        "Preparing Disk Check": "正在准备磁盘检查",
        "The command list is being prepared.": "正在准备检查命令列表。",
        "Completed": "已完成",
        "Cancel Check": "取消检查",
        "Running": "正在运行",
        "Waiting for command output...": "正在等待命令输出...",
        "Unsupported": "不支持",
        "Exit Code": "退出码",
        "Open Files Using Disk": "占用此磁盘的程序",
        "These processes currently have files open on the selected disk.": "这些进程当前在所选磁盘上打开了文件。",
        "Disk Action Failed": "磁盘操作失败",
        "No Occupying Processes": "未发现占用程序",
        "No process with open files was reported for this disk.": "系统未报告有进程正在打开此磁盘上的文件。",
        "Program": "程序",
        "User": "用户",
        "Path": "路径",
        "Close": "关闭",
        "Rename Volume": "重命名卷宗",
        "Reveal in Finder": "在 Finder 中显示",
        "Disconnect": "断开",
        "Enter a new name for the selected volume.": "输入所选卷宗的新名称。",
        "Rename": "重命名",
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
        "Runs": "测试次数",
        "Test Size": "测试文件大小",
        "Data Pattern": "数据模式",
        "Custom Test Groups": "自定义测试项目组",
        "Each group creates read/write tests; mixed adds a 30% write / 70% read item.": "每个项目组会生成读取/写入测试；开启混合会额外添加约 30% 写入 / 70% 读取的混合项。",
        "Engine": "引擎",
        "Sync": "同步",
        "Async": "异步",
        "Async uses POSIX AIO queue depth; Sync uses worker threads with blocking file I/O.": "异步使用 POSIX AIO 队列深度；同步使用工作线程执行阻塞式文件 I/O。",
        "Loop repeats the custom groups until you stop it manually.": "循环会重复执行自定义项目组，直到手动停止。",
        "Loop mode ignores test count and extra trimmed testing.": "循环模式会忽略测试次数和加量测试去极值。",
        "Add Group": "添加项目组",
        "Type": "类型",
        "Block Size": "块大小",
        "Mixed": "混合",
        "Delete": "删除",
        "Maximum 4 groups.": "最多 4 个项目组。",
        "Trimmed Avg": "去极值平均",
        "Trim Outliers": "加量测试去极值",
        "Off": "关闭",
        "On": "开启",
        "Run two extra measured passes, discard fastest and slowest, then average the rest.": "额外执行 2 轮正式测量，去掉最快和最慢后再平均。",
        "No writable volume": "没有可写卷",
        "Run": "运行",
        "Cancel": "取消",
        "Save Results": "保存结果",
        "Live Disk Activity": "磁盘实时活动",
        "Saved Benchmark Activity": "已保存测速曲线",
        "Monitors total I/O reported by macOS for the selected physical disk.": "监控 macOS 报告的所选物理磁盘总 I/O。",
        "Network drives do not provide per-disk IOKit activity counters.": "网络硬盘不提供本机单盘 IOKit 活动计数。",
        "Drive": "磁盘",
        "Sample Interval": "采样间隔",
        "Start Monitoring": "开始监控",
        "Stop Monitoring": "停止监控",
        "Save to History": "保存到历史",
        "Clear Chart": "清空图表",
        "Large File Workload": "大文件负载",
        "Workload": "负载",
        "Large File Size": "大文件大小",
        "Loop": "循环",
        "Start Workload": "开始负载",
        "Stop Workload": "停止负载",
        "Full Disk (95%)": "全盘 (95%)",
        "Large file workload creates temporary files and may stress or wear storage.": "大文件负载会创建临时文件，并可能给存储带来持续压力和写入磨损。",
        "Workload engine: SEQ1M Q4T4 async, 4 MiB chunks, 0 Fill.": "负载引擎：SEQ1M Q4T4 异步，4 MiB 块，0 填充。",
        "Choose a writable folder where large temporary workload files can be created.": "选择一个可创建大临时负载文件的可写文件夹。",
        "Workload target folder must be on the selected drive": "负载目标文件夹必须位于当前选中的磁盘",
        "Not enough free space for the selected workload": "可用空间不足，无法运行所选负载",
        "Selected workload size exceeds available free space": "所选负载大小超过可用空间",
        "Elapsed": "已运行",
        "Samples": "采样点",
        "samples": "个采样点",
        "Peak": "峰值",
        "Average": "平均",
        "Live Activity History": "实时活动监控",
        "No saved activity records yet.": "还没有保存的实时活动记录。",
        "No visible activity records. Hidden activity records can be restored below.": "当前没有显示中的实时活动记录，隐藏记录可在下方找回。",
        "Load Chart": "加载图表",
        "Activity record saved to history.": "实时活动记录已保存到历史。",
        "Could not save activity record.": "无法保存实时活动记录。",
        "Target Folder": "目标文件夹",
        "Choose Target Folder": "选择目标文件夹",
        "Change Folder": "更改文件夹",
        "No target folder selected": "未选择目标文件夹",
        "Choose a writable target folder": "请选择可写目标文件夹",
        "Target folder is writable": "目标文件夹可写",
        "Target folder is not writable": "目标文件夹不可写",
        "Target folder is writable but not on selected drive": "目标文件夹可写，但不在当前选中的磁盘上",
        "Benchmark will measure the target folder volume, not the selected drive.": "测速会测量目标文件夹所在卷，而不是当前选中的磁盘。",
        "Not enough free space for the smallest test size": "可用空间不足，无法运行最小测试文件",
        "Selected test size exceeds available free space": "所选测试文件大小超过可用空间",
        "Choose a writable folder where a temporary benchmark file can be created.": "选择一个可创建临时测速文件的可写文件夹。",
        "Use Folder": "使用文件夹",
        "Select a target folder before starting the speed test.": "开始测速前请选择目标文件夹。",
        "Benchmark writes a temporary test file to the selected volume.": "测速会在所选卷中写入一个临时测试文件。",
        "Benchmark writes a temporary test file to the selected target folder.": "测速会在所选目标文件夹中写入一个临时测试文件。",
        "Benchmark writes temporary test files to the selected target folder.": "测速会在所选目标文件夹中写入临时测试文件。",
        "Benchmark writes a complete temporary test file to the selected target folder.": "测速会在所选目标文件夹中写入一个完整的临时测试文件。",
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
        "Run a benchmark profile to populate the write/read matrix.": "运行一个测速配置以生成写入/读取结果矩阵。",
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
        "Use this when SMART data is unavailable or limited for an external drive.": "当外接磁盘 SMART 无信息或来源有限时，可在这里检查支持状态并验证。",
        "Install smartmontools": "安装 smartmontools",
        "Capricorn does not bundle smartctl. Install smartmontools to enable detailed SMART data when macOS native fields are limited.": "Capricorn 不内置 smartctl。当 macOS 原生 SMART 字段有限时，安装 smartmontools 可启用更详细的 SMART 数据。",
        "After installation, refresh Capricorn. Apple Silicon Homebrew usually installs smartctl at /opt/homebrew/bin/smartctl; Intel Homebrew usually uses /usr/local/bin/smartctl.": "安装后请刷新 Capricorn。Apple Silicon 的 Homebrew 通常会把 smartctl 安装到 /opt/homebrew/bin/smartctl；Intel Mac 的 Homebrew 通常使用 /usr/local/bin/smartctl。",
        "Open Homebrew smartmontools formula": "打开 Homebrew smartmontools formula",
        "No SAT SMART Driver bundle was detected in standard extension locations.": "标准扩展位置未检测到 SAT SMART Driver。",
        "Open SAT SMART Driver project": "打开 SAT SMART Driver 项目",
        "History & Reports": "历史与报告",
        "Include serials": "包含序列号",
        "Copy JSON": "复制 JSON",
        "Copy CSV": "复制 CSV",
        "Copy Text": "复制文本",
        "SMART Snapshots": "SMART 快照",
        "No saved snapshots yet.": "还没有保存的快照。",
        "No visible snapshots. Hidden snapshots can be restored below.": "当前没有显示中的快照，隐藏快照可在下方找回。",
        "Benchmark Runs": "测速记录",
        "No saved benchmark results yet.": "还没有保存的测速结果。",
        "No visible benchmark results. Hidden benchmark results can be restored below.": "当前没有显示中的测速记录，隐藏记录可在下方找回。",
        "Hide from history": "从历史中隐藏",
        "Hide All": "全部隐藏",
        "Manage Hidden Records": "管理隐藏记录",
        "Restore": "恢复",
        "Restore All": "恢复全部",
        "Hidden records remain in the local database and can be restored here.": "隐藏记录仍保留在本地数据库中，可在这里找回。",
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
        "Running disk action...": "正在执行磁盘操作...",
        "Disk action completed.": "磁盘操作已完成。",
        "Disk action failed:": "磁盘操作失败：",
        "Inspecting open files...": "正在查看占用程序...",
        "Open file inspection completed.": "占用程序查看完成。",
        "System internal disks cannot be mounted, unmounted, or ejected from Capricorn.": "Capricorn 不允许装载、卸载或推出系统内置磁盘。",
        "No physical drives found.": "未找到物理磁盘。",
        "No physical or network drives found.": "未找到物理或网络磁盘。",
        "Network volumes do not expose local SMART data.": "网络卷不提供本机 SMART 数据。",
        "Network drives do not provide per-disk IOKit activity counters.": "网络硬盘不提供本机单盘 IOKit 活动计数。",
        "SD cards do not expose standard SMART health data on macOS.": "SD 卡在 macOS 上不提供标准 SMART 健康数据。",
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
        "Creating benchmark files": "正在创建测速文件",
        "Preparing test file": "正在准备测试文件",
        "Preparing complete test file": "正在准备完整测试文件，不计入成绩",
        "Flushing prepared test file": "正在刷新准备文件",
        "Flushing writes": "正在刷新写入",
        "Waiting between tests": "测试间隔等待中",
        "Waiting between passes": "轮次间隔等待中",
        "Loop running": "循环测试中",
        "Loop stopped": "循环测试已停止",
        "Benchmark cancelled.": "测速已取消。",
        "Could not preallocate benchmark file.": "无法预分配测速文件。",
        "Could not resize benchmark file.": "无法调整测速文件大小。",
        "Could not flush prepared benchmark file.": "无法刷新准备好的测速文件。",
        "Could not flush benchmark writes.": "无法刷新测速写入。",
        "Async benchmark wait failed.": "异步测速等待失败。",
        "Async write test failed.": "异步写入测试失败。",
        "Async read test failed.": "异步读取测试失败。",
        "Could not prepare read-test data.": "无法准备读取测试数据。",
        "Write test failed.": "写入测试失败。",
        "Read test failed.": "读取测试失败。",
        "Benchmark complete": "测速完成",
        "Starting": "开始",
        "Complete": "完成",
        "Starting workload": "正在启动负载",
        "Preparing read workload file": "正在准备读取负载文件",
        "Reading workload file": "正在读取负载文件",
        "Writing workload file": "正在写入负载文件",
        "Running mixed workload": "正在运行读写混合负载",
        "Flushing workload writes": "正在刷新负载写入",
        "Cleaning workload files": "正在清理负载文件",
        "Workload complete": "负载完成",
        "Workload stopped": "负载已停止",
        "Stopping workload": "正在停止负载",
        "Workload target folder must be on the selected drive.": "负载目标文件夹必须位于当前选中的磁盘。",
        "Could not flush workload writes.": "无法刷新负载写入。",
        "Write workload failed.": "写入负载失败。",
        "Read workload failed.": "读取负载失败。",
        "Preview": "预览",
        "Preview complete": "预览完成",
        "Read": "读取",
        "Write": "写入",
        "Mixed": "混合",
        "Passed": "通过",
        "Failed": "失败",
        "Verified": "已验证",
        "Preparing First Aid...": "正在准备磁盘急救…",
        "First Aid is ready for confirmation.": "磁盘急救已准备好，等待确认。",
        "First Aid preflight failed.": "磁盘急救预检失败。",
        "Open files were found on the selected volume.": "所选卷上发现占用文件的程序。",
        "First Aid will stop after the current volume.": "磁盘急救将在当前卷完成后停止。",
        "First Aid is running...": "磁盘急救正在运行…",
        "Refreshing disk information after First Aid...": "磁盘急救完成后正在刷新磁盘信息…",
        "First Aid completed with issues.": "磁盘急救完成，但存在问题。",
        "First Aid completed.": "磁盘急救已完成。",
        "Could not inspect open files before First Aid.": "无法在磁盘急救前检查占用文件。",
        "No output.": "没有输出。"
    ]
}

struct BenchmarkConfigurationDescription: Equatable {
    var profileUse: String
    var runs: String
    var fileSize: String
    var dataPattern: String
    var testTerms: String
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
