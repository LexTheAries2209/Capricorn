# Capricorn

Formerly DiskSpeedTest.

Capricorn is a local macOS utility for DIT-style disk inspection, SMART health checks, storage benchmarking, and live disk activity monitoring. It is designed for users who need to quickly identify local drives, external SSDs, mounted network volumes, memory cards, and benchmark targets before copying, backing up, or stress-testing storage.

Capricorn 是一个本地 macOS 工具，用于 DIT 场景下的磁盘检查、SMART 健康状态查看、存储测速和实时磁盘活动监控。它面向需要快速确认本机硬盘、外接 SSD、已挂载网络卷、存储卡和测速目标位置的工作流。

[Latest Release / 最新版本](https://github.com/LexTheAries2209/Capricorn/releases/latest): `v2.1.1`

Bilingual release notes / 双语发布说明：[docs/releases/v2.1.1.md](docs/releases/v2.1.1.md)

---

## 中文说明

### 项目定位

Capricorn 不是完整的磁盘维修工具，也不会直接对裸设备写入。它的目标是把磁盘识别、SMART 信息、测速、实时活动曲线和历史记录放在一个本地工具里，方便在拷贝、备份、外接盘测试和现场 DIT 工作前快速判断存储状态。

### 下载和安装

1. 前往 [GitHub Releases](https://github.com/LexTheAries2209/Capricorn/releases/latest) 下载 `Capricorn-v2.1.1-macOS.zip`。
2. 解压后把 `Capricorn V2.1.1.app` 放到 `Applications` 或你的本地工具目录。
3. 首次打开时，如果 macOS Gatekeeper 提示来自互联网下载的 App，请在 Finder 中右键点击 App 后选择“打开”，或在“系统设置 > 隐私与安全性”中允许打开。

V2.1.1 的中文发布说明见 [docs/releases/v2.1.1.zh-CN.md](docs/releases/v2.1.1.zh-CN.md)。

典型用途：

- 查看 Mac 内置硬盘、外接 SSD、读卡器、SD 卡和网络卷的基本信息。
- 查看 macOS 原生 SMART 或可选 `smartctl` 提供的健康数据。
- 对指定目标文件夹执行顺序、随机、读取、写入和混合测速。
- 使用同步或 POSIX AIO 队列深度引擎测试 SSD 峰值和持续性能。
- 在实时活动页观察磁盘读写曲线，并主动生成大文件读取、写入或读写混合负载。
- 保存 SMART、测速和实时活动历史，并按需要隐藏或恢复记录。
- 通过磁盘右键菜单执行装载、卸载、推出、重命名、Finder 定位、占用程序查看和只读检查。

### 核心功能

- 识别本机物理磁盘、外接磁盘、普通挂载分区、网络卷和存储卡。
- 对 APFS、普通外接分区和网络挂载路径做目标文件夹归属判断，避免测错卷。
- 在磁盘概览中显示文件系统格式，并在 SMART、测速和历史页显示当前查看的磁盘名称。
- 右键磁盘菜单支持安全的装载、卸载、强制卸载、推出、重命名、Finder 定位、刷新和网络卷断开操作。
- 内置系统盘保护，避免从 Capricorn 对系统内置盘执行装载、卸载或推出操作。
- 支持查看占用所选磁盘的进程，并在卸载、推出失败时显示可能占用磁盘的程序列表。
- 在设置中开启“检查与修复”后，右键磁盘菜单会提供快速检查、深度检查和急救，并展示 `diskutil` 或 macOS 原生文件系统检查器的输出。
- SMART 页面显示健康状态、温度、寿命、通电小时、介质错误、不安全关机次数和数据来源。
- 可在设置中按需显示 ATA、NVMe 和 SAT 设备的 SMART 自检状态、快速/完整自检、自动轮询、中止操作、最近记录和原始 smartctl 输出回退；该界面默认隐藏，概览仅在启用后显示最近一次设备自检摘要。
- 启用自检界面后，操作会根据设备能力和传输层禁用不支持的目标；系统盘自检仍需在设置中单独允许，macOS NVMe 不支持的 admin command 不会被强行执行。
- smartctl 7.5 数据兼容性得到加强，保留诊断信息；默认避免为 SMART 刷新唤醒休眠磁盘，并在无法安全识别设备类型时保留上一份数据。
- 本地物理磁盘的 SMART 页面始终保留可折叠的“外接磁盘 SMART”支持区；内置磁盘或同时检测到 smartctl 与 SAT SMART Driver 时默认折叠，缺少依赖或尚未验证的外接磁盘默认展开。
- “驱动诊断”集中显示 smartctl 目标路径、设备类型、协议、打开错误和明确标注的 SAT SMART Driver 路径；未检测到 SAT 驱动时提供开源项目仓库入口，检测成功后不再显示重复的安装或重连提示。
- SMART 属性页支持独立纵向滚动、折叠历史自检记录和清除状态消息；常见外接 ATA 字段提供中文解释，Total LBAs Read/Written 会按逻辑块大小换算为可读容量，同时保留原始 LBA 信息。
- 内置 177 条物理硬盘型号规则，覆盖 Samsung、Intel、Solidigm、SK hynix、Micron、Crucial、KIOXIA、Toshiba、WD、Seagate、YMTC 和致钛的消费级、OEM、数据中心及企业系列；已足够精简或无法确认的型号继续显示系统原始名称。
- 侧边栏优先显示最大容量卷的名称，下一行显示硬盘商品名/型号，再显示序列号；宽度与行距受到约束，便于区分多块同型号硬盘。
- 侧边栏和概览显示物理磁盘或网络卷的总容量、已用和可用空间；APFS 共享容器只统计一次可用空间，避免重复汇总。
- SMART 温度会按数据源区分单位：原生 Kelvin 数值同时显示换算后的摄氏度，已是摄氏度的数值保持摄氏度显示。概览中 `70–85 °C` 标黄、`85 °C` 及以上标红，但温度不参与整体 SMART 健康等级。
- NVMe 累计读取量和写入量会把 macOS 原生与 `smartctl` 的 Data Units 转换为 TB，并保留原始 units 计数。
- macOS 原生 SMART 优先，可选使用用户已安装的 `smartctl` 获取更完整的 ATA/NVMe 数据。
- 对 SD/SDXC 读卡器和网络卷显示有限支持说明，避免把无 SMART 数据误判为硬盘故障。
- 支持默认、峰值/NVMe、真实场景、演示和自定义测速配置。
- 自定义测速最多 4 个测试项目组，可选择 SEQ/RND、块大小、Q、T 和混合测试。
- 每个测速配置可以选择同步或异步引擎；自定义配置可选择循环。
- 测速文件大小从 1 GiB 起，支持 Random 和 0 Fill 数据模式。
- 点击测速结果矩阵左侧的绿色项目按钮，可以沿用当前引擎、文件大小和数据模式只测试该项目一次；单项测试固定关闭加量测试并保留写入确认。
- “提高小块文件测试效率”可按 5%、10%、20%、30% 或 50% 缩减 4 KiB、16 KiB 和 64 KiB 项目的实际测试文件量，默认关闭，首次开启默认为 20%。
- 测速目标跟随侧边栏所选硬盘，默认使用该盘第一个已挂载且可写的分区，并支持选择同盘分区或文件夹；启动前会再次校验目标归属。
- 测速页显示实时磁盘活动曲线，保存测速结果时会保存本次曲线样本。
- 实时活动页支持 0.1s、0.2s、0.5s、1s 采样间隔、图表保留和保存到历史。
- 实时活动页的监控磁盘完全跟随左侧侧边栏；监控或负载运行期间锁定其他磁盘，设备消失时停止任务并显示错误，停止后可切换磁盘且不同磁盘的未保存样本不会串联。
- 大文件负载默认使用当前物理磁盘按设备标识排序后的第一个已挂载可写分区，并支持选择同盘分区或文件夹；只读、未挂载和跨盘目标会被拒绝，目标选择按磁盘分别记忆。
- 停止实时活动监控后可以“继续监控”并从现有图表续接；“开始监控”仍会清空图表并创建新的监控段。
- 实时活动大文件负载支持读取、写入、读写混合、固定大小和全盘 95% 模式。
- 历史页支持 SMART、测速、实时活动记录的隐藏、管理隐藏记录和恢复；记录优先按完整硬件序列号匹配，无可用序列号时使用卷 UUID 兜底。V2.0.1 使用新的 `CapricornHistory` 数据库，不兼容旧版历史记录。
- 历史页的旧 JSON、CSV 和纯文本复制功能已移除，等待新的统一导出设计。
- SMART 快照导出为紧凑 CSV，在同一属性表中加入磁盘身份、设备类型、卷 UUID 和外接盘卷信息；中文界面额外包含中文名称，英文界面使用 SMART 属性的英文名称和说明。
- SMART 页面可使用 `Command-S` 保存 CSV 快照，保存按钮提供对应快捷键提示。
- 测速和实时负载使用明确的运行会话与取消状态，停止后会等待进程、文件句柄和临时文件完成清理，并拒绝旧任务的晚到回调。
- 修复测速取消、重启和后台回调导致的界面卡顿问题，停止后会等待真实清理完成。
- 磁盘发现与 Native SMART 采集分离：先发布磁盘列表，再以最多 2 路并发异步补充 Native 数据；单个外接盘超时不会阻塞其他磁盘。
- Native SMART 探测对超时和暂时缺失执行立即、1 秒、3 秒静默重试，明确不支持的设备不重试；瞬时失败会保留同一稳定身份设备的上次有效值并标注正在刷新或上次读取。
- 应用监听磁盘装载、卸载和设备终止事件，并在约 0.75 秒防抖后刷新列表；单个事件刷新不会阻塞其他磁盘的数据发布。
- 设置可选择关闭（默认）或每 1、3、5、10、15、30 分钟自动刷新磁盘列表。
- 新增磁盘“急救”流程：仅对用户确认的外接或可移除 APFS/ExFAT 卷调用 `diskutil repairVolume`，支持预检、占用文件提示、串行流式输出和完成后刷新。
- 急救会阻断 SMART 故障、系统盘、内置盘、网络卷、虚拟盘、只读卷、锁定卷和 NTFS；NTFS 仅提供 Windows CHKDSK 指引。
- Shell 命令取消时会终止对应子进程，并区分启动失败、非零退出和主动取消。
- 设置页支持虚拟磁盘显示、序列号脱敏、普通 Tab 切页、自定义 `smartctl` 路径、历史数据库位置打开、自动刷新、检查与修复菜单和 SMART 自检界面，并完整支持简体中文。序列号脱敏默认关闭；开启后只保留前四位，其余显示为 `*`，内部身份匹配仍使用完整值。
- 应用菜单只保留系统 `Settings…` 设置入口，并使用 `Command-P` 打开；另支持 `Command-R` 刷新、`Control-Tab` / `Control-Shift-Tab` 切换功能页，普通 `Tab` 切页可在设置中关闭。
- 应用启动时静默检查 GitHub 最新稳定版；设置页和应用菜单提供手动检查、重试、打开 Releases 和查看发布说明入口，不会主动弹出更新提醒。
- 界面支持较小窗口和自适应控制栏、指标卡布局，宽表格保留水平滚动。
- SwiftData 历史记录使用版本化 Schema、独立 `CapricornHistory` 存储目录和统一 Repository，保存失败会显示明确错误。
- 内置简体中文和英文界面。

### SMART 和外接设备说明

macOS 原生 SMART 对 NVMe、SATA、USB、SD 卡和网络卷的支持程度不同。Capricorn 会尽量读取系统提供的数据，但不会伪造 `当前 / 最差 / 阈值` 等 ATA SMART 归一化字段。

- 内置 Apple NVMe 通常可以显示 macOS 原生 SMART 摘要。
- 部分外接 USB-SATA 设备需要用户自行安装 SAT SMART Driver 或通过 `smartctl` 读取。
- 未检测到 SAT SMART Driver 时，SMART 支持区可直接打开 [OS-X-SAT-SMART-Driver 开源项目仓库](https://github.com/kasbert/OS-X-SAT-SMART-Driver)；Capricorn 只提供入口，不会自动下载或安装驱动。
- USB NVMe、SD/SDXC 卡和网络卷通常不会暴露标准 SMART 健康属性。
- Capricorn 不会安装或卸载内核扩展，也不会捆绑 GPL `smartctl` 二进制文件。

安装可选 smartmontools：

```sh
brew install smartmontools
```

Apple Silicon Homebrew 通常安装到 `/opt/homebrew/bin/smartctl`；Intel Mac 通常安装到 `/usr/local/bin/smartctl`。安装后请重启或刷新 Capricorn。

### 测速和实时活动

Capricorn 只在你选择的文件夹内创建临时测试文件，不做裸设备写入。测速结果按实际完成文件传输所需时间计算，不读取“活动监视器”的速度值。

重要说明：

- 写入、混合、循环和大文件负载会对存储产生压力和写入磨损。
- 选择目标文件夹时，请确认它位于你想测试的磁盘上。
- 网络卷可以作为文件夹测速目标，但不会提供本机单盘 IOKit 活动计数。
- 实时活动页显示的是 macOS 为所选物理磁盘报告的系统级读写活动，不是单个进程的精确 I/O。

### 系统要求

- 使用发布版：macOS `14.0` 或更新版本，不需要 Xcode。
- 从源码构建：需要 Xcode，当前工程使用 SwiftUI、SwiftData、IOKit 和 DiskArbitration。
- 可选依赖：smartmontools (`smartctl`)。

### 构建和测试

1. 用 Xcode 打开 `Capricorn.xcodeproj`。
2. 选择 `Capricorn` scheme。
3. 点击 Run，或按 `Command-R`。

终端构建：

```sh
xcodebuild -project Capricorn.xcodeproj -scheme Capricorn -destination 'platform=macOS' build
```

运行测试：

```sh
xcodebuild test -project Capricorn.xcodeproj -scheme Capricorn -destination 'platform=macOS'
```

### 版本命名

公开 Display Name 使用由 Xcode `Version` 和 `Build` 组成的三段式版本名。`Version` 保持两段，`Build` 表示 App 发布构建次数。

例如：

- `Version = 2.1`
- `Build = 1`
- `Display Name = Capricorn V2.1.1`

### 当前限制

- SMART 数据取决于 macOS、硬盘协议、桥接芯片和可选工具支持。
- SD/SDXC 卡一般不提供标准硬盘 SMART 健康字段。
- 网络卷不能提供本机单盘 IOKit 活动计数。
- 异步队列深度测试依赖 macOS POSIX AIO 行为，结果可能与 Blackmagic Disk Speed Test 等工具不同。
- 发布包未在本仓库流程中自动公证；首次打开可能需要通过 macOS Gatekeeper 手动允许。

---

## English

### Purpose

Capricorn is not a full disk repair utility and does not write directly to raw devices. It focuses on local disk inspection, SMART visibility, benchmark runs, live activity charts, and history records for practical storage checks before copying, backing up, or stress-testing media drives.

### Download And Install

1. Download `Capricorn-v2.1.1-macOS.zip` from [GitHub Releases](https://github.com/LexTheAries2209/Capricorn/releases/latest).
2. Unzip it and move `Capricorn V2.1.1.app` to `Applications` or your local tools folder.
3. On first launch, if macOS Gatekeeper shows an internet-download warning, right-click the app in Finder and choose Open, or allow it from System Settings > Privacy & Security.

English release notes for V2.1.1 are available at [docs/releases/v2.1.1.en.md](docs/releases/v2.1.1.en.md).

Common use cases:

- Inspect internal drives, external SSDs, card readers, SD cards, and mounted network volumes.
- Review native macOS SMART data or optional `smartctl` health details.
- Benchmark a selected target folder with sequential, random, read, write, and mixed tests.
- Use synchronous or POSIX AIO queue-depth engines for peak and sustained SSD checks.
- Watch live disk activity while generating large-file read, write, or mixed workloads.
- Save SMART, benchmark, and live activity history with hide and restore controls.
- Use the drive context menu for mount, unmount, eject, rename, Finder reveal, open-file inspection, and read-only checks.

### Features

- Detects local physical disks, external drives, mounted partitions, network volumes, and memory cards.
- Maps APFS, ordinary mounted partitions, and network paths back to the selected benchmark target.
- Shows filesystem format in the overview and repeats the selected drive name on SMART, benchmark, and history pages.
- Adds a drive context menu for safe mount, unmount, force unmount, eject, rename, Finder reveal, refresh, and network disconnect actions.
- Protects internal system disks from mount, unmount, force-unmount, and eject operations initiated from Capricorn.
- Shows processes with open files on a selected disk, including follow-up diagnostics when unmount or eject actions fail.
- When Check and Repair is enabled in Settings, the drive context menu offers Quick Check, Deep Check, and First Aid, with output from `diskutil` or native macOS filesystem checkers where available.
- Shows SMART health, temperature, life remaining, power-on hours, media errors, unsafe shutdowns, and provider status.
- Settings can reveal SMART self-test status, quick/full tests for supported ATA, NVMe, and SAT devices, automatic polling, abort, recent records, and raw smartctl fallback. This interface is hidden by default; Overview shows the latest device-reported self-test summary only when it is enabled.
- When the self-test interface is enabled, unsupported operations remain disabled based on device capability and transport. System-disk self-tests require a separate Settings opt-in, and unsupported macOS NVMe admin commands are never forced.
- Improves smartctl 7.5 compatibility and diagnostics, avoids waking sleeping disks by default for SMART refresh, and retains the previous snapshot when safe device identification is unavailable.
- The SMART page keeps an expandable External Drive SMART support section available for every local physical drive. It starts collapsed for internal drives or when both smartctl and SAT SMART Driver are detected, and starts expanded for external drives with missing or unverified support.
- Driver Diagnostics groups the smartctl target path, device type, protocol, open errors, and explicitly labeled SAT SMART Driver paths. When the SAT driver is missing, it links to the open-source project; after detection, redundant installation and reconnect guidance stays hidden.
- SMART attributes have an independently scrolling table, collapsible self-test history, and dismissible status messages. Common external ATA fields have clearer localized explanations, while Total LBAs Read/Written values are converted using the reported logical block size without dropping the original LBA details.
- Includes 177 physical-drive model rules covering consumer, OEM, data-center, and enterprise families from Samsung, Intel, Solidigm, SK hynix, Micron, Crucial, KIOXIA, Toshiba, WD, Seagate, YMTC, and ZHITAI. Already concise or unconfirmed models retain their system-reported names.
- The sidebar leads with the largest volume name, then the drive product/model and serial number. Width and row spacing are bounded to keep same-model devices distinguishable.
- The sidebar and overview show total, used, and available capacity for physical and network drives. APFS volumes that share one container are deduplicated before capacity aggregation.
- Formats native Kelvin temperatures with a Celsius conversion while keeping already-Celsius values in Celsius. Overview values are yellow from `70–85 °C` and red at `85 °C` or above, but temperature does not alter overall SMART health.
- Converts native macOS and `smartctl` NVMe Data Units Read/Written values to TB while retaining the raw unit count.
- Uses native macOS SMART first, with optional user-installed `smartctl` for deeper ATA/NVMe data.
- Displays limited-support messages for SD/SDXC readers and network volumes instead of treating missing SMART as a drive failure.
- Includes Default, Peak/NVMe, RealWorld, Demo, and Custom benchmark profiles.
- Custom benchmarks support up to 4 test groups with SEQ/RND, block size, Q, T, and mixed-test choices.
- Each profile can use a synchronous or asynchronous engine; Custom can also run in loop mode.
- Benchmark file sizes start at 1 GiB and support Random or 0 Fill data patterns.
- Each green result-row button can run that benchmark item once using the current engine, file size, and data pattern; single-item runs force incremental testing off and keep the write confirmation.
- An optional small-block efficiency control scales the actual test data for 4 KiB, 16 KiB, and 64 KiB items to 5%, 10%, 20%, 30%, or 50%; it is off by default and starts at 20% when first enabled.
- Benchmark targets follow the drive selected in the sidebar, automatically choosing its first mounted writable partition while still allowing a partition or same-drive folder override. Ownership is validated again before a run starts.
- Benchmark results can include the live activity samples captured during the run.
- Live Activity supports 0.1s, 0.2s, 0.5s, and 1s sampling, retained charts, and history saving.
- Live Activity follows the physical drive selected in the sidebar. Other drive rows are locked while monitoring or workload activity runs, disappearing devices stop the active tasks with an error, and unsaved samples remain isolated by drive after switching.
- Large-file workloads automatically use the first writable mounted partition in natural device order, with explicit same-drive partition or folder selection. Read-only, unmounted, and cross-drive targets are rejected, and target choices are remembered separately for each drive.
- After stopping Live Activity, Continue Monitoring appends new samples to the existing chart; Start Monitoring keeps the original clear-and-start-new behavior.
- Large-file workloads support read, write, mixed read/write, fixed sizes, and a 95% free-space mode.
- History supports SMART, benchmark, and activity record hiding, hidden-record management, and restore. Records match by full hardware serial first and fall back to volume UUIDs when a serial is unavailable. V2.0.1 uses a new `CapricornHistory` database and does not import legacy history.
- The legacy JSON, CSV, and plain-text copy controls were removed from History pending a redesigned unified exporter.
- SMART snapshots use a compact CSV export with drive identity, device type, volume UUID, and external-drive volume metadata in the same attribute table. The Simplified Chinese UI adds a Chinese name column; the English UI uses English names and explanations.
- The SMART page saves a CSV snapshot with `Command-S`, and the toolbar button exposes the same shortcut in its help text.
- Benchmark and live-workload sessions use explicit run and cancellation states, wait for process/file cleanup, and reject late callbacks from superseded work.
- Performs a quiet GitHub stable-release check at launch; Settings and the application menu provide manual check, retry, Releases, and release-notes actions without proactively interrupting the user.
- Fixes benchmark cancellation/restart paths that could make the UI stall, while waiting for real cleanup before a new run starts.
- Drive discovery and Native SMART collection are separated: the drive list appears first, then Native data is added asynchronously with at most two concurrent probes. One slow external drive cannot block publication for another disk.
- Native SMART probes retry transient timeouts and missing fields immediately, after 1 second, and after 3 seconds, while explicit unsupported responses are not retried. Last-known-good Native values survive transient failures and are labeled as refreshing or previously read.
- Disk mount, unmount, and device-termination events trigger a debounced refresh after about 0.75 seconds, without allowing a single event refresh to block other drive updates.
- Settings can keep automatic disk refresh off by default or run it every 1, 3, 5, 10, 15, or 30 minutes.
- Adds a guarded First Aid flow for explicitly selected external or removable APFS/ExFAT volumes using `diskutil repairVolume`, with preflight checks, open-file warnings, serial streaming output, and post-run refresh.
- Blocks First Aid for failing SMART health, system/internal disks, network or virtual volumes, read-only/locked volumes, and NTFS; NTFS shows Windows CHKDSK guidance only.
- Cancelling a shell command terminates its child process and distinguishes launch failures, non-zero exits, and user cancellation.
- Settings cover virtual-drive visibility, serial-number redaction, plain-Tab navigation, a custom `smartctl` path, history-database reveal, automatic refresh, the Check and Repair menu, and the SMART self-test interface, with complete Simplified Chinese content. Redaction is off by default; when enabled, only the first four characters remain visible while internal identity matching still uses the complete serial.
- The application menu keeps only the system `Settings…` command and maps it to `Command-P`. Capricorn also supports `Command-R` to refresh and `Control-Tab` / `Control-Shift-Tab` to switch feature pages; plain-Tab switching can be disabled.
- Responsive controls and metric grids support smaller windows while wide tables keep horizontal scrolling.
- SwiftData history uses a versioned schema, a dedicated `CapricornHistory` storage directory, and a repository boundary with explicit save errors.
- Provides Simplified Chinese and English UI text.

### SMART And External Device Notes

macOS exposes different SMART data depending on NVMe, SATA, USB, SD card, bridge chipset, and network volume behavior. Capricorn reports available data without fabricating ATA normalized fields such as `Current / Worst / Threshold`.

- Internal Apple NVMe drives usually expose a native SMART summary.
- Some external USB-SATA devices require a user-installed SAT SMART Driver or `smartctl`.
- When SAT SMART Driver is not detected, the SMART support section links directly to the [OS-X-SAT-SMART-Driver open-source repository](https://github.com/kasbert/OS-X-SAT-SMART-Driver). Capricorn provides the link but does not download or install the driver.
- USB NVMe, SD/SDXC cards, and network volumes often do not expose standard SMART health attributes.
- Capricorn does not install or remove kernel extensions and does not bundle the GPL `smartctl` binary.

Install optional smartmontools:

```sh
brew install smartmontools
```

Apple Silicon Homebrew usually installs `smartctl` at `/opt/homebrew/bin/smartctl`; Intel Homebrew usually uses `/usr/local/bin/smartctl`. Restart or refresh Capricorn after installation.

### Benchmark And Live Activity

Capricorn creates temporary files only inside the folder you choose. It does not perform raw device writes. Benchmark throughput is calculated from bytes transferred and elapsed time, not from Activity Monitor.

Important notes:

- Write, mixed, loop, and large-file workload tests can stress and wear storage devices.
- Make sure the selected target folder is on the drive you intend to test.
- Network volumes can be benchmarked as mounted folders, but they do not expose local per-disk IOKit counters.
- Live Activity reports system-level I/O counters for the selected physical disk, not exact per-process I/O.

### Requirements

- Release build: macOS `14.0` or later; Xcode is not required.
- Source build: Xcode with SwiftUI, SwiftData, IOKit, and DiskArbitration support.
- Optional dependency: smartmontools (`smartctl`).

### Build And Test

1. Open `Capricorn.xcodeproj` in Xcode.
2. Select the `Capricorn` scheme.
3. Press Run, or use `Command-R`.

Terminal build:

```sh
xcodebuild -project Capricorn.xcodeproj -scheme Capricorn -destination 'platform=macOS' build
```

Run tests:

```sh
xcodebuild test -project Capricorn.xcodeproj -scheme Capricorn -destination 'platform=macOS'
```

### Version Naming

The public Display Name uses a three-part version label composed from Xcode `Version` and `Build`. `Version` stays two-part, while `Build` represents the release build count.

Example:

- `Version = 2.1`
- `Build = 1`
- `Display Name = Capricorn V2.1.1`

### Current Limitations

- SMART visibility depends on macOS, drive protocol, bridge chipset, and optional tooling.
- SD/SDXC cards usually do not expose standard drive SMART health fields.
- Network volumes do not provide local per-disk IOKit activity counters.
- POSIX AIO queue-depth results can differ from tools such as Blackmagic Disk Speed Test.
- The release bundle is not notarized by an automated repository workflow; first launch may require manual Gatekeeper approval.

---

## Development Notes / 开发说明

- `Capricorn/App/` contains the application entry point, root model, preferences, and root view.
- `Capricorn/Domain/`, `Features/`, `Services/`, `Persistence/`, and `Support/` contain the split domain, UI, process/SMART/benchmark services, data boundary, logging, and localization code.
- `CapricornTests/` contains parser, benchmark, SMART, history, and activity tests.
- `Capricorn.xcodeproj` is the Xcode project.
- `DerivedData/` and local build artifacts are development outputs and should not be used as release assets.

`Capricorn/` 为应用源码；`CapricornTests/` 为解析器、测速、SMART、历史和实时活动测试；`Capricorn.xcodeproj` 为 Xcode 工程。`DerivedData/` 和本地构建产物只用于开发，不作为 Release 资产。

## License / 授权

Capricorn source code is licensed under the GNU General Public License v3.0 only (`GPL-3.0-only`). See [LICENSE](LICENSE).

Capricorn 源代码使用 GNU General Public License v3.0 only (`GPL-3.0-only`) 授权。使用、修改和分发本项目源代码时，请遵守 [LICENSE](LICENSE) 中的条款。

App icons and branding assets are not covered by the GPLv3 source-code license unless explicitly stated otherwise.

软件图标和品牌视觉资源不属于 GPLv3 源代码授权范围，除非另有明确说明。
