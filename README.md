# Capricorn

Capricorn is a macOS SwiftUI utility for DIT-style drive checks. It combines disk inventory, SMART health snapshots, live I/O monitoring, configurable read/write benchmarks, and local history in one desktop app.

The project was formerly named DiskSpeedTest.

## Features

- Lists local physical drives and mounted network volumes.
- Reads native macOS SMART data when available and can use `smartctl` from smartmontools for deeper device details.
- Shows drive health, temperature, life remaining, power-on hours, media errors, unsafe shutdowns, and provider status.
- Runs configurable benchmark profiles with sequential, random, read, write, and mixed tests.
- Supports synchronous tests and POSIX AIO queue-depth tests.
- Offers loop and extreme loop profiles for sustained storage checks.
- Monitors live per-disk I/O counters through IOKit for local disks.
- Can generate temporary read, write, or mixed live-activity workloads.
- Stores SMART snapshots, benchmark results, and live-activity records with hide/restore controls.
- Exports drive reports as JSON, CSV, or plain text, with serial numbers redacted by default.
- Provides English and Simplified Chinese UI text.

## Requirements

- macOS 14.0 or later
- Xcode with Swift 5 support
- Optional: smartmontools (`smartctl`) for extended SMART details, especially on devices where macOS exposes limited native SMART fields

## Optional smartctl Support

Capricorn does not bundle smartmontools or install `smartctl` automatically. It uses macOS native SMART data when available, then looks for an existing `smartctl` installation at `/opt/homebrew/bin/smartctl`, `/usr/local/bin/smartctl`, or `/usr/sbin/smartctl`.

Install smartmontools with Homebrew:

```sh
brew install smartmontools
```

Apple Silicon Homebrew usually installs `smartctl` at `/opt/homebrew/bin/smartctl`; Intel Homebrew usually uses `/usr/local/bin/smartctl`. Restart or refresh Capricorn after installation. See the [Homebrew smartmontools formula](https://formulae.brew.sh/formula/smartmontools) for package details.

## Build

Open `Capricorn.xcodeproj` in Xcode, select the `Capricorn` scheme, and build or run the app.

From Terminal:

```sh
xcodebuild -project Capricorn.xcodeproj -scheme Capricorn -destination 'platform=macOS' build
```

Run tests:

```sh
xcodebuild test -project Capricorn.xcodeproj -scheme Capricorn -destination 'platform=macOS'
```

## Safety Notes

Capricorn creates temporary files in the selected benchmark or workload folder. Write, mixed, loop, and large workload tests can use significant free space and can stress storage devices. Choose the target folder carefully, avoid critical production volumes, and stop loop tests when you have enough data.

Network volumes can be benchmarked as mounted folders, but they do not expose local per-disk IOKit activity counters or SMART data.

## License

This project is licensed under the GNU General Public License version 3 only.

SPDX-License-Identifier: GPL-3.0-only

See `LICENSE` for the full license text.

---

# Capricorn 中文说明

Capricorn 是一个面向 macOS 的 SwiftUI DIT 磁盘检查工具。它把磁盘盘点、SMART 健康快照、实时 I/O 监控、可配置读写测速和本地历史记录集中在一个桌面应用里。

本项目旧名称为 DiskSpeedTest。

## 功能

- 列出本机物理磁盘和已挂载的网络卷。
- 在可用时读取 macOS 原生 SMART 数据，也可以使用 smartmontools 的 `smartctl` 获取更完整的设备信息。
- 显示磁盘健康、温度、剩余寿命、通电小时、介质错误、不安全关机次数和数据来源状态。
- 运行可配置测速配置，支持连续、随机、读取、写入和混合测试。
- 支持同步测试和基于 POSIX AIO 的队列深度测试。
- 提供循环和极限循环配置，用于持续存储检查。
- 通过 IOKit 监控本机磁盘实时 I/O 计数。
- 可生成读取、写入或混合的实时活动负载临时文件。
- 保存 SMART 快照、测速结果和实时活动记录，并支持隐藏/恢复。
- 可导出 JSON、CSV 或纯文本报告，默认隐藏序列号。
- 内置英文和简体中文界面文本。

## 环境要求

- macOS 14.0 或更高版本
- 支持 Swift 5 的 Xcode
- 可选：smartmontools（`smartctl`），用于在 macOS 原生 SMART 字段有限时读取更详细的设备信息

## 可选 smartctl 支持

Capricorn 不会内置 smartmontools，也不会自动安装 `smartctl`。它会优先使用 macOS 原生 SMART 数据，然后查找现有的 `smartctl`：`/opt/homebrew/bin/smartctl`、`/usr/local/bin/smartctl` 或 `/usr/sbin/smartctl`。

可以通过 Homebrew 安装 smartmontools：

```sh
brew install smartmontools
```

Apple Silicon 的 Homebrew 通常会把 `smartctl` 安装到 `/opt/homebrew/bin/smartctl`；Intel Mac 的 Homebrew 通常使用 `/usr/local/bin/smartctl`。安装后请重启或刷新 Capricorn。软件包详情见 [Homebrew smartmontools formula](https://formulae.brew.sh/formula/smartmontools)。

## 构建

用 Xcode 打开 `Capricorn.xcodeproj`，选择 `Capricorn` scheme，然后构建或运行。

也可以在终端执行：

```sh
xcodebuild -project Capricorn.xcodeproj -scheme Capricorn -destination 'platform=macOS' build
```

运行测试：

```sh
xcodebuild test -project Capricorn.xcodeproj -scheme Capricorn -destination 'platform=macOS'
```

## 安全提示

Capricorn 会在你选择的测速或负载文件夹中创建临时文件。写入、混合、循环和大容量负载测试可能占用大量可用空间，也会对存储设备造成压力。请选择正确的目标文件夹，避免在关键生产卷上测试，并在取得足够数据后及时停止循环测试。

网络卷可以作为已挂载文件夹进行测速，但不会提供本机单盘 IOKit 活动计数，也不会暴露本地 SMART 数据。

## 许可证

本项目仅使用 GNU General Public License version 3 授权。

SPDX-License-Identifier: GPL-3.0-only

完整许可证文本见 `LICENSE`。
