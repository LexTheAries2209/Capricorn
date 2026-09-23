# Capricorn Release Log / 更新记录

This file records every public Capricorn release. Entries are listed newest first and are maintained as part of the release workflow. Detailed verification, compatibility, and packaging information remains in each version's release notes.

本文记录 Capricorn 的全部公开版本，按新到旧排列，并作为发布流程的一部分持续维护。每个版本更完整的验证、兼容性和打包信息仍保留在对应发布说明中。

## V2.9.1 - 2026-09-23

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v2.9.1) | [Release Notes / 发布说明](docs/releases/v2.9.1.md)

### 中文

- 测速运行与单项测试的确认提醒改为紧凑活动窗口，按字段展示配置、目标文件夹和写入风险，不再使用拥挤的系统提醒或覆盖整个测速页的遮罩。
- 启动后在活动窗口显示测速进度、当前测试和取消操作；隐藏窗口不会停止测速，可从测速页重新打开。
- 缓存界面显示用的目标卷可用容量，减少打开与取消窗口时的主线程重复查询；运行前仍实时核验目标、写入能力及剩余空间。

### English

- Replaces crowded system alerts and the full-page overlay with a compact benchmark activity sheet for full and single-test confirmation, grouping settings, target, and write warnings.
- Shows progress, current test, and cancellation in the activity sheet after starting; hiding it does not stop the benchmark, and the sheet can be reopened.
- Caches display-only volume capacity to avoid repeated main-thread queries during sheet transitions while retaining fresh target, write-access, and free-space checks before starting.

## V2.9.0 - 2026-09-23

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v2.9.0) | [Release Notes / 发布说明](docs/releases/v2.9.0.md)

### 中文

- 修正 USB-NVMe SMART 自检能力判定与传输层提示，避免将仅能读取 SMART 的设备误报为可启动自检。
- 为支持自检的非系统盘加入启动确认、可隐藏的进度监视器、紧凑状态条和完成结果，展示设备报告的进度、运行时间、预估完成时间及最近刷新状态；未知结果不再显示为通过。
- 系统盘不再显示概览快速自检、SMART 诊断自检和对应历史区块，也不能从菜单或内部操作路径执行磁盘检查/自检。
- 设置重整诊断显示选项，并加入保留硬盘缓存和历史数据库的“重置所有设置”二次确认操作。
- SMART 诊断的自检历史 CSV/JSON 导出改为每次选择保存位置，不影响 SMART 快照导出。

### English

- Corrects USB-NVMe self-test capability reporting and transport guidance so SMART read access alone is not mistaken for self-test support.
- Adds start confirmation, a hideable progress monitor, compact status, and completion results for supported non-system disks. Device-reported progress, elapsed time, estimated completion, and recent refresh state are shown; unknown results are not labeled passed.
- Hides Overview quick checks, SMART diagnostic self-tests, and related history sections for system disks and blocks disk checks/self-tests through both UI and operation paths.
- Reorganizes diagnostic display preferences and adds a confirmed Reset All Settings action that preserves disk caches and the history database.
- Prompts for a CSV/JSON destination on every SMART diagnostics self-test history export without changing SMART snapshot exports.

## V2.8.1 - 2026-09-23

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v2.8.1) | [Release Notes / 发布说明](docs/releases/v2.8.1.md)

### 中文

- 将测速配置首排重构为独立标题行和控件行，标题按首行基线对齐，按钮、菜单和分段控件按中心线对齐。
- 将测速与实时活动图表的纵轴网格改为 9 条横线，并仅在第 1、3、5、7、9 条线上显示数值标签。
- 本次仅调整界面布局与图表刻度展示，不改变测速引擎、数据模式或磁盘写入安全边界。

### English

- Reworks the first benchmark configuration row into separate label and control rows, aligning labels by first baseline and controls by center line.
- Changes benchmark and Live Activity chart grids to nine horizontal lines, with numeric labels on lines 1, 3, 5, 7, and 9.
- Limits this release to layout and chart-scale presentation; benchmark engines, data modes, and disk-write safety boundaries are unchanged.

