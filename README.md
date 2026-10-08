# Capricorn

Formerly DiskSpeedTest.

Capricorn is a local macOS utility for disk inspection, SMART health checks, storage benchmarking, and live disk activity monitoring.

Capricorn 是一个本地 macOS 工具，用于磁盘检查、SMART 健康状态查看、存储测速和实时磁盘活动监控。

[Latest Release / 最新版本](https://github.com/LexTheAries2209/Capricorn/releases/latest): `v2.9.7`

Bilingual release notes / 双语发布说明：[docs/releases/v2.9.7.md](docs/releases/v2.9.7.md)

Complete release log / 完整更新记录：[CHANGELOG.md](CHANGELOG.md)

---

## 中文说明

### 项目定位

Capricorn 面向需要了解磁盘状态、检查外接设备、测试存储性能和观察实时读写活动的 macOS 用户。

### 下载和安装

前往 [GitHub Releases](https://github.com/LexTheAries2209/Capricorn/releases/latest) 下载 `Capricorn-v2.9.7-macOS.zip`，解压后将 `Capricorn V2.9.7.app` 放到 `Applications` 或其他本地工具目录。

首次打开时，如果 macOS Gatekeeper 显示互联网下载提示，请在 Finder 中右键点击 App 后选择“打开”，或在“系统设置 > 隐私与安全性”中允许打开。

### 核心功能

- 识别本机物理磁盘、外接磁盘、普通挂载分区、网络卷和存储卡。
- 显示磁盘容量、文件系统、设备名称、序列号和连接信息。
- 查看 SMART 健康状态、温度、寿命、通电时间、介质错误和读写数据。
- 支持查看 SMART 自检状态和历史记录。
- 对指定文件夹执行顺序、随机、读取、写入和混合测速。
- 观察实时磁盘读写活动，并运行读写负载。
- 保存、查看和管理 SMART、测速及实时活动历史。
- 提供装载、卸载、推出、重命名、Finder 定位和占用程序查看等磁盘操作。
- 支持简体中文和英文界面。

### 外接设备和 SMART 说明

不同磁盘、存储卡、USB 桥接器和网络卷能够提供的 SMART 信息不同。Capricorn 只显示设备实际提供的数据，不对缺失信息进行推测。

Capricorn 内置 smartmontools 7.5，不会自动安装或移除系统驱动，也不会直接向裸设备写入测速数据。

### 测速和实时活动

测速只在用户选择的文件夹中创建临时测试文件。写入、混合和大文件负载可能对存储设备产生压力，请确认目标位置并保留重要数据备份。

网络卷可以作为挂载文件夹参与测速，但不提供本地物理磁盘级别的全部活动数据。

### 系统要求

- Release build：macOS `14.0` 或更高版本。
- Source build：支持 SwiftUI、SwiftData、IOKit 和 DiskArbitration 的 Xcode。
- App 已内置 smartctl 7.5，无需另外安装 smartmontools。

### 构建和测试

```sh
xcodebuild -project Capricorn.xcodeproj -scheme Capricorn -destination 'platform=macOS' build
```

```sh
xcodebuild test -project Capricorn.xcodeproj -scheme Capricorn -destination 'platform=macOS'
```

---

## English

### Purpose

Capricorn is for macOS users who need to inspect drive status, review external devices, benchmark storage performance, and monitor live disk activity.

### Download And Install

Download `Capricorn-v2.9.7-macOS.zip` from [GitHub Releases](https://github.com/LexTheAries2209/Capricorn/releases/latest), then move `Capricorn V2.9.7.app` to `Applications` or another local tools folder.

On first launch, if macOS Gatekeeper shows an internet-download warning, right-click the app in Finder and choose Open, or allow it from System Settings > Privacy & Security.

### Features

- Identifies local physical disks, external drives, mounted partitions, network volumes, and memory cards.
- Shows capacity, filesystem, device name, serial number, and connection information.
- Displays SMART health, temperature, life remaining, power-on time, media errors, and read/write data.
- Supports SMART self-test status and history.
- Benchmarks a selected folder with sequential, random, read, write, and mixed tests.
- Shows live disk activity and runs read/write workloads.
- Saves, reviews, and manages SMART, benchmark, and live-activity history.
- Provides mount, unmount, eject, rename, Finder reveal, and open-file inspection actions.
- Provides Simplified Chinese and English UI text.

### External Devices And SMART Notes

SMART availability varies across drives, memory cards, USB bridges, and network volumes. Capricorn reports data provided by the device without inferring missing values.

Capricorn bundles smartmontools 7.5. It does not automatically install or remove system drivers, and benchmarks do not write directly to raw devices.

### Benchmark And Live Activity

Benchmarks create temporary files only inside the folder selected by the user. Write, mixed, and large-file workloads can stress storage devices; verify the target and keep important backups.

Network volumes can be benchmarked as mounted folders, but they do not provide all local physical-disk activity data.

### Requirements

- Release build: macOS `14.0` or later.
- Source build: Xcode with SwiftUI, SwiftData, IOKit, and DiskArbitration support.
- smartctl 7.5 is bundled with the App.

### Build And Test

```sh
xcodebuild -project Capricorn.xcodeproj -scheme Capricorn -destination 'platform=macOS' build
```

```sh
xcodebuild test -project Capricorn.xcodeproj -scheme Capricorn -destination 'platform=macOS'
```

---

## License / 授权

Bundled smartctl and its corresponding source are provided under `GPL-2.0-or-later`. See [ThirdParty/smartmontools](ThirdParty/smartmontools) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for source, licenses, and build instructions.

内置 smartctl 及对应源代码按 `GPL-2.0-or-later` 提供。源代码、许可证和构建说明见 [ThirdParty/smartmontools](ThirdParty/smartmontools) 和 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

Capricorn source code is licensed under the GNU General Public License v3.0 only (`GPL-3.0-only`). See [LICENSE](LICENSE).

Capricorn 源代码使用 GNU General Public License v3.0 only (`GPL-3.0-only`) 授权。使用、修改和分发本项目源代码时，请遵守 [LICENSE](LICENSE) 中的条款。

App icons and branding assets are not covered by the GPLv3 source-code license unless explicitly stated otherwise.

软件图标和品牌视觉资源不属于 GPLv3 源代码授权范围，除非另有明确说明。
