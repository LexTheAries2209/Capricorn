# Capricorn

Formerly DiskSpeedTest.

Capricorn is a local macOS utility for DIT-style disk inspection, SMART health checks, storage benchmarking, and live disk activity monitoring. It is designed for users who need to quickly identify local drives, external SSDs, mounted network volumes, memory cards, and benchmark targets before copying, backing up, or stress-testing storage.

Capricorn 是一个本地 macOS 工具，用于 DIT 场景下的磁盘检查、SMART 健康状态查看、存储测速和实时磁盘活动监控。它面向需要快速确认本机硬盘、外接 SSD、已挂载网络卷、存储卡和测速目标位置的工作流。

[Latest Release / 最新版本](https://github.com/LexTheAries2209/Capricorn/releases/latest): `v1.1.1`

Bilingual release notes / 双语发布说明：[docs/releases/v1.1.1.md](docs/releases/v1.1.1.md)

---

## 中文说明

### 项目定位

Capricorn 不是完整的磁盘维修工具，也不会直接对裸设备写入。它的目标是把磁盘识别、SMART 信息、测速、实时活动曲线和历史记录放在一个本地工具里，方便在拷贝、备份、外接盘测试和现场 DIT 工作前快速判断存储状态。

### 下载和安装

1. 前往 [GitHub Releases](https://github.com/LexTheAries2209/Capricorn/releases/latest) 下载 `Capricorn-v1.1.1-macOS.zip`。
2. 解压后把 `Capricorn V1.1.1.app` 放到 `Applications` 或你的本地工具目录。
3. 首次打开时，如果 macOS Gatekeeper 提示来自互联网下载的 App，请在 Finder 中右键点击 App 后选择“打开”，或在“系统设置 > 隐私与安全性”中允许打开。

V1.1.1 的中文发布说明见 [docs/releases/v1.1.1.zh-CN.md](docs/releases/v1.1.1.zh-CN.md)。

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
- 支持普通检查日志和只读详细检查，展示 `diskutil` 或 macOS 原生文件系统检查器的输出。
- SMART 页面显示健康状态、温度、寿命、通电小时、介质错误、不安全关机次数和数据来源。
- SMART 温度会按数据源区分单位：原生 Kelvin 数值同时显示换算后的摄氏度，已是摄氏度的数值保持摄氏度显示。
- NVMe 累计读取量和写入量会把 macOS 原生与 `smartctl` 的 Data Units 转换为 TB，并保留原始 units 计数。
- macOS 原生 SMART 优先，可选使用用户已安装的 `smartctl` 获取更完整的 ATA/NVMe 数据。
- 对 SD/SDXC 读卡器和网络卷显示有限支持说明，避免把无 SMART 数据误判为硬盘故障。
- 支持默认、峰值/NVMe、真实场景、演示和自定义测速配置。
- 自定义测速最多 4 个测试项目组，可选择 SEQ/RND、块大小、Q、T 和混合测试。
- 每个测速配置可以选择同步或异步引擎；自定义配置可选择循环。
- 测速文件大小从 1 GiB 起，支持 Random 和 0 Fill 数据模式。
- 点击测速结果矩阵左侧的绿色项目按钮，可以沿用当前引擎、文件大小和数据模式只测试该项目一次；单项测试固定关闭加量测试并保留写入确认。
- “提高小块文件测试效率”可按 5%、10%、20%、30% 或 50% 缩减 4 KiB、16 KiB 和 64 KiB 项目的实际测试文件量，默认关闭，首次开启默认为 20%。
- 测速页显示实时磁盘活动曲线，保存测速结果时会保存本次曲线样本。
- 实时活动页支持 0.1s、0.2s、0.5s、1s 采样间隔、图表保留和保存到历史。
- 停止实时活动监控后可以“继续监控”并从现有图表续接；“开始监控”仍会清空图表并创建新的监控段。
- 实时活动大文件负载支持读取、写入、读写混合、固定大小和全盘 95% 模式。
- 历史页支持 SMART、测速、实时活动记录的隐藏、管理隐藏记录和恢复。
- 报告导出支持 JSON、CSV 和纯文本，默认隐藏序列号。
- 测速和实时负载使用明确的运行会话与取消状态，停止后会等待进程、文件句柄和临时文件完成清理，并拒绝旧任务的晚到回调。
- 修复测速取消、重启和后台回调导致的界面卡顿问题，停止后会等待真实清理完成。
- 磁盘刷新使用受控并发和单次 `smartctl` 扫描；重叠刷新时只有最新结果可以更新界面。
- 新增磁盘“急救”流程：仅对用户确认的外接或可移除 APFS/ExFAT 卷调用 `diskutil repairVolume`，支持预检、占用文件提示、串行流式输出和完成后刷新。
- 急救会阻断 SMART 故障、系统盘、内置盘、网络卷、虚拟盘、只读卷、锁定卷和 NTFS；NTFS 仅提供 Windows CHKDSK 指引。
- Shell 命令取消时会终止对应子进程，并区分启动失败、非零退出和主动取消。
- 设置页支持虚拟磁盘显示、报告序列号、普通 Tab 切页和自定义 `smartctl` 路径，并完整支持简体中文。
- 支持 `Command-R` 刷新、`Command-P` 打开设置、`Control-Tab` / `Control-Shift-Tab` 切换功能页；普通 `Tab` 切页可在设置中关闭。
- 界面支持较小窗口和自适应控制栏、指标卡布局，宽表格保留水平滚动。
- SwiftData 历史记录使用版本化 Schema、迁移计划和统一 Repository，保存或导出失败会显示明确错误。
- 内置简体中文和英文界面。

### SMART 和外接设备说明

macOS 原生 SMART 对 NVMe、SATA、USB、SD 卡和网络卷的支持程度不同。Capricorn 会尽量读取系统提供的数据，但不会伪造 `当前 / 最差 / 阈值` 等 ATA SMART 归一化字段。

- 内置 Apple NVMe 通常可以显示 macOS 原生 SMART 摘要。
- 部分外接 USB-SATA 设备需要用户自行安装 SAT SMART Driver 或通过 `smartctl` 读取。
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

- `Version = 1.1`
- `Build = 1`
- `Display Name = Capricorn V1.1.1`

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

1. Download `Capricorn-v1.1.1-macOS.zip` from [GitHub Releases](https://github.com/LexTheAries2209/Capricorn/releases/latest).
2. Unzip it and move `Capricorn V1.1.1.app` to `Applications` or your local tools folder.
3. On first launch, if macOS Gatekeeper shows an internet-download warning, right-click the app in Finder and choose Open, or allow it from System Settings > Privacy & Security.

English release notes for V1.1.1 are available at [docs/releases/v1.1.1.en.md](docs/releases/v1.1.1.en.md).

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
- Adds ordinary disk verification logs and read-only detailed checks using `diskutil` and native macOS filesystem checkers where available.
- Shows SMART health, temperature, life remaining, power-on hours, media errors, unsafe shutdowns, and provider status.
- Formats native Kelvin temperatures with a Celsius conversion while keeping already-Celsius values in Celsius.
- Converts native macOS and `smartctl` NVMe Data Units Read/Written values to TB while retaining the raw unit count.
- Uses native macOS SMART first, with optional user-installed `smartctl` for deeper ATA/NVMe data.
- Displays limited-support messages for SD/SDXC readers and network volumes instead of treating missing SMART as a drive failure.
- Includes Default, Peak/NVMe, RealWorld, Demo, and Custom benchmark profiles.
- Custom benchmarks support up to 4 test groups with SEQ/RND, block size, Q, T, and mixed-test choices.
- Each profile can use a synchronous or asynchronous engine; Custom can also run in loop mode.
- Benchmark file sizes start at 1 GiB and support Random or 0 Fill data patterns.
- Each green result-row button can run that benchmark item once using the current engine, file size, and data pattern; single-item runs force incremental testing off and keep the write confirmation.
- An optional small-block efficiency control scales the actual test data for 4 KiB, 16 KiB, and 64 KiB items to 5%, 10%, 20%, 30%, or 50%; it is off by default and starts at 20% when first enabled.
- Benchmark results can include the live activity samples captured during the run.
- Live Activity supports 0.1s, 0.2s, 0.5s, and 1s sampling, retained charts, and history saving.
- After stopping Live Activity, Continue Monitoring appends new samples to the existing chart; Start Monitoring keeps the original clear-and-start-new behavior.
- Large-file workloads support read, write, mixed read/write, fixed sizes, and a 95% free-space mode.
- History supports SMART, benchmark, and activity record hiding, hidden-record management, and restore.
- Exports JSON, CSV, and plain-text reports with serial numbers redacted by default.
- Benchmark and live-workload sessions use explicit run and cancellation states, wait for process/file cleanup, and reject late callbacks from superseded work.
- Fixes benchmark cancellation/restart paths that could make the UI stall, while waiting for real cleanup before a new run starts.
- Drive refresh uses bounded concurrency and one `smartctl` scan; only the newest overlapping refresh may update the UI.
- Adds a guarded First Aid flow for explicitly selected external or removable APFS/ExFAT volumes using `diskutil repairVolume`, with preflight checks, open-file warnings, serial streaming output, and post-run refresh.
- Blocks First Aid for failing SMART health, system/internal disks, network or virtual volumes, read-only/locked volumes, and NTFS; NTFS shows Windows CHKDSK guidance only.
- Cancelling a shell command terminates its child process and distinguishes launch failures, non-zero exits, and user cancellation.
- Settings cover virtual-drive visibility, report serial numbers, plain-Tab navigation, and a custom `smartctl` path, with complete Simplified Chinese content.
- Supports `Command-R` to refresh, `Command-P` to open Settings, and `Control-Tab` / `Control-Shift-Tab` to switch feature pages; plain-Tab switching can be disabled.
- Responsive controls and metric grids support smaller windows while wide tables keep horizontal scrolling.
- SwiftData history uses a versioned schema, migration plan, and repository boundary with explicit save/export errors.
- Provides Simplified Chinese and English UI text.

### SMART And External Device Notes

macOS exposes different SMART data depending on NVMe, SATA, USB, SD card, bridge chipset, and network volume behavior. Capricorn reports available data without fabricating ATA normalized fields such as `Current / Worst / Threshold`.

- Internal Apple NVMe drives usually expose a native SMART summary.
- Some external USB-SATA devices require a user-installed SAT SMART Driver or `smartctl`.
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

- `Version = 1.1`
- `Build = 1`
- `Display Name = Capricorn V1.1.1`

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