## V2.8.0 - 2026-09-21

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v2.8.0) | [Release Notes / 发布说明](docs/releases/v2.8.0.md)

### 中文

- 新增跨 Capricorn 进程共享的物理硬盘操作锁；开发版与正式版使用同一套锁，避免多个实例同时对同一硬盘执行互斥操作。
- 测速、实时活动负载、SMART 自检、磁盘检查/急救、装载、卸载、推出、重命名和网络卷断开均在实际执行前检查冲突；发现冲突时弹窗显示占用操作与进程，不会继续执行。
- 保留现有 runID 隔离，并把临时文件清理限制在当前运行；超过一小时且确认没有活跃租约的崩溃残留会在新任务开始前清理。
- 硬盘锁只协调 Capricorn 自身，不锁定系统设备，也不阻止 Finder、其他测速工具或系统服务访问硬盘。

### English

- Adds a physical-disk operation lock shared by all Capricorn processes, including development and release builds, so multiple instances cannot start conflicting operations on the same disk.
- Benchmarking, Live Activity workloads, SMART self-tests, disk checks/First Aid, mount, unmount, eject, rename, and network-volume disconnect operations check for conflicts before execution. Conflicts show the owning operation and process and do not proceed.
- Preserves runID isolation and limits temporary-file cleanup to the active run. Crash leftovers older than one hour are removed before a new task only when no active lease exists.
- The lock coordinates Capricorn only. It does not lock the system device or prevent Finder, other benchmark tools, or system services from accessing the disk.

## V2.7.6 - 2026-09-21

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v2.7.6) | [Release Notes / 发布说明](docs/releases/v2.7.6.md)

### 中文

- 测试宿主启动时不再执行真实磁盘刷新、事件监控或更新检查，避免自动化测试被系统 I/O 和网络副作用拖住。
- SMART 测试使用隔离的命令协调器，并为扫描、读取和版本查询增加明确超时；网络卷与存储卡会在设备扫描前直接返回不支持，确保异常路径不会占住队列。
- GitHub Actions 质量工作流改为仅在 `Main` 推送和拉取请求运行，取消重复标签构建，并为所有任务增加并发取消与最长执行时间。
- 完整测试增至 319 项，严格并发和 Swift 6 兼容性构建继续通过。

### English

- Prevents the test host from starting real disk refresh, event monitoring, or update checks, avoiding automation stalls caused by system I/O and network side effects.
- Isolates SMART test command coordination and adds explicit scan, read, and version timeouts. Network volumes and memory cards now return unsupported before device scanning so exceptional paths cannot occupy the queue.
- Runs the GitHub Actions quality workflow only for `Main` pushes and pull requests, removes duplicate tag builds, and adds concurrency cancellation plus job time limits.
- Expands the full suite to 319 passing tests while retaining successful strict-concurrency and Swift 6 compatibility builds.

## V2.7.5 - 2026-09-20

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v2.7.5) | [Release Notes / 发布说明](docs/releases/v2.7.5.md)

### 中文

- SMART 历史摘要增加寿命、介质错误、累计读写量和通电时间，并支持在独立窗口查看完整报告与再次导出 CSV。
- SMART 页面新增独立“保存到历史”操作；保存 CSV 仍会同步保存当前快照到历史。
- 测速历史按共享曲线整组隐藏、恢复和删除，并修正紧凑图表速度刻度的对齐显示。
- 设置新增默认关闭的历史逐条删除功能，可在二次确认后永久删除可见或已隐藏记录。

### English

- Expands SMART History summaries with life, media errors, cumulative reads and writes, and power-on time, plus full report windows and CSV export.
- Adds a separate Save to History action on SMART while Save CSV continues to store the snapshot in History.
- Hides, restores, and deletes Benchmark History by the run sharing one chart, with corrected compact speed-axis labels.
- Adds a default-off per-record history deletion setting with confirmation for visible and hidden records.

## V2.7.4 - 2026-09-19

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v2.7.4) | [Release Notes / 发布说明](docs/releases/v2.7.4.md)

### 中文

- 测速新增仅读取、仅写入和读写选择，并重新整理操作区间距和按钮位置。
- 测速历史按一次任务分组，在组顶部只显示一张活动曲线，下面列出该次保存的测速结果，同时兼容旧版重复曲线数据。
- 实时活动历史显示已保存的折线图，并将历史三栏布局的折行阈值调整到约 1200 pt。
- 精简 SMART 快照空状态文案，并统一测速与实时活动历史的紧凑视觉层级。

### English

- Adds read-only, write-only, and read-and-write benchmark selection and refines control spacing and action placement.
- Groups Benchmark History by run with one activity chart above that run's saved results, including compatibility for legacy duplicate chart data.
- Shows saved charts in Live Activity History and keeps the three-panel History layout down to about 1200 pt.
- Simplifies the empty SMART snapshot message and aligns benchmark and Live Activity history presentation.

## V2.7.3 - 2026-09-19

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v2.7.3) | [Release Notes / 发布说明](docs/releases/v2.7.3.md)

### 中文

- 为已安装 SAT SMART Drive 但仍无法读取 SMART 的三星 Portable SSD T5 增加驱动冲突提醒。
- 为相同条件下的 USB-NVMe 设备增加桥接器可能无法在 macOS 提供 SMART 数据的说明。
- 两类提醒严格按设备类型、SMART 读取结果和 SAT 安装状态触发，并精简概览与 SMART 页的展示。

### English

- Adds a driver-conflict warning for Samsung Portable SSD T5 devices that still expose no SMART data after SAT SMART Drive is installed.
- Explains that some USB-NVMe bridges may not expose SMART data on macOS under the same conditions.
- Gates both warnings by device type, SMART results, and SAT installation state, with a more compact presentation in Overview and SMART.

## V2.7.2 - 2026-09-17

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v2.7.2) | [Release Notes / 发布说明](docs/releases/v2.7.2.md)

### 中文

- 设置新增“界面显示”和“快捷键”区域，并重新整理硬盘操作、SMART 与历史数据库选项。
- 功能页统一使用 `Tab` 顺序切换，移除旧开关和 Control-Tab 组合。
- App 内仅保留 SAT SMART Drive 的 PKG 安装包，移除重复 ZIP 资源。

### English

- Adds Interface Display and Keyboard Shortcuts sections and reorganizes Disk Actions, SMART, and History Database settings.
- Standardizes feature navigation on `Tab` and removes the former toggle and Control-Tab combinations.
- Keeps only the SAT SMART Drive PKG installer in the app, removing the duplicate ZIP resource.

## V2.7.1 - 2026-09-17

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v2.7.1) | [Release Notes / 发布说明](docs/releases/v2.7.1.md)

### 中文

- SAT SMART Driver 的绿色状态改为仅依据驱动文件是否安装并加载。
- 符合条件的 USB-SATA 设备在 SMART 不可用时始终显示 SAT 引导，并移除对应设置开关。
- 安装操作更名为“安装 SAT SMART Drive”，并增加跨输入法可用的反引号/波浪号设置快捷键。

### English

- Makes the green SAT SMART Driver state depend only on whether its files are installed and loaded.
- Always shows SAT guidance for eligible USB-SATA devices without SMART data and removes the related Settings toggle.
- Renames the install action and adds a grave/tilde Settings shortcut that works across input sources.

## V2.7.0 - 2026-09-17

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v2.7.0) | [Release Notes / 发布说明](docs/releases/v2.7.0.md)

### 中文

- 重构侧边栏状态区，固定健康与刷新状态，并显示最近的去重活动记录。
- 补充 SMART、扫描、占用程序和磁盘操作的完成状态，修正已装载卷的操作可用性。
- 按设备能力隐藏不适用的 SMART 错误、诊断和快速自检内容，改善网络盘与 SD 卡文案。
- 为缺少 SMART 数据的合适 USB 设备增加 SAT SMART Drive 引导和设置入口。
- 改进快速自检历史匹配、SMART 能力恢复后的显示，以及历史与测速布局的自适应能力。

### English

- Reworks the sidebar status area with pinned health and refresh rows plus recent deduplicated activity.
- Adds completion states for SMART, scanning, open-file inspection, and disk actions, and fixes mounted-volume action availability.
- Hides inapplicable SMART errors, diagnostics, and quick checks according to device capability, with clearer network and SD-card text.
- Adds contextual SAT SMART Drive guidance for eligible USB devices without SMART data.
- Improves quick-check history matching, recovery when SMART capability returns, and adaptive History and benchmark layouts.

## V2.6.3 - 2026-09-15

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v2.6.3) | [Release Notes / 发布说明](docs/releases/v2.6.3.md)

### 中文

- 新增可选 SAT SMART Driver 支持与设置诊断，包括安装状态、版本、来源和透传说明。
- 改进 USB-SATA/USB-NVMe SMART 透传展示、本地化诊断和读取回退能力。
- 保留暂时读取失败时的上一份有效 SMART 数据，并避免执行 macOS 不支持的 NVMe 管理命令。
- 重新整理实时活动页的监控、采样、负载目标和操作控件。
- 调整侧边栏版本与用户名位置，并移除设置入口的 `Command-P` 提示。

### English

- Adds optional SAT SMART Driver support and Settings diagnostics for installation state, version, source, and passthrough guidance.
- Improves USB-SATA and USB-NVMe passthrough reporting, localization, and SMART read fallback.
- Preserves the last valid SMART snapshot after transient failures and avoids unsupported macOS NVMe admin commands.
- Reorganizes Live Activity monitoring, sampling, workload-target, and action controls.
- Adjusts version and user identity placement and removes the `Command-P` hint from the Settings entry.

## V2.5.1 - 2026-09-09

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v2.5.1) | [Release Notes / 发布说明](docs/releases/v2.5.1.md)

### 中文

- 概览健康度改用系统电池图标，并增加六档填充状态。
- 重新整理历史页的快速自检、自检报告和 SMART/测速/实时活动布局。
- 统一历史操作按钮尺寸，继续保持温度与错误日志不改变整体健康等级。
- 完善自检能力探测、系统盘保护和无法发送 NVMe 自检命令时的提示。

### English

- Uses system battery symbols for Overview health with six fill levels.
- Reorganizes Quick Check, self-test reports, SMART, benchmark, and Live Activity sections in History.
- Aligns History action sizing while keeping temperature and error-log warnings independent from overall health.
- Improves self-test capability detection, system-disk protection, and unsupported NVMe self-test guidance.

## V2.5.0 - 2026-09-08

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v2.5.0) | [Release Notes / 发布说明](docs/releases/v2.5.0.md)

### 中文

- 新增 SMART 诊断界面，支持设备自检状态、快速/完整自检、历史、错误日志读取与导出。
- 按设备能力和权限提供操作，并为 macOS 无法发送的 NVMe 自检命令显示明确状态。
- 概览增加快速自检入口，自检报告按硬盘身份保存，系统盘操作需要单独允许。
- 温度和错误日志保留独立提示，但不改变整体 SMART 健康等级。

### English

- Adds a SMART diagnostics interface for status, short and extended self-tests, history, and error-log reading and export.
- Gates actions by capability and permission, with an explicit state for NVMe commands unavailable on macOS.
- Adds Quick Check to Overview, stores reports by drive identity, and requires a separate opt-in for system disks.
- Keeps temperature and error-log warnings independent from the overall SMART health grade.

## V2.4.2 - 2026-09-02

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v2.4.2) | [Release Notes / 发布说明](docs/releases/v2.4.2.md)

### 中文

- 修复 USB 外壳仅返回设备识别信息时被误报为已验证 SMART 的问题。
- USB-SATA/USB-NVMe 透传成功现在必须有实际 SMART 状态、属性、温度或健康日志作为证据。
- 保留桥接器诊断，同时明确区分可访问路径与成功读取 SMART 数据。

### English

- Fixes USB enclosures being reported as SMART-verified when they return identity data only.
- Requires actual SMART status, attributes, temperature, or health logs before USB passthrough is reported as successful.
- Retains bridge diagnostics while separating an accessible path from a successful SMART read.

## V2.4.1 - 2026-09-02

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v2.4.1) | [Release Notes / 发布说明](docs/releases/v2.4.1.md)

### 中文

- 设置只显示内置 `smartctl` 版本和 smartmontools 源项目，不再提供外部工具选择。
- 概览新增基于真实读取结果的 USB-SATA 与 USB-NVMe SMART 命令透传状态。
- 统一数据来源区域布局，并修正 WD Elements Portable 5TB 与 HDD 介质类型识别。

### English

- Limits Settings to the bundled `smartctl` version and smartmontools source link, removing external-tool selection.
- Adds USB-SATA and USB-NVMe command-passthrough state based on actual read results.
- Unifies provider layout and fixes WD Elements Portable 5TB and HDD media-type identification.

## V2.4.0 - 2026-09-01

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v2.4.0) | [Release Notes / 发布说明](docs/releases/v2.4.0.md)

### 中文

- 内置固定版本 smartmontools 7.5，包括通用架构 `smartctl`、`drivedb.h`、许可证、源码和可复现构建脚本。
- SMART 默认使用 App 内置工具，不再自动搜索 PATH 或 Homebrew。
- 将外接 SMART、ATA 选项和 SAT 驱动诊断集中到设置，并保持同一磁盘查询与自检串行执行。
- 改进 SMART 属性表滚动与空间使用，并补充外接磁盘型号和卷宗识别。

### English

- Bundles a pinned smartmontools 7.5 build with universal `smartctl`, `drivedb.h`, licensing, source, and reproducible build scripts.
- Uses the bundled tool by default instead of searching PATH or Homebrew automatically.
- Consolidates external SMART, ATA options, and SAT diagnostics in Settings while serializing access to each drive.
- Improves SMART table scrolling and space usage and expands external-drive identity rules.

## V2.3.2 - 2026-08-31

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v2.3.2) | [Release Notes / 发布说明](docs/releases/v2.3.2.md)

### 中文

- 新增 ARRI Codex Compact Drive、Compact Drive Express 和 SXR Capture Drive 型号识别。
- 修正 UDF 摄影机介质未出现在 `diskutil list` 时的卷宗信息回填。
- 侧边栏及卷宗操作改用真实挂载卷名，不再以硬盘型号代替。

### English

- Adds recognition for ARRI Codex Compact Drive, Compact Drive Express, and SXR Capture Drive media.
- Restores UDF camera-media volume details when they are missing from `diskutil list`.
- Uses the real mounted volume name in the sidebar and volume actions instead of substituting the drive model.

## V2.3.1 - 2026-08-25

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v2.3.1) | [Release Notes / 发布说明](docs/releases/v2.3.1.md)

### 中文

- 设置显示历史数据库目录、占用空间和记录总数，并支持确认后清理全部历史。
- 历史页增加当前硬盘记录统计和按范围清理，不影响其他硬盘。
- 系统盘测速自动目标优先选择桌面，避免写入系统根目录。
- 实时监控或负载运行时锁定其他硬盘选择，并整理 Tab 切换说明的位置。

### English

- Shows the History database location, size, and record count in Settings, with confirmed full cleanup.
- Adds per-drive History counts and scoped cleanup without affecting other drives.
- Prefers Desktop as the automatic benchmark target for the system disk instead of the filesystem root.
- Locks other drive selections during monitoring or workloads and relocates the Tab-navigation explanation.

## V2.2.2 - 2026-08-24

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v2.2.2) | [Release Notes / 发布说明](docs/releases/v2.2.2.md)

### 中文

- 解析 APFS Physical Store 关系与分区内容，识别并排除容器承载分区、EFI 和其他结构条目。
- 取消全局小容量过滤，只在拓扑缺失且多项条件同时满足时把容量作为辅助信号。
- 在概览、代表卷、测速、负载、检查修复、容量汇总和 SMART CSV 中统一过滤结构分区。

### English

- Parses APFS Physical Store relationships and partition content to identify container backing partitions, EFI, and other structural entries.
- Removes the global small-volume filter and uses capacity only as a fallback when topology is missing and several conditions agree.
- Applies structural-partition filtering consistently across Overview, representative volumes, benchmarks, workloads, repair, capacity, and SMART CSV.

## V2.2.1 - 2026-08-24

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v2.2.1) | [Release Notes / 发布说明](docs/releases/v2.2.1.md)

### 中文

- 外接物理磁盘可切换代表卷，侧边栏、重命名、测速和实时活动负载共享该选择。
- 设置新增默认最大可操作卷或恢复上次手动选择的启动策略。
- 过滤 EFI、APFS 容器支撑分区和系统辅助卷，并固定系统盘优先显示根卷。
- 扩展 Intel/Solidigm 数据中心 SSD 与 WD Ultrastar DC SN640 型号映射。

### English

- Lets external physical drives select a representative volume shared by the sidebar, rename, benchmark, and Live Activity workload flows.
- Adds startup policies for the largest usable volume or the last manual selection.
- Filters EFI, APFS container backing partitions, and system helper volumes while prioritizing the system root volume.
- Expands Intel/Solidigm data-center SSD and WD Ultrastar DC SN640 model mappings.

## V2.1.1 - 2026-08-24

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v2.1.1) | [Release Notes / 发布说明](docs/releases/v2.1.1.md)

### 中文

- 监听磁盘装载、卸载和设备终止事件，并在防抖后自动刷新。
- 增加可选的定时自动刷新，同时避免慢速外接盘阻塞其他磁盘更新。
- SMART 快照保存支持 `Command-S`，设置可直接打开历史数据库位置。
- 将检查与修复、自检状态和自检操作分别放入默认关闭的设置开关。

### English

- Watches mount, unmount, and device-termination events and refreshes automatically after debouncing.
- Adds optional scheduled refresh without allowing a slow external drive to block other updates.
- Adds `Command-S` for SMART snapshots and a Settings action to reveal the History database.
- Places Check and Repair and SMART self-test presentation behind separate, default-off Settings controls.

## V2.0.1 - 2026-08-23

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v2.0.1) | [Release Notes / 发布说明](docs/releases/v2.0.1.md)

### 中文

- 历史记录改用完整硬件序列号匹配，并在缺失时回退卷 UUID；启用新的 `CapricornHistory` 数据库。
- 补强序列号、商品名和侧边栏身份展示，并增加仅影响显示与导出的序列号脱敏。
- 分离磁盘发现和 Native SMART 采集，增加受限并发、超时、静默重试和上次有效数据保留。
- 测速目标与侧边栏磁盘联动，并在启动前再次校验目标归属。
- 扩展 SMART CSV 身份字段、SD/SDXC 识别、温度提示和 177 条硬盘型号规则。

### English

- Matches History by full hardware serial with volume-UUID fallback and introduces the new `CapricornHistory` database.
- Improves serial, product-name, and sidebar identity display with optional UI and export masking.
- Separates disk discovery from Native SMART collection with bounded concurrency, timeouts, retries, and last-known-good retention.
- Links benchmark targets to the selected sidebar drive and revalidates ownership before starting.
- Expands SMART CSV identity fields, SD/SDXC handling, temperature warnings, and the 177-rule drive model catalog.

## V1.2.12 - 2026-08-22

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v1.2.12) | [Release Notes / 发布说明](docs/releases/v1.2.12.md)

### 中文

- 启动时静默检查 GitHub 最新稳定版，并在设置与应用菜单提供手动检查、重试和打开 Releases。
- SMART 快照改为紧凑的本地化 CSV，中文增加中文名称列，英文保留英文名称与说明。
- 导出文件名按界面语言使用 UTC+8 或 UTC+0，并明确标记时区。

### English

- Checks GitHub quietly for the latest stable release and adds manual check, retry, and Releases actions.
- Exports SMART snapshots as compact localized CSV, with a Chinese-name column in Simplified Chinese.
- Uses explicitly labeled UTC+8 or UTC+0 timestamps in filenames according to the interface language.

## V1.2.11 - 2026-08-04

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v1.2.11) | [Release Notes / 发布说明](docs/releases/v1.2.11.md)

### 中文

- 为本地物理磁盘保留外接磁盘 SMART 支持区，并按依赖和验证状态决定默认展开方式。
- 将 smartctl 诊断改为统一的驱动诊断，集中显示工具、目标、协议、电源和错误信息。
- 明确区分 smartctl 目标路径与 SAT SMART Driver 安装路径，并提供缺失驱动的项目入口。
- 移除重复的中文设置菜单，仅保留系统 `Settings…` 与 `Command-P`。

### English

- Keeps External Drive SMART support available for local physical drives with state-based default expansion.
- Consolidates tool, target, protocol, power, and error details into Driver Diagnostics.
- Separates the smartctl target from SAT SMART Driver install paths and links to the driver project when missing.
- Removes the duplicate localized Settings command, retaining the system `Settings…` item and `Command-P`.

## V1.2.10 - 2026-07-27

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v1.2.10) | [Release Notes / 发布说明](docs/releases/v1.2.10.md)

### 中文

- 改进 SMART 页面滚动、属性表、自检记录折叠和状态消息清理。
- 为常见 ATA SMART 字段增加本地化解释，并按逻辑块大小换算累计读写容量。
- 在侧边栏和概览显示总量、已用与可用空间，并正确处理 APFS 共享容器。
- 新增外接机械硬盘型号目录并改善侧边栏名称展示。
- 实时活动完全跟随侧边栏所选硬盘，按磁盘隔离样本、状态与目标记忆。
- 大文件负载支持同盘分区或文件夹选择，并拒绝只读、失效和跨盘目标。

### English

- Improves SMART scrolling, attribute sizing, self-test record collapsing, and status-message dismissal.
- Adds localized ATA SMART explanations and converts cumulative I/O using the reported logical block size.
- Shows total, used, and available capacity with correct APFS shared-container handling.
- Adds an external HDD model catalog and clearer sidebar identity presentation.
- Makes Live Activity follow the selected sidebar drive and isolates samples, state, and target memory per drive.
- Supports same-drive workload volumes or folders while rejecting read-only, stale, and cross-drive targets.

## V1.2.5 - 2026-07-25

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v1.2.5) | [Release Notes / 发布说明](docs/releases/v1.2.5.md)

### 中文

- 增强 ATA 与 NVMe SMART 自检日志解析，并在解析失败时保留原始输出。
- SMART 页面增加快速/完整自检、自动轮询、中止、状态、预计时间和历史记录。
- 概览仅显示最近一次设备自检摘要，完整控制集中在 SMART 页面。
- 根据设备能力禁用不支持的操作，不强行执行 macOS 不支持的 NVMe 自检命令。
- 增加系统盘自检设置与原生管理员授权，并改善 smartctl 7.5、休眠盘和 SAT 诊断处理。

### English

- Strengthens ATA and NVMe self-test log parsing while preserving raw output on failure.
- Adds short and extended tests, polling, abort, status, estimated time, and history to SMART.
- Keeps Overview limited to the latest device-reported summary and places full controls in SMART.
- Disables unsupported operations by capability and does not force unavailable macOS NVMe self-test commands.
- Adds system-disk self-test settings and native authorization and improves smartctl 7.5, sleeping-drive, and SAT diagnostics behavior.

## V1.1.1 - 2026-07-24

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v1.1.1) | [Release Notes / 发布说明](docs/releases/v1.1.1.md)

### 中文

- 原生 SMART 温度同时显示 Kelvin 原值与摄氏度换算，并统一 NVMe 累计读写的 TB 显示。
- 实时活动支持停止后继续监控，保留现有图表样本。
- 测速矩阵支持只运行单个项目，并沿用当前引擎、文件大小和数据模式。
- 新增小块文件测试效率控制，可按比例缩减 4 KiB、16 KiB 和 64 KiB 测试量。

### English

- Shows native Kelvin SMART temperatures with Celsius conversion and standardizes NVMe cumulative I/O in TB.
- Adds Continue Monitoring to append Live Activity samples to the existing chart.
- Allows a single benchmark item to run with the current engine, file size, and data pattern.
- Adds a small-block efficiency control that reduces the 4 KiB, 16 KiB, and 64 KiB workloads by a selected percentage.

## V1.0.5 - 2026-07-15

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v1.0.5) | [Release Notes / 发布说明](docs/releases/v1.0.5.md)

### 中文

- 修复测速取消、立即重启和晚到回调导致的界面卡顿，并等待真实清理完成。
- 新增安全受限的磁盘“急救”流程，支持外接或可移除 APFS/ExFAT 卷的预检、占用检查和串行修复。
- 每个卷开始前重新验证设备身份、格式、可写与锁定状态。
- 阻止系统盘、内置盘、网络盘、虚拟盘、只读盘、锁定卷、SMART 故障盘和 NTFS 直接修复。

### English

- Fixes benchmark UI stalls after cancellation, immediate restart, and late callbacks while waiting for real cleanup.
- Adds a safety-limited First Aid flow for external or removable APFS and ExFAT volumes with preflight and serial repair.
- Revalidates device identity, format, writable state, and lock state before each volume starts.
- Blocks direct repair for system, internal, network, virtual, read-only, locked, SMART-failing, and NTFS targets.

## V1.0.4 - 2026-07-12

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v1.0.4) | [Release Notes / 发布说明](docs/releases/v1.0.4.md)

### 中文

- 重构测速、实时负载和命令执行的会话、取消与晚到事件处理。
- 新增受控并发的统一磁盘刷新服务，并确保重叠刷新只采用最新结果。
- 将工程拆分为 App、Domain、Features、Services、Persistence 和 Support 模块。
- 为 SwiftData 增加版本化 Schema、迁移和统一 Repository。
- 新增完整本地化设置页、响应式布局、日志、构建脚本和 GitHub Actions 质量检查。

### English

- Reworks benchmark, live-workload, and process session, cancellation, and late-event handling.
- Adds a unified bounded-concurrency refresh service with newest-result-wins behavior.
- Splits the project into App, Domain, Features, Services, Persistence, and Support modules.
- Adds versioned SwiftData schemas, migration, and a unified repository boundary.
- Adds localized Settings, responsive layouts, logging, build scripts, and GitHub Actions quality checks.

## V1.0.3 - 2026-07-08

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v1.0.3) | [Release Notes / 发布说明](docs/releases/v1.0.3.md)

### 中文

- 新增磁盘右键菜单，支持装载、卸载、强制卸载、推出、重命名、Finder 定位、刷新和网络卷断开。
- 增加系统盘保护与占用程序查看，并在操作失败时显示原因和可能占用磁盘的进程。
- 增加只读检查日志和详细文件系统检查输出。
- 改进文件系统格式识别，并在 SMART、测速和历史页显示当前磁盘名称。
- 增加 `Command-R` 刷新和 `Tab` / `Shift-Tab` 页面切换。

### English

- Adds a drive context menu for mount, unmount, force unmount, eject, rename, Finder reveal, refresh, and network disconnect.
- Adds system-disk protection and open-file inspection with clearer failure and occupying-process details.
- Adds read-only check logs and detailed native filesystem-check output.
- Improves filesystem recognition and shows the selected drive name on SMART, Benchmark, and History.
- Adds `Command-R` refresh and `Tab` / `Shift-Tab` page navigation.

## V1.0.2 - 2026-07-06

[GitHub Release](https://github.com/LexTheAries2209/Capricorn/releases/tag/v1.0.2) | [Release Notes / 发布说明](docs/releases/v1.0.2.md)

V1.0.2 is the first public Capricorn release. / V1.0.2 是 Capricorn 的首个公开版本。

### 中文

- 建立 Capricorn 名称与三段式公开版本体系。
- 支持本机物理盘、外接 SSD、挂载分区、网络卷和 SD/SDXC 存储卡识别。
- 修复外接分区挂载点与物理磁盘的归属判断。
- 提供 SMART 属性与中文解释、同步与 POSIX AIO 异步测速、自定义测试组合。
- 提供实时活动监控、大文件负载、历史保存、隐藏和恢复。

### English

- Establishes the Capricorn name and three-part public version scheme.
- Detects local physical disks, external SSDs, mounted partitions, network volumes, and SD/SDXC media.
- Fixes ownership mapping from mounted external partitions to their physical drives.
- Provides SMART attributes and Chinese explanations, synchronous and POSIX AIO benchmarks, and custom test groups.
- Provides Live Activity monitoring, large-file workloads, and History save, hide, and restore workflows.
