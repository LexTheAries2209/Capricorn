# Capricorn 自动更新：Sparkle 适配研究与功能计划

## V3.2.2 / Build 0057：已发布

本次在 Main 准备完整版本 `3.2.2`、独立全局 Build `0057`，上一分发构建为 `0056`。自动 SNT 跳过只读介质和含只读卷的硬盘；错误日志读取移至默认关闭的开发者选项；新增默认关闭的“始终显示 SMART 自检”，SNT 和无 SMART 信息的设备仍不显示。固定 `Capricorn.app`、既有更新公钥和稳定 feed 保持一致。

严格并发、Swift 6、Universal Archive、归档 App 启动、完整 bundle 签名、App/服务/两套运行工具双架构、dSYM UUID 和存档源码独立 Universal Release 构建均通过。20 个真实 Sparkle 隔离场景全部通过，下载中冲突使用两秒下载延迟；安装回归使用隔离 App 和数据，服务衔接使用模拟协调器。

更新包与清单使用既有 Ed25519 密钥签名并复验。真实 Sparkle 候选源确认旧 `0056` 发现 `3.2.2 / 0057`，当前 `0057` 无更新。最终 ZIP 为 14,647,522 字节，SHA-256 为 `b4945c619f76e18893afc1a3a3c8f54eab97e31296c32e775f4a4c9e328087b5`，摘要仅计算一次；仅更新发布说明和重新签名清单，不修改 ZIP。

完整归档/dSYM 位于 `~/Library/Developer/Xcode/Archives/2026-11-11/Capricorn V3.2.2.xcarchive`，版本备份 App、README、固定源码与更新附件位于 `Capricorn旧版软件/Capricorn V3.2.2/`，没有额外桌面副本。沿用 Apple Development 签名，没有 Developer ID 或 Apple 公证。

全量最终 768 项：763 通过、5 项显式硬件/离线实验或证书条件跳过、零失败。首轮虚拟磁盘编辑界面出现三个保存断言失败，单独复跑通过（命令 47.9 秒、测试体 6.1 秒）；第二轮仅旧侧栏截图将完整可见的 `ProtocolEnd` 误识别为 `ProtocolEno`。禁用字段标记的拼写校正并检查 OCR 候选后，全量通过。仅测试代码调整，发布 App 和 ZIP 未改动。

主要本地阶段：严格并发 45.2 秒、Swift 6 47.3 秒、Universal Archive 102.0 秒、独立源码 Universal 构建 187.6 秒、20 个 Sparkle 场景合计 158.7 秒、候选源检查 3.0 秒。首轮全量命令 412.3 秒，第二轮 213.4 秒；最终全量命令 158.6 秒，测试体约 130.2 秒。额外耗时来自旧 UI 测试排查和复跑。

自动化 SNT 验证使用模拟磁盘和命令。此前单块 CODEX 显式手动实验取得错误日志，无有效返回条目；该设备不支持自检，未取得自检记录，也未启动自检。该硬件实验不作为通用 SNT 日志功能。真实多卷恢复、Intel/macOS 14、其他 Mac 服务批准及真实 root 服务跨版本授权保留仍需实机验收。

2026-11-11 已发布为最新正式版，标签及 Release 指向固定提交 `927c0269e2d3a1aa34b021e381163e9a424d37f4`。公开 README、累计日志和三份发布说明与固定提交逐字节一致，发布说明的 GitHub Markdown 渲染链接已核对。ZIP、完整对应源码包和 appcast 的大小与 GitHub digest 均匹配本地证据。

真实 Sparkle 公开稳定源确认旧 `0056` 发现 `3.2.2 / 0057`，当前 `0057` 无更新；公开 ZIP 返回 HTTP 200。公开清单与本地签名文件逐字节一致且签名复验通过。检查使用现有本机系统代理或命令级代理，未修改系统网络。推送 3.3 秒、ZIP 上传 4.9 秒、源码与清单上传 4.9 秒、公开源检查 5.0 秒。

The release was published as latest on November 11, 2026 at `927c0269e2d3a1aa34b021e381163e9a424d37f4`. All public documentation and asset sizes/digests match retained evidence. Real Sparkle public-feed checks confirmed that Build `0056` discovers `3.2.2 / 0057`, while `0057` reports no update. The public ZIP returns HTTP 200, and the public feed matches the signed local file byte for byte.

[GitHub CI](https://github.com/LexTheAries2209/Capricorn/actions/runs/42982095833) 的全量测试、严格并发、Swift 6 三项全部通过；远端完整测试任务约 5 分 25 秒，没有超出本地测试与编译的合理差异范围。All three CI jobs passed: full tests, strict concurrency and Swift 6 compatibility.

构建号已标记为 published；此发布后状态记录另行提交。已发布标签、App、ZIP、源码包和清单不变；版本备份源码保持固定发布提交 `927c026`。

## V3.2.1 / Build 0056：已发布

本次在 Main 准备完整版本 `3.2.1`，独立全局构建号 `0056`，上一分发构建为 `0055`。加入 48 小时 SNT 缓存、采集时间行和 SMART 默认列宽调整；固定 `Capricorn.app`、既有更新公钥与稳定 feed 保持一致。

全量 754 项测试：751 通过、3 项硬件或证书条件跳过、零失败。严格并发、Swift 6、Universal Archive、归档 App 启动、App/服务/两套 smartctl 双架构及同团队证书签名、dSYM UUID、存档源码独立 Universal Release 构建均通过。20 个真实 Sparkle 隔离场景全部通过，服务衔接使用模拟协调器。下载中冲突场景首轮下载先于冲突注入完成，加入两秒下载延迟后通过，未改产品代码。

更新包与清单使用既有 Ed25519 密钥签名并复验。真实 Sparkle 候选源确认旧 `0055` 发现 `3.2.1 / 0056`，当前 `0056` 无更新。最终 ZIP 为 14,641,649 字节，SHA-256 为 `ddd5163e66f2c759f13e3f9256e76d5c9f4d1bf043563f20255f836e34681f49`，摘要仅计算一次。

完整归档/dSYM 位于 `~/Library/Developer/Xcode/Archives/2026-11-03/Capricorn V3.2.1.xcarchive`，版本备份 App、README、固定源码与更新附件位于 `Capricorn旧版软件/Capricorn V3.2.1/`，没有额外桌面副本。沿用 Apple Development 签名，没有 Developer ID 或 Apple 公证。本次未执行真实 USB 接管、卷卸载或硬件自检，Intel/macOS 14、其他 Mac 的服务批准及真实 root 服务跨版本授权保留仍需实机验收。

主要本地阶段：全量测试命令 182.8 秒（测试体约 118.8 秒）、严格并发 44.6 秒、Swift 6 44.3 秒、Universal Archive 101.4 秒、独立源码 Universal 构建 74.8 秒。Sparkle 场景首段含一次条件不足的冲突测试为 61.8 秒，调整条件后其余十二场景为 90.8 秒。候选源检查仅验证发现更新，不等于真实用户 App 安装验收。

2026-11-03 已发布为最新正式版，标签指向 `11782ac7baf01411c8124d9f0c75981359da9479`，发布时 Main 与标签一致。[GitHub CI](https://github.com/LexTheAries2209/Capricorn/actions/runs/41582906416) 的全量测试、严格并发和 Swift 6 三项全部通过。公开 README、累计日志和三份发布说明与固定发布提交逐字节匹配；ZIP、对应源码包和 appcast 的大小与 GitHub digest 均与本地保留证据一致。

真实 Sparkle 公开稳定源确认旧 `0055` 发现 `3.2.1 / 0056`，当前 `0056` 无更新。公开 ZIP 返回 HTTP 200；公开 appcast 与本地签名文件逐字节一致且签名复验通过。链接检查使用本机既有系统代理对应的命令级代理设置，未修改系统网络。推送耗时 2.8 秒，ZIP 上传 4.9 秒，源码和清单上传 4.3 秒，公开源检查 5.0 秒。

The release was published as latest on November 3, 2026 at `11782ac7baf01411c8124d9f0c75981359da9479`. All three CI jobs passed. Real Sparkle public-feed checks confirmed that Build `0055` discovers `3.2.1 / 0056`, while `0056` reports no update. The public ZIP returns HTTP 200; all asset sizes and digests match retained evidence, and the public feed matches the signed local file byte for byte.

构建号已标记为 published；此发布后状态记录另行提交。已发布标签、App、ZIP、源码包和清单不变，版本备份源码保持固定发布提交 `11782ac`。

## V3.2.0 / Build 0055：已发布

自动 SNT 分支已快进合并到 Main。完整版本 `3.2.0`，独立全局构建号 `0055`，上一分发构建为 `0054`；固定 `Capricorn.app`、既有更新公钥和稳定 feed 保持一致。

新增启动及接入时的可选自动 SNT 读取、最近有效数据缓存和失败暂停，保留手动重试；设备服务未启用或连接异常时开关不可用，点击红色感叹号查看提示。自动读取默认关闭，服务和卷权限就绪且磁盘空闲时才执行，不重复逐次确认。

本机全量 747 项测试：744 通过、3 项硬件或证书条件跳过、0 失败。严格并发、Swift 6、Universal Archive、归档 App 启动、双架构与 dSYM UUID、完整 bundle 和嵌入服务/工具同团队证书签名、存档源码独立 Universal Release 构建均通过。20 个真实 Sparkle 隔离场景全部通过；服务衔接使用模拟协调器，不等于真实 root 服务跨版本批准保留验收。

更新包与清单使用既有 Ed25519 密钥签名并复验。真实 Sparkle 候选签名源确认旧 `0054` 发现 `3.2.0 / 0055`，当前 `0055` 无更新。ZIP 为 14,632,134 字节，SHA-256 为 `097d2d3911eac59f02cf4e0ede8695ad73b8a4509ef9a0a5d706bfbb52a74328`，最终 ZIP 摘要仅计算一次。

完整归档/dSYM 位于 `~/Library/Developer/Xcode/Archives/2026-11-02/Capricorn V3.2.0.xcarchive`；App、README、源码与 `update/` 下的 ZIP、源码包及签名清单保存在 `Capricorn旧版软件/Capricorn V3.2.0/`，无额外桌面副本。采用同团队 Apple Development 证书，没有 Developer ID 或 Apple 公证。

本次未执行真实 USB 接管、卷卸载或硬件自检。真实权限撤销与重新授权、全系统占用可见性、接管中拔盘、多卷挂载恢复、Intel/macOS 14 及其他 Mac 的服务批准仍需实机验收。自动读取的卷可访问检查不等于系统隐私授权状态查询，不保证所有权限变化场景都无系统弹窗。

主要本地阶段：全量测试命令 178.0 秒（测试体约 119.7 秒）、严格并发 37.9 秒、Swift 6 37.6 秒、Universal Archive 92.1 秒、独立源码 Universal 构建 72.4 秒、20 个 Sparkle 场景 144.9 秒。Git 拉取首次传输因低速超时，通过 API 核对远端 Main 与本地相同后再快进合并，未强制更新历史。

2026-11-02 已发布为最新正式版，标签指向 `283afc7e9392311e876e588a35f80be49a8acfff`，发布时 Main 与标签一致。GitHub Release 的 ZIP、源码包及 appcast 大小和 digest 均与保留的本地证据一致；公开 README、累计日志和三份发布说明与固定发布提交逐字节匹配。[CI](https://github.com/LexTheAries2209/Capricorn/actions/runs/41440616799) 的全量测试、严格并发及 Swift 6 三项全部通过，无重复标签任务。

真实 Sparkle 公开稳定源检查确认旧 `0054` 发现 `3.2.0 / 0055`，当前 `0055` 无更新。公开 ZIP 返回 HTTP 200，公开清单与本地签名文件逐字节一致且签名复验通过。链接检查使用本机已配置的 HTTP 代理，未修改系统网络设置。普通 HTTPS 推送通过单次命令使用该代理，2.7 秒完成；ZIP 与源码/清单上传分别为 7.8 秒和 7.9 秒。公开更新发现检查耗时 4.4 秒，不代表真实用户 App 的安装验收；隔离安装和实机验证边界见上文。

The release was published as latest on November 2, 2026 at `283afc7e9392311e876e588a35f80be49a8acfff`, after merging the automatic-SNT branch into Main. All three CI jobs passed. Real Sparkle public-feed checks confirmed that Build `0054` discovers `3.2.0 / 0055`, while `0055` reports no update. The public ZIP returns HTTP 200; all asset sizes and digests match retained evidence, and the public feed matches the signed local file byte for byte.

构建号已标记为 published；此发布后记录单独提交，不改变已发布标签、App、ZIP、源码包或签名清单。版本备份源码保持固定发布提交 `283afc7`，完整 xcarchive/dSYM、签名更新附件及验证日志均保留。

## V3.1.4 / Build 0054：已发布

本次改善 SMART 表格：横向滚动、列宽上限、来源列拖动、紧凑固定状态列，以及来源默认宽度向 ID 转移。完整版本 `3.1.4`，独立全局构建号 `0054`，上一分发构建为 `0053`。固定 `Capricorn.app`、既有更新公钥及稳定 feed 保持一致。

2026-11-02 发布为最新正式版，标签指向 `a8e5a8325bd505e19fd10ece414106645a6b023b`。发布时 Main 与标签一致；公开 README、累计日志和三份发布说明均与本地对应文件一致。公开 ZIP、对应源码包及 appcast 的大小和 GitHub digest 均与本地保留记录一致。

全量 724 项测试：721 通过、3 跳过、0 失败；跳过两项显式启用的硬件检查及无证书测试主程序的证书专属检查。严格并发、Swift 6、Universal Archive、归档 App 启动、App/服务/工具双架构与同团队证书签名、dSYM UUID 核对、存档源码独立 Universal Release 构建均通过。20 个真实 Sparkle 隔离场景全部通过；服务衔接使用模拟协调器，不等于真实 root 服务跨版本授权保留验收。

真实 Sparkle 候选签名源确认旧 `0053` 发现 `3.1.4 / 0054`，当前 `0054` 无更新。ZIP 为 14,501,067 字节，SHA-256 为 `933d92056e31f52a4a2fc03c72ce3ee35dc16eb85877949656e90eb52375d1f5`；更新包及清单使用既有 Ed25519 密钥签名并复验。

发布后的公开稳定源也由真实 Sparkle 验证：旧 `0053` 发现 `3.1.4 / 0054`，当前 `0054` 无更新。[GitHub CI](https://github.com/LexTheAries2209/Capricorn/actions/runs/41391402874) 的全量测试、严格并发和 Swift 6 三项检查全部通过，无重复标签任务。公开更新源检查仅验证更新发现；隔离安装回归覆盖及服务衔接限制见前文。

公开 ZIP 链接返回 HTTP 200，公开 appcast 与本地签名文件逐字节一致且签名有效。命令行直连 GitHub 超时后，使用本机已配置的 HTTP 代理完成链接和清单下载检查，未修改系统网络设置。

The release was published as latest on November 2, 2026 at `a8e5a8325bd505e19fd10ece414106645a6b023b`. All three GitHub CI jobs passed. Real Sparkle public-feed checks confirmed that Build `0053` discovers `3.1.4 / 0054`, while `0054` reports no update. The public ZIP returns HTTP 200; all asset sizes and digests match retained local evidence, and the public feed matches the signed local file byte for byte.

完整 xcarchive/dSYM 保存在 `~/Library/Developer/Xcode/Archives/2026-11-02/Capricorn V3.1.4.xcarchive`，版本备份位于 `Capricorn旧版软件/Capricorn V3.1.4/`，包含 App、README、固定发布源码快照和 `update/` 下的更新包、对应源码包及签名清单，无额外桌面副本。使用同团队 Apple Development 证书，没有 Developer ID 或 Apple 公证。本次未执行真实 SNT 接管、卷卸载或硬件自检。

主要本地阶段：全量测试命令 173.4 秒（测试体约 116 秒）、严格并发 35.7 秒、Swift 6 35.9 秒、Universal Archive 90.3 秒、独立源码 Universal 构建 77.2 秒、20 个 Sparkle 场景 146.1 秒、签名包准备 1.6 秒、候选签名源验证 2.7 秒。最终 ZIP 摘要仅计算一次。

## V3.1.3 / Build 0053：已发布

本次修复 APFS 外置硬盘被误报为无法唯一确定 SMART 目标的问题，改善 SMART 与 SNT 的设备识别和目标异常提示。完整版本 `3.1.3`，独立全局构建号 `0053`，上一分发构建为 `0052`。固定 `Capricorn.app`、既有更新公钥与稳定 feed 保持一致。

2026-11-02 发布为最新正式版，标签指向 `3074c69558879d1b31c745580fa109a4374daaaf`。发布时 Main 与标签一致；公开 README、累计日志和三份发布说明均与本地对应文件一致。公开 ZIP、对应源码包与 appcast 的大小及 GitHub digest 均与本地保留记录一致。

全量 721 项测试：719 通过、2 跳过、0 失败；跳过 root 硬件操作检查及无证书测试主程序的证书专属检查。真实 USB APFS 只读身份检查通过：物理盘 `disk6` 可匹配，合成盘 `disk7` 被排除。严格并发、Swift 6、Universal Archive、归档 App 启动、App/服务/工具双架构与同团队证书签名、dSYM UUID 核对、存档源码独立 Universal Release 构建通过。20 个真实 Sparkle 隔离场景全部通过；服务衔接使用模拟协调器。

完整 xcarchive/dSYM 保存在 `~/Library/Developer/Xcode/Archives/2026-11-02/Capricorn V3.1.3.xcarchive`；版本备份位于 `Capricorn旧版软件/Capricorn V3.1.3/`。采用同团队 Apple Development 证书，没有 Developer ID 或 Apple 公证。本次未执行真实 SNT 接管、卷卸载或硬件自检。

更新包与清单 Ed25519 签名复验通过。真实 Sparkle 候选签名源确认旧 `0052` 发现 `3.1.3 / 0053`，当前 `0053` 无更新。ZIP 为 14,493,316 字节，SHA-256 为 `3e26074384894ef84d8483064a6ab6899572b171b6373d272135ea840706f044`。

发布后的公开稳定源也由真实 Sparkle 验证：旧 `0052` 发现 `3.1.3 / 0053`，当前 `0053` 无更新。公开 ZIP 链接返回 HTTP 200，公开清单与本地签名文件逐字节一致。[GitHub CI](https://github.com/LexTheAries2209/Capricorn/actions/runs/41380876859) 的全量测试、严格并发和 Swift 6 三项检查全部通过，无重复标签任务。公开更新源检查仅验证更新发现；隔离安装回归的覆盖与服务衔接限制见前文及详细发布说明。

The release was published as latest on November 2, 2026 at `3074c69558879d1b31c745580fa109a4374daaaf`. All three GitHub CI jobs passed. Real Sparkle public-feed checks confirmed that Build `0052` discovers `3.1.3 / 0053`, while `0053` reports no update. The public ZIP returns HTTP 200; all asset sizes and digests match retained local evidence, and the public feed matches the signed local file byte for byte.

主要本地阶段：全量测试命令 158.5 秒（测试体约 133 秒）、严格并发 99.0 秒、Swift 6 99.3 秒；首次 Archive 88.6 秒，修正显示名称后重新归档 65.2 秒；独立源码 Universal 构建 68.1 秒，显示名称同步后的增量验证 3.5 秒；签名包准备 1.5 秒。保留第一次归档于本地遗弃目录，实际发布使用显示名称核对通过的新归档；源码未更改，无需重复全量行为测试。ZIP 摘要仅计算一次。

## V3.1.2 / Build 0052：已发布

本次包含 SNT 磁盘正忙时的有限次卸载重试与占用程序提示，界面未新增按钮。完整版本 `3.1.2`，独立全局构建号 `0052`，上一分发构建为 `0051`。固定 `Capricorn.app`、既有更新公钥及稳定 feed 保持一致。

2026-11-01 发布为最新正式版，标签指向 `7a5f16bc2f65f92fbf1f2fa3af08060ad7cbdcd5`。Main 与发布标签、公开 README、累计日志和三份发布说明均已核对。固定发布提交的源码快照逐文件匹配，公开 ZIP、对应源码包和 appcast 的大小及 GitHub digest 均与本地保留记录一致。

全量 713 项测试：710 通过、3 跳过、0 失败；跳过两项显式启用的硬件检查及无证书测试主程序的证书专属检查。严格并发、Swift 6、Universal Archive、归档 App 启动、App/服务/两套 smartctl 双架构及同团队证书签名、dSYM UUID 核对、存档源码独立 Universal Release 构建均通过。20 个真实 Sparkle 隔离场景全部通过，服务衔接场景使用模拟协调器。

候选签名源已由真实 Sparkle 验证：旧 `0051` 发现 `3.1.2 / 0052`，当前 `0052` 无更新。更新包和清单使用既有 Ed25519 密钥签名并复验。ZIP 为 14,483,697 字节，SHA-256 为 `2d32dd7c88845eb20c049e0f224dbf2c687ad9d495dc380d8097fc2db1562f5e`。

发布后的公开稳定源也由真实 Sparkle 验证：旧 `0051` 发现 `3.1.2 / 0052`，当前 `0052` 无更新。公开 ZIP 链接返回 HTTP 200，公开清单与本地签名文件逐字节一致且签名有效。[GitHub CI](https://github.com/LexTheAries2209/Capricorn/actions/runs/41320475462) 的全量测试、严格并发和 Swift 6 三项检查全部通过，无重复标签任务。

完整 xcarchive/dSYM 保存在 `~/Library/Developer/Xcode/Archives/2026-11-01/Capricorn V3.1.2.xcarchive`；版本备份的 App、README、源码快照和 `update/` 下的 ZIP、对应源码包及签名清单保存在 `Capricorn旧版软件/Capricorn V3.1.2/`，无额外桌面副本。App、服务和工具采用同团队 Apple Development 证书，没有 Developer ID 或 Apple 公证。未复现真实 SanDisk 占用故障，未执行真实 SNT 接管、卷卸载或硬件自检。

主要阶段：Universal Archive 92.9 秒、全量测试命令 175.3 秒（测试体约 114.5 秒）、严格并发 38.1 秒、Swift 6 38.6 秒、独立源码通用构建 73.1 秒、签名包准备 1.5 秒、候选源验证 4.5 秒、推送 4.8 秒、ZIP 上传 8.7 秒、源码与清单上传 6.2 秒、公开源验证 8.7 秒。测试宿主使用单次框架搜索路径配置避免 Desktop 构建缓存加载停滞；未修改项目或 CI 配置。构建完成后仅更新文档，最终 ZIP 摘要只计算一次；发布状态另行提交，保留已发布附件和标签。

## V3.1.1 / Build 0051：已发布

2026-11-01 发布为最新正式版，标签指向 `9e449cb51485bca35daaaec6777e27333f920501`。Main 包含 USB 集线器设备识别、无效 SMART 响应与异常缓存过滤、完整设备目标匹配及中文提示修复。完整版本 `3.1.1`，独立全局构建号 `0051`；固定 `Capricorn.app`、既有更新公钥及稳定 feed 保持一致。

本机全量 705 项测试：702 通过、3 跳过、0 失败。跳过两项显式启用的硬件检查和无证书测试主程序的证书专属检查；分发归档另行通过同团队证书签名验证。严格并发、Swift 6、Universal Archive、归档 App 启动、双架构与 dSYM UUID 核对、完整 bundle 及工具签名均通过。20 个真实 Sparkle 隔离场景全部通过，服务衔接场景使用模拟协调器。存档源码独立 Universal Release 构建通过，最终源码快照逐文件匹配发布提交。

真实 Sparkle 对候选及公开稳定源均验证：旧 `0050` 发现 `3.1.1 / 0051`，当前 `0051` 无更新。公开 ZIP 返回 HTTP 200，公开 appcast 与本地签名文件逐字节一致；ZIP、源码包及清单的 GitHub 大小和摘要均正确。ZIP 为 14,462,662 字节，SHA-256 为 `f4b39ce9dabdcc097954e720c1b828a6a87451270d002baee3b9b816dc6c88cf`。

完整 xcarchive/dSYM 保存在 `~/Library/Developer/Xcode/Archives/2026-11-01/Capricorn V3.1.1.xcarchive`，App、README、固定发布提交的源码快照与 `update/` 下的 ZIP、对应源码包及签名清单保存在 `Capricorn旧版软件/Capricorn V3.1.1/`。没有额外桌面副本。对应源码包含两套 smartctl 上游源码包、SNT 补丁、构建脚本与许可证。App、服务和工具使用同团队 Apple Development 证书，更新包及清单使用既有 Ed25519 密钥；没有 Developer ID 或 Apple 公证。

多级集线器下真实 USB 标识只读验证已通过；本次没有实际 SNT 接管、卸载卷或硬件自检。修复不代表设备获得 SMART 能力；没有可信响应时应显示不可用。Intel、macOS 14、其他 Mac 的证书信任与服务批准，以及真实 root 服务跨版本授权保留仍需对应环境验收。

[GitHub CI](https://github.com/LexTheAries2209/Capricorn/actions/runs/41310651013) 的全量测试、严格并发与 Swift 6 三项检查全部通过。发布提交对应的 Main 工作流只运行一次，没有重复标签任务。

主要阶段：Universal Archive 81.77 秒、全量测试命令 140.95 秒（测试体约 119.4 秒）、严格并发 3.48 秒、Swift 6 3.05 秒、独立源码通用构建 75.61 秒、推送 4.0 秒、ZIP 上传 9.1 秒，源码与 feed 上传 6.3 秒。构建完成后只更新文档；未重复构建或重新计算最终 ZIP 摘要。发布后的状态记录单独提交，标签与已发布附件保持不变。

## V3.1.0 / Build 0050：已发布

2026-11-01 发布为最新正式版，标签指向 `4ce59162f846c1e67d34b94bad369c9764e4dd23`。特权设备服务分支已快进合并到 Main。版本为 `3.1.0`，独立全局构建号 `0050`；保持固定 `Capricorn.app`、既有更新公钥和稳定 feed。

本机发布验证：全量 688 项测试，679 通过、9 项环境或硬件条件跳过、0 失败。严格并发、Swift 6、Universal Archive、归档 App 启动、双架构和 dSYM UUID、完整 bundle 及辅助程序签名通过。20 个真实 Sparkle 隔离场景通过，服务衔接场景使用模拟协调器，不能代替真实 root 服务跨版本授权验收。存档源码独立 Universal Release 构建用时 72.94 秒。

候选与公开源均由真实 Sparkle 验证：旧 `0049` 发现 `3.1.0 / 0050`，当前 `0050` 无更新。公开 ZIP 返回 HTTP 200，公开 appcast 与本地签名文件逐字节一致。ZIP 为 14,451,792 字节，SHA-256 为 `8ee44da6084f1a746a68d5f080d8c9594d5d60d5c1326f3d8bd557121693f9fc`；ZIP、源码包与 feed 的 GitHub 大小和摘要均已核对。

完整 xcarchive/dSYM 保存在 `~/Library/Developer/Xcode/Archives/2026-11-01/Capricorn V3.1.0.xcarchive`，App、README、源码快照及 `update/` 下的包和签名 feed 保存在 `Capricorn旧版软件/Capricorn V3.1.0/`，无额外桌面副本。源码包来自固定发布提交，包含两套 smartctl 对应源码、SNT 补丁、构建脚本和许可证。

App、特权服务和工具使用同一团队 Apple Development 证书，更新继续使用既有 Ed25519 密钥；没有 Developer ID 或 Apple 公证。真实 USB-SNT 隐私归属、接管和恢复挂载、硬件自检启动/中止，以及其他 Mac 的服务批准仍需对应环境验收。

发布提交的首轮 CI 严格并发与 Swift 6 通过，全量测试有一项失败：无证书 CI 构建直接运行了要求证书团队的签名集成测试。后续提交 `9937aab` 只修正测试前置条件：先确认无证书或 ad-hoc 主程序被服务拒绝，再跳过证书专属校验；有证书构建继续执行完整校验。本机两种配置均验证通过，[后续 CI](https://github.com/LexTheAries2209/Capricorn/actions/runs/41292243441) 的全量测试、严格并发和 Swift 6 三项全部通过。发布标签、App、ZIP、源码包和签名 feed 均保持原样。

## V3.0.0 / Build 0049：已发布

SNT 分支已快进合并到 Main。完整版本为 `3.0.0`，独立全局构建号 `0049`，上一分发构建为 `0048`。

全量 648 项测试通过，零失败、零跳过；严格并发、Swift 6、Universal Archive、双架构 dSYM UUID、完整 bundle 与嵌入 SNT 工具签名、归档 App 启动和独立存档源码 Universal Release 构建通过。Swift 6 保留已有的 `init(cString:)` 弃用警告。

19 个真实 Sparkle 隔离场景全部通过，包含手动和自动安装保留历史与偏好、取消、任务冲突、签名拒绝与启动检查。测试使用独立 App、历史与偏好，不替换真实用户 App 或数据库。

真实 Sparkle 验证候选签名源：`0048` 发现 `3.0.0 / 0049`，`0049` 无更新。ZIP 为 13,407,049 字节，SHA-256 为 `c68e15dcd52131f78ba550478ba12fea99b2be07b82b01995c83a98886f8c6d4`。更新包和清单使用既有 Ed25519 密钥签名并复验；App 延续有效 ad-hoc 分发，没有 Developer ID 或 Apple 公证。完整 xcarchive/dSYM、版本备份 App/README/源码和 ZIP/feed 均保留，无额外桌面副本。

正式标签指向 `602d7e3afbc2aa7b53b699dcba3638ffd1114e62`，已设为最新正式版。[GitHub CI](https://github.com/LexTheAries2209/Capricorn/actions/runs/41026985016) 三项检查全部通过。真实 Sparkle 对公开稳定源完成 `0048` 发现新版本、`0049` 无更新验证；公开 ZIP 返回 HTTP 200，附件大小与 GitHub ZIP digest 一致，公开 appcast 与本地逐字节一致且签名有效。网络验证通过本机已配置的代理完成，没有修改系统网络设置。

Release 同时提供固定发布提交生成的 `Capricorn-v3.0.0-source.tar.gz`，包含 smartctl 7.5 与实验性 SNT 工具的对应源码、本地补丁、许可证及构建脚本。发布后的构建号状态与验证记录单独提交，已发布的 App、ZIP、feed 和标签保持不变。

## V2.12.0 / Build 0048：已发布

2026-10-29 发布共享硬盘连接拓扑版本，标签指向 `a5c507d53ac252a67ca624a643a7baed43093b31`，已设为最新正式版。继续使用固定 `Capricorn.app`、既有公钥和稳定 feed，不改变更新下载与安装策略。

最终全量 601 项测试通过，无失败或跳过；严格并发、Swift 6、Universal Archive、双架构 dSYM UUID、完整 bundle 签名和归档 App 启动通过。首轮系统截屏命令失败经单项和最终全量复测通过。19 个真实 Sparkle 隔离场景通过，手动与自动安装保留测试历史及偏好；下载中冲突场景使用两秒延迟确保冲突注入。安装测试没有替换真实用户 App 或数据库。

候选签名源已由真实 Sparkle 核验：`0047` 发现 `2.12.0 / 0048`，`0048` 无更新。最终 ZIP 为 12,290,365 字节，SHA-256 为 `d9270836dac1634e2c38e2709cc94386cd13f1c4128f3f70b75adf44e39ee9f0`；更新包和清单使用既有 Ed25519 密钥签名并复验。App 继续使用有效 ad-hoc bundle 签名，没有 Developer ID 或 Apple 公证。

存档源码已通过独立 Universal Release 构建，完整 xcarchive/dSYM 和版本备份保留；无额外桌面副本。

[GitHub CI](https://github.com/LexTheAries2209/Capricorn/actions/runs/40835823957) 的全量测试、严格并发和 Swift 6 三项检查全部通过。GitHub 附件大小及 ZIP 摘要与本地一致，从 Releases API 下载的公开 appcast 与本地签名文件逐字节一致并通过签名复验。本机系统代理未启用，直连 github.com 超时（URLSession `NSURLErrorDomain -1001`），因此发布后客户端直接读取稳定源及直连下载链接验证未完成；不将候选源通过视为该项通过。

最终归档阶段约 58.5 秒，全量测试命令约 126.2 秒，其中测试执行约 101.4 秒。常规 HTTPS 推送断开后使用受保护 Git Data API 保留全部原提交并以 `force=false` 更新 Main，后备同步约 159.7 秒；ZIP 上传约 8.4 秒。首轮编译检查修正和网络诊断增加了发布耗时。

## V2.11.1 / Build 0047：已发布

2026-10-19 发布为最新正式版，标签指向 `2240d9a0b716284b92a087327c60a84336c33a74`。

- 启动自动检查、手动检查、版本发现及更新说明不再受磁盘任务阻止；检查过程中启动刷新或其他任务，也不取消检查、不弹冲突提示。启动开关、每次启动仅一次和 15 秒截止保持不变。
- 开发者自动更新发现新版时先静默检查任务冲突；忙碌时保留可用版本，不下载安装包，不弹窗，任务完成后不自动恢复。用户可在空闲后手动检查，或在下一次启动时再次尝试。
- 手动选择下载时仍检查全部任务冲突并提示；下载过程中出现冲突，仍取消下载并提示。已进入解压或安装准备时，任务冲突仍按原策略处理。
- 安装确认、恢复安装及更新退出前继续复查冲突；获准安装时保存历史并阻止新磁盘任务，保存失败拒绝安装。普通退出继续取消尚未确认的安装。
- 以下发布记录保留对应版本的历史行为。

开发阶段验证：全量 529 项测试全部通过，零失败、零跳过；10 个真实 Sparkle 隔离场景通过，覆盖检查前/检查中刷新、开发者自动发现时静默延后且任务结束不自动重试、手动下载冲突、下载中新增刷新、安装准备冲突、手动/自动完整安装、普通退出取消及 15 秒截止后手动重试。成功安装保留测试历史与偏好，受阻安装保持旧版。测试使用独立测试 App、偏好与数据库。发布构建另行执行完整质量检查与签名源验证。

发布候选验证：最终全量 529 项测试全部通过，无失败或跳过；严格并发、Swift 6、Universal Archive、双架构 dSYM UUID、完整 bundle 签名、独立存档源码构建及归档 App 启动通过。首轮实时活动续采样等待失败单项复测通过，第二轮截图 OCR 将 Efficiency 识别为 Efficlency；仅兼容该 OCR 字形偏差后，相关单项与最终全量通过。19 个真实 Sparkle 隔离场景全部通过。原有 Ed25519 密钥已验证候选清单及安装包签名，候选签名源由真实 Sparkle 验证：`0046` 发现 `2.11.1 / 0047`，`0047` 无更新。

发布后公开签名源同样通过真实 Sparkle 验证，公开 ZIP 返回 HTTP 200，GitHub 附件大小及 ZIP 摘要与本地最终包一致，公开清单与本地签名文件逐字节一致。完整 xcarchive/dSYM、版本备份 App/README/源码、最终 ZIP 及签名 feed 均保留，无额外桌面副本。仍使用有效 ad-hoc bundle 签名，没有 Developer ID 或 Apple 公证。发布操作中按标签查询草稿 API 返回 404，后续命令仍执行了发布；随后已完整复核公开 Release、目标提交及全部附件，均正确。

[GitHub CI](https://github.com/LexTheAries2209/Capricorn/actions/runs/39229427935) 的全量测试、严格并发与 Swift 6 三项检查全部通过。主要阶段耗时：Universal Archive 80.6 秒、严格并发 35.4 秒、Swift 6 36.1 秒、存档源码独立构建 55.1 秒、最终全量 113.2 秒、ZIP 上传 6.2 秒。两次全量复核及 OCR 排查增加了发布耗时；未重复构建或重新计算最终 ZIP 摘要。

## V2.11.0 / Build 0046：已发布

2026-10-19 发布为最新正式版，标签指向 `b98afe5847febada3d366298b0fd5ce60b1f3da9`。本次更新测速及大文件负载，保留既有启动检查、开发者自动安装、冲突拦截和历史保存策略。

全量测试 525 项：517 通过、8 项截图检查因录屏权限不足跳过、0 失败。严格并发、Swift 6、Universal Archive 和存档源码独立构建通过；归档 App 已启动，主程序与 dSYM 双架构 UUID 对应。17 个真实 Sparkle 隔离场景全部通过，手动与开发者自动安装保留测试历史和偏好，取消、关闭自动更新、冲突、签名拒绝、404 及启动检查均通过。

真实 Sparkle 验证候选及发布后的公开签名源：`0045` 发现 `2.11.0 / 0046`，`0046` 无更新。公开 ZIP 返回 HTTP 200，GitHub 附件大小及摘要与本地最终包一致。[CI 三项检查全部通过](https://github.com/LexTheAries2209/Capricorn/actions/runs/39223391828)。

完整 xcarchive/dSYM、版本备份 App/README/源码与 `update/` 下的 ZIP/签名 feed 均保留，无额外桌面副本。继续使用有效 ad-hoc bundle 签名和既有 Ed25519 密钥，没有 Developer ID 或 Apple 公证。安装回归仍使用独立测试 App，不替换实际用户 App 或数据库。

## V2.10.5 / Build 0045：已发布

2026-10-18 发布为最新正式版，标签指向 `fcb3a703fea55ea5565c5ee3851768470472efcb`。开发者自动下载并安装默认关闭，启动检查仍使用原有显式选择和 15 秒截止；未启用开发者自动更新时继续手动确认。以下各版本记录保留历史策略。

本次全量测试 488 项通过，无失败或跳过；严格并发、Swift 6、Universal Archive 与存档源码独立构建通过。17 个真实 Sparkle 隔离场景通过，包含手动安装、开发者自动安装、关闭选项、取消或普通退出、冲突阻止、签名拒绝、404 和启动检查；成功安装保留测试历史与偏好。候选及发布后的公开签名源均由真实 Sparkle 核验：`0044` 发现 `2.10.5 / 0045`，`0045` 无更新。公开 ZIP 返回 HTTP 200，大小和 GitHub digest 与本地一致；[CI 三项检查全部通过](https://github.com/LexTheAries2209/Capricorn/actions/runs/39104133695)。

App 继续使用有效 ad-hoc bundle 签名与既有 Ed25519 更新密钥，没有 Developer ID 或 Apple 公证；安装测试使用独立测试 App，不替换实际用户 App 或数据库。完整 xcarchive/dSYM、版本备份 App/README/源码与 `update/` ZIP/feed 均保留，无额外桌面副本。

调研日期：2026-10-17，Asia/Shanghai。状态：P0–P2 已随 V2.10.2 / Build 0042 发布；V2.10.3 / Build 0043 已发布，包含后续提示窗口、启动检查截止与许可入口改进。

V2.10.3 发布核验：全量 460 项测试通过，零失败、零跳过；严格并发、Swift 6、Universal Release Archive 和存档源码独立构建通过。[GitHub CI](https://github.com/LexTheAries2209/Capricorn/actions/runs/39029308503) 三项检查全部通过。10 个隔离更新场景通过；公开签名源已由真实 Sparkle 核验，旧 `0042` 发现 `2.10.3 / 0043`，当前 `0043` 判定为最新。ZIP 大小与 GitHub 摘要一致，归档 App 的两处许可入口与完整文本切换通过界面验证。安装回归使用独立测试 App，不替换真实用户 App；保留的旧版备份、ZIP/feed、完整 xcarchive 与 dSYM 均已核验。

### V2.10.3 后续设置调整（未发布）

移除应用菜单、设置中的第三方许可阅读入口及独立窗口。原“SMART”设置模块改为“第三方组件”，按 Sparkle、smartctl、SAT SMART Drive 的顺序显示组件信息和项目链接。Sparkle 版本读取实际加载框架的元数据。完整第三方说明和上游许可继续保存在源码中，保留随包许可资源，不在软件界面展示全文；历史发布说明和已发布产物不改写。本次只合并源码到 Main，不创建新 Release。

后续本地调整（未推送）：发现新版本时，设置状态补充“请点击‘检查更新’下载并安装”，中英文均使用实际版本号，长文本允许自然换行。使用当前 App 本地化声明与原有签名公开源的隔离预览，确认新版发现窗口的中文标题、说明、自动下载复选框和安装/跳过按钮均已翻译，英文预览仍为英文。两个底部按钮的坐标均为 y=20 pt、height=28 pt、centerY=34 pt，无需改变 Sparkle 原生布局。截图中的英文界面来自旧 V2.10.2；已有本地化声明修复继续保留。预览回复固定为 dismiss，不下载安装更新、不使用真实用户偏好与数据库。

本次严格并发构建通过，30 项相关回归复核全部通过，无失败或跳过。首轮设置滚动定位断言失败，关闭预览窗口后单项与整组复核均通过；没有额外修改定位逻辑。修改仅作本地提交，不推送或发布。

## 后续本地调整：开发者自动更新（未发布）

- “开发者选项 → 自动下载并安装更新”是唯一设置入口，默认关闭，使用独立偏好保存；旧 Sparkle 自动下载选择不会迁移为同意。关闭开发者总开关会停用此能力但保留子开关选择，重置所有设置则清除选择。
- 启动检查仍由原开关控制，开启开发者自动更新本身不触发网络请求。开启后，检查到普通新版本即自动下载，准备完成并通过任务冲突检查及历史保存后安装并重启；信息更新或要求明确同意的重大升级仍沿用标准流程。
- 在发现版本和安装前分别读取当前开发者授权。自动下载途中关闭选项或开发者总开关后，准备完成将回到手动安装确认；有冲突或保存失败不会自动安装，也不会在冲突消失后擅自重试。
- `SUAllowsAutomaticUpdates=NO` 和 `SUAutomaticallyUpdate=NO` 保持不变，Sparkle 原生更新窗口和许可询问均不提供自动下载复选框。应用的用户驱动层依据开发者授权选择下载与安装，安装器、签名校验和退出协调继续使用原有实现。
- V2.10.4 已发布的 App、ZIP、签名 feed 与发布说明保持原样，以下记录保留其手动更新策略。

本次验证：29 项更新控制器、偏好持久化/重置及中英文开发者设置测试通过，无失败、无跳过；严格并发与 Swift 6 构建通过。12 个真实 Sparkle 隔离场景通过，包含开发者自动完整安装、开发者总开关关闭时零包请求、检查前及安装前冲突阻止、下载期间关闭自动选项后恢复手动确认，以及原有手动安装、取消/普通退出、包与清单签名拒绝和 15 秒截止。成功安装使用测试编号 `0041 → 0042`，保留测试历史与偏好；未替换真实用户 App。中英文设置截图确认该开关仅随开发者子选项显示，默认关闭。原生复选框继续由现有 `SUAllowsAutomaticUpdates=NO` 禁用，没有修改第三方框架。本次仅作本地修改和提交，未推送或发布。

## V2.10.4：仅由用户下载与安装

V2.10.4 / Build 0044 发布准备核验：全量 464 项测试通过，零失败、零跳过；严格并发、Swift 6、Universal Archive 和源码备份独立构建通过。首轮开发者设置 OCR 将“虚”识别为“虛”，复用已有归一化规则后全量通过。12 个隔离场景均通过，准备完成后取消与普通退出保持旧版，手动完整安装保留测试历史与偏好；慢速启动清单在 15.004 秒结束并允许手动重试。归档 App 的更新开关、第三方组件和开发者设置已核对；候选签名源确认 `0043` 发现 `2.10.4 / 0044`，`0044` 无更新。完整归档和 dSYM 保留在 Xcode Archives，版本备份的 `update/` 保存同一最终 ZIP 与签名 feed，不生成额外桌面产物。

V2.10.4 已发布为最新正式版，标签指向 `0e6569a21baa833069362c0efe775473e05b4cee`。发布后的公开签名源同样通过旧版发现/当前无更新验证，公开 ZIP 链接返回 HTTP 200，GitHub ZIP digest 与保留的本地摘要一致。[GitHub CI](https://github.com/LexTheAries2209/Capricorn/actions/runs/39041318731) 三项检查全部通过。主要阶段耗时：归档 59.8 秒、严格并发 15.5 秒、Swift 6 15.5 秒、最终全量测试 95.2 秒、源码备份构建 53.9 秒；包含一次 OCR 误报的定位和全量复核。

- 保留默认关闭的启动检查与 15 秒截止，启动检查只发现版本，不下载安装包。
- 移除设置中的自动下载/退出安装开关及 API，`SUAllowsAutomaticUpdates=NO` 隐藏 Sparkle 原生窗口的自动下载选项；初始化时将旧 `SUAutomaticallyUpdate` 偏好置为 false，更新器始终关闭自动下载。
- 用户手动打开新版窗口并选择下载，准备完成后再明确确认安装并重启。普通退出若遇到尚未确认的准备任务，先取消并等待更新周期结束，再继续退出，不以退出作为安装确认。晚到的确认回调不能重新启动已取消的安装。
- 对旧版本遗留的 installing 阶段任务发送 skip，取消其退出安装安排；需要更新时由用户重新手动检查。保留冲突拦截、安装前历史保存、签名验证和已确认安装的退出许可。
- 以下自动下载/退出安装的结果属于 V2.10.2 / V2.10.3 历史验证，不描述当前本地策略。已发布产物和历史发布说明保持原样。

本次验证：全量测试 464 项中 463 项通过，一项虚拟硬盘截图测试因系统截屏命令返回错误失败，单独复测通过；没有修改该测试或相关功能。严格并发与 Swift 6 构建通过，后者仅保留原有的 `init(cString:)` 弃用警告。真实 Sparkle 隔离测试确认：旧自动下载偏好为 true 时，启动检查仍只请求一次清单、零安装包请求；手动确认完成 Build 0041 → 0042 并保留测试历史与偏好；准备完成后取消或普通退出，均取消安装并保持 Build 0041，安装占用已释放。上述 Build 仅用于独立测试 App，不修改公开版本。

原生中文窗口的隔离预览确认：可见操作只剩“安装更新”和“跳过这个版本”，自动下载复选框已隐藏；两按钮仍同高（y=20 pt、height=28 pt）。预览不下载安装包，未使用真实用户偏好与数据库。

## 历史实施记录

分支：`codex/sparkle-updates-p0-p2`。以下保留历史实现、最初研究与分期依据；当前交互以“最新本地策略”为准。

- 已锁定 Sparkle 2.10.0，通过单一更新器接管菜单与设置入口；设置页出现不再主动检查。
- 首次集成版本为完整 `2.10.2`，内部构建号 `0042`：已核实此前有 41 次正式 Release，以此作为一次性迁移基线。后续采用四位、全局递增的独立发布构建号。详见 [版本规则](versioning.md) 和 [构建号分配记录](../Configuration/ReleaseBuilds.json)。
- 保持 App 产物固定名 `Capricorn.app` 和 bundle ID `lex.Capricorn`。
- 自动检查现已改为用户启用后每次启动检查一次，不再按时间间隔检查。自动下载/退出时安装另行选择，默认关闭；后台更新采用温和提醒，菜单显示可用版本。V2.10.3 加入启动检查 15 秒无结果自动结束、不自动重试的策略。
- 任何冲突任务均弹窗并阻止更新检查或安装，不会强行停止磁盘任务；已下载更新在退出时仍需通过冲突与保存检查。手动下载期间出现冲突会取消下载。后台自动下载可能已取得部分或全部字节，但不能因此越过安装和退出检查。
- 安装获准后禁止新磁盘任务进入，并保存主 SwiftData context；保存失败会释放安装占用并拒绝退出。
- 拦截安装确认回复和恢复安装路径，使用 AppKit 应用退出代理覆盖退出时安装，不能只依赖 relaunch 代理。
- 更新 UI 与错误提示提供中英文。原生 Sparkle 窗口采用应用下次启动时的语言；应用内切换语言后显示重启提示。
- 启用解压前签名验证、更新清单签名及无限期拒绝无效清单，不启用失败过期回退。禁用系统画像数据发送。
- 新增 `scripts/prepare-sparkle-update.py`，校验 App 身份、签名和版本，生成完整包与已签名 appcast，并检查包长和签名；脚本不发布任何资源。
- 完整 Sparkle 与附带组件许可已加入仓库和 App Resources。V2.10.3 在应用菜单和设置提供第三方许可窗口，读取打包后的 `Contents/Resources/LICENSE` 与 smartctl 的 `COPYING`。

真实安装测试使用 `scripts/test-sparkle-update.py` 和仅用于测试的独立 App，bundle ID 为 `lex.Capricorn.UpdateFixture`，运行目录位于用户 Caches 下。测试使用独立临时密钥、偏好和 SwiftData store，没有访问 Capricorn 的实际历史数据库，也未使用生产私钥。

| 测试场景 | 已验证结果 |
| --- | --- |
| 手动完整包更新 | Build 0041 → 0042，替换后重启；测试历史与偏好保留 |
| 自动下载后退出安装 | 退出后安装 Build 0042，再次启动；测试历史与偏好保留 |
| 有测速冲突 | 弹窗回调被触发，无更新下载；保持 Build 0041 |
| 更新包字节被篡改 | 显示签名错误，保持 Build 0041 |
| 已签名更新清单被篡改 | 显示签名错误，不下载安装包；保持 Build 0041 |
| 更新清单返回 HTTP 404 | 显示下载失败与检查发布文件提示；保持 Build 0041 |
| 确认窗口出现后才开始冲突任务 | 单元测试验证安装回复被转换为取消，不占用安装许可 |
| 自动更新已准备后出现冲突 | 单元测试验证提示并拒绝更新退出 |
| 保存失败 | 单元测试验证拒绝安装、释放占用 |
| 连续两次启动 | 即使上次检查时间刚更新，每个进程仍恰好请求一次清单；同一进程重复启动回调不重复请求 |
| 关闭启动检查 | 即使旧 Sparkle 开关曾开启，仍不启动更新器或请求清单 |
| 启动时有冲突 | 弹出阻止提示，零网络请求 |

验证环境为本机 Apple silicon。安装测试使用无 Hardened Runtime 的 ad-hoc 测试 App，不证明 Developer ID、公证、隔离下载、Intel 或 macOS 14 真机上的安装行为。V2.10.2 同样采用完整 bundle ad-hoc 签名并关闭 Hardened Runtime，已验证归档 App 正常启动；没有 Developer ID 或公证信任链。业务数据库已有测试在正常测试套件中回归，安装测试不等于对真实用户数据库进行了迁移演练。

生产 Ed25519 私钥已保存在登录 Keychain 的 `lex.Capricorn` 账号中，公钥嵌入 App。V2.10.2 已成功使用该密钥签名清单和安装包，并验证签名；没有将生产私钥导出为文件，其备份和恢复演练尚未完成。独立安装测试仍使用测试密钥。

配置的稳定 feed 地址是 GitHub Releases 的 `releases/latest/download/appcast.xml`。V2.10.1 及更早公开版本没有 Sparkle，需手动安装 V2.10.2 一次。发布后已使用真实 Sparkle 读取公开签名清单：旧 Build 0041 发现 2.10.2 / 0042，当前 0042 判定为最新；实际归档 App 的手动检查也显示 2.10.2 为最新。公开 ZIP 大小与 GitHub SHA-256 digest 均匹配本地最终包。全量测试、严格并发、Swift 6 的 [发布 CI](https://github.com/LexTheAries2209/Capricorn/actions/runs/39008671960) 全部通过；后文保留历史阶段的验证记录。

### 原生窗口语言修复（V2.10.3）

V2.10.2 的主 App 未声明中文本地化，导致即使 `appLanguage` 和 `AppleLanguages` 已选择中文，Sparkle 原生窗口仍回退为英文。修复在 `CFBundleLocalizations` 中声明 `en` 和 `zh-Hans`，并同步 Xcode 的已知语言；继续使用 Sparkle 自带的完整翻译，不修改第三方框架。

27 项更新、冲突和设置回归测试全部通过。重新编译并启动的实际 App 已确认“您使用的就是最新版！”、版本说明和“好”按钮为中文；使用同一语言声明及 Sparkle 标准界面的独立检查窗口确认“软件更新”“正在检查更新…”和“取消”为中文，英文模式仍显示英文。语言切换仍需重启后应用于原生更新窗口；已公开的 V2.10.2 安装包未替换。

### 统一检查提示窗口（V2.10.3）

手动检查的进度、最新版本结果、更新错误与任务冲突提示统一使用应用管理的原生 `NSAlert`，恢复最初系统提示框的图标、留白和按钮样式，不再使用自绘 SwiftUI 窗口。首次打开时居中于当前应用窗口所在屏幕，切换状态时结束旧提示框并创建新提示框，保持中心位置；尺寸由系统根据正文自动排版。取消检查会触发取消回调，结果和错误在确认时完成对应回调。Sparkle 结束更新会话时只关闭属于该会话的提示，不关闭应用独立弹出的冲突警告。

中文弹框正文使用系统分句器按完整句子分行，保留既有段落和任务列表，不按字节或固定字符数截断，版本号与网址保持完整。单句本身较长时由系统根据实际文本宽度折行。设置页的短提示保持原样。提示框排入主运行循环，由 `NSAlert.runModal()` 管理鼠标、键盘和系统按钮处理，不接管 AppKit 保留的 target/action，也不再通过定时轮询自行驱动模态会话。网络回调切换状态时会唤醒并结束旧模态循环，待其退出后再显示下一状态。

应用管理的更新提示统一将图标、标题与正文居中，覆盖系统针对多行正文采用的默认左对齐布局。弹框文案先分句换行，再去掉句末标点；版本号小数点与链接内符号保留，设置页文案不受此格式处理影响。原生按钮、模态交接和紧凑尺寸保持原有行为。

新版下载确认与安装流程继续使用 Sparkle 的原生界面及现有安全检查。此前全量测试 458 项中 450 项通过、0 失败，8 项截图测试因录屏权限跳过；真实独立测试 App 的手动更新、自动下载后退出安装、冲突阻止及清单 404 场景通过，两条升级路径保留测试历史与偏好。

2026-10-17 后续修复：复现了停止动画后等待圈仍留在结果正文中，以及直接调用按钮动作有效、真实鼠标点击无效的差异。现在显式移除旧 accessory 视图并使用完整原生模态流程。31 项提示框、更新控制器及安全检查测试通过，严格并发构建和提示框组件的 Swift 6 warnings-as-errors 编译通过。完整 App 连续两次读取公开 feed 后显示最新版本，结果中没有等待圈，鼠标确认和回车均可关闭；独立慢速检查的鼠标取消和 Esc 也通过。回归测试覆盖真实模态循环内的连续状态切换、等待圈清理、回调次数及应用独立冲突提示的保留。本次另行通过真实 Sparkle 的隔离手动完整升级（Build `0041 → 0042`），测试历史与偏好均保留。

### 四位构建号迁移

后续版本规则以 [versioning.md](versioning.md) 为准。2026-10-17 核对 GitHub 完整分页列表、累计日志与完整发布说明，三者均为 41 个正式版本；下一分发构建预留为 `0042`，并非声称已找回全部本地编译次数。原开发值 `1000` 未公开发布，不计为历史发布构建；新规则不修改历史安装包或将旧版补丁 Build 追溯改写为累计序号。

四位编号已完成 21 项更新与版本测试及全部 9 个真实 Sparkle 场景回归。实际 App 的 `CFBundleVersion` 为字符串 `0042`，签名 appcast 也保留 `0042`；Sparkle 的数值比较与 `0041 → 0042` 两条安装路径均通过。前述表格及后续安装测试统一采用这两个测试编号。早期阶段留下的 `1000/1001` 验证记录仅描述当时的测试数据。

### 启动检查与偏好持久化

2026-10-17 后续调整以本节为准，替代原计划中的每日定时检查和 Sparkle 默认询问机制。

- 设置改名为“启动时自动检查更新”，默认关闭。开关在 `AppUpdater` 初始化时读取，修改时立即保存，不再依赖更新器启动来加载或写入，因此 Debug 下重新打开应用也能正确显示。
- 应用完成首次磁盘刷新后调用启动检查，每个进程只处理一次；重复打开窗口不会再查。开启后的下次启动会检查，不依据 `SULastCheckTime` 或 24 小时间隔；本次打开设置或修改开关不会发起网络请求。
- Release 和 Debug 均遵循已保存的显式选择；测试、演示及禁用启动任务的环境仍不自动联网。手动检查不受启动检查开关限制。
- 新键 `checksForUpdatesOnLaunch` 表示应用自管的启动检查。没有该键时读取原 `SUEnableAutomaticChecks` 的用户选择，首次启动更新器时先保存迁移值，再关闭 Sparkle 的定时调度；迁移后新选择优先。
- `SUEnableAutomaticChecks=NO` 禁用 Sparkle 自身的定时器和默认许可询问，移除 `SUScheduledCheckInterval`。`SUAllowsAutomaticUpdates=YES` 保留用户另行开启自动下载的能力，不代表默认启用；下载偏好继续使用 `SUAutomaticallyUpdate`，默认关闭。
- 上次检查时间在更新器未启动时也能加载，仅供显示，不决定是否检查。有冲突仍提示并阻止，本次启动不会在任务结束后自动补查；可手动重试。
- 启动检查设 15 秒总截止时间（V2.10.3），不按网络是否持续返回少量数据续期。超时后清理当前 Sparkle 检查器，依靠其销毁流程取消清单请求，设置页显示超时状态，不弹出错误窗口、不安排自动重试；下次启动或手动检查时可创建新实例。旧驱动解除与应用的绑定，迟到的取消、结果与界面清理回调不会覆盖新的检查状态。
- 收到可用版本、确认无更新、检查失败或离开检查阶段时取消截止计时。手动检查及已经开始的更新包下载、解压和安装不受此 15 秒限制；任务冲突提示继续保留。
- “重置所有设置”会关闭启动检查与自动下载。

15 秒截止的后续验证（V2.10.3）：32 项更新控制器、提示框和安全检查测试通过，严格并发构建通过，真实测试 App 使用 Swift 6 编译。每秒持续返回清单字节的请求在 15.004 秒结束，服务器确认连接被取消；应用保持打开不自动重试，随后手动检查成功。更新包响应另暂停 16 秒，自动下载及退出安装仍成功完成，测试历史与偏好保留。

增量验证：21 项更新、冲突、设置导航和翻译测试通过，无失败、无跳过，严格并发构建与 Swift 6 构建通过；Swift 6 仍有原有 `init(cString:)` 弃用警告。独立测试 App 验证连续两次启动共两次清单请求、关闭时零请求、冲突时零请求，以及手动完整更新、启动检查后的自动下载/退出安装两条路径；两条安装路径均为 Build 1000 → 1001，测试历史与偏好保留。没有发布公开更新源。

### 系统代理与网络诊断

Sparkle 2.10.0 的 `SPUDownloader` 使用 `URLSessionConfiguration.default`，没有覆盖代理字典。Apple 文档说明代理字典默认为空时遵循系统设置。因此检查清单、发布说明和更新包下载共用 macOS 的代理策略，包括代理自动配置与绕过规则；应用未设置“先直连再代理”的策略，也未固定任何本地端口。仅在终端设置代理环境变量不等于已配置 macOS 系统代理。

2026-10-17 本机实测：默认配置和显式复制系统代理配置均报告 `URLSessionTaskTransactionMetrics.isProxyConnection = true`，目标 feed 均返回 HTTP 404；GitHub 首页可达，而最新 `v2.10.1` Release 只有 ZIP，尚无 `appcast.xml`。此时无法更新的原因是清单未发布，不能归因为系统代理未生效。

只读诊断脚本使用与 Sparkle 相同的默认会话配置，输出每一跳的主机、是否经代理及 HTTP 状态，不修改系统网络设置，也不输出代理凭据：

```sh
xcrun swift scripts/diagnose-update-network.swift \
  https://github.com \
  https://github.com/LexTheAries2209/Capricorn/releases/latest/download/appcast.xml
```

所有请求成功时退出码为 0；HTTP 错误或连接失败时为 1，参数错误为 2。`proxy=true` 说明该跳使用代理，不说明代理服务内部一定选择了远端代理线路。

Sparkle 不为 HTTP 失败提供结构化状态码，而是同样使用 `SUDownloadError`。应用对其显示通用下载失败与检查 Release 文件的恢复提示；只有底层连接错误才显示网络/系统代理提示，不解析本地化错误字符串来猜测 404。清单解析、签名验证和冲突阻止仍保留独立提示。

本次增量验证：`AppUpdaterTests` 10 项通过，无失败或跳过；真实 Sparkle 的 `missing-feed` 场景返回 404 后显示下载失败，保持 Build 1000；诊断脚本通过 Swift 6 与 warnings-as-errors 检查，且成功报告代理路径与状态码。首次 Xcode 测试宿主在 Desktop 构建目录的动态库加载阶段等待，结束该测试后改用 `~/Library/Caches/CapricornProxyValidation` 构建输出并通过；未结束用户原来运行的 Capricorn。

官方依据：[Sparkle 2.10.0 下载器](https://github.com/sparkle-project/Sparkle/blob/2.10.0/Downloader/SPUDownloader.m)；[Apple connectionProxyDictionary](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/connectionproxydictionary)。

P0–P2 初始实现的本地验证记录（后续增量验证见上述各节）：

- 最终全量测试：439 项通过，无失败、无跳过。
- 严格并发与 Swift 6 兼容构建通过；Swift 6 保留原有 `init(cString:)` 弃用警告。
- Universal Release Archive 成功，包含 arm64 和 x86_64；主程序与 dSYM UUID 对应。
- 归档使用 Apple Development 签名与 Hardened Runtime，`codesign --verify --deep --strict` 通过；不代表 Developer ID 或公证完成。
- 已在真实 Capricorn 界面启动只读活动监控，确认“检查更新”弹出中文冲突提示；之后已停止测试监控。
- 中英文更新设置布局及语言重启提示已人工检查，原中文偏好已恢复。
- 安装测试覆盖两种成功升级路径和三种拒绝路径；测试日志位于工作区 `tmp/sparkle-*.log`，测试 App 和独立 store 位于 `~/Library/Caches/CapricornUpdateFixtures/`。

后续验证可使用解压后的官方 Sparkle 2.10.0 完整归档目录（包含 `Sparkle.framework` 和 `bin`）：

```sh
python3 scripts/test-sparkle-update.py --sparkle-root tmp/sparkle-tools --scenario update
python3 scripts/test-sparkle-update.py --sparkle-root tmp/sparkle-tools --scenario manual-only
python3 scripts/test-sparkle-update.py --sparkle-root tmp/sparkle-tools --scenario cancel-install
python3 scripts/test-sparkle-update.py --sparkle-root tmp/sparkle-tools --scenario quit-before-install
python3 scripts/test-sparkle-update.py --sparkle-root tmp/sparkle-tools --scenario conflict
python3 scripts/test-sparkle-update.py --sparkle-root tmp/sparkle-tools --scenario archive-signature
python3 scripts/test-sparkle-update.py --sparkle-root tmp/sparkle-tools --scenario feed-signature
python3 scripts/test-sparkle-update.py --sparkle-root tmp/sparkle-tools --scenario missing-feed
python3 scripts/test-sparkle-update.py --sparkle-root tmp/sparkle-tools --scenario launch-checks
python3 scripts/test-sparkle-update.py --sparkle-root tmp/sparkle-tools --scenario launch-disabled
python3 scripts/test-sparkle-update.py --sparkle-root tmp/sparkle-tools --scenario launch-conflict
python3 scripts/test-sparkle-update.py --sparkle-root tmp/sparkle-tools --scenario launch-timeout
python3 scripts/test-sparkle-update.py --sparkle-root tmp/sparkle-tools --scenario update --archive-delay 16
```

正式发布保持三段营销版本和四位全局递增 Build。发布准备脚本的 `--previous-build` 在首次迁移时使用 `0041`，之后使用实际上一分发构建的全局序号；脚本拒绝非四位、零值、相同或倒退的构建。`--download-url-prefix` 指向即将发布的固定版本附件目录，输出目录必须尚不存在。V2.10.2 已通过生产密钥签名及复验。没有 Developer ID 和公证时，使用 `--allow-unnotarized`（兼容旧参数 `--allow-development-signing`）明确接受信任限制，但仍强制验证完整 bundle 和 Ed25519 签名。密钥备份建议尽快完成，不作为这次发布的先决条件。

## 结论

建议采用 Sparkle 2 承担 Capricorn 的应用内更新流程，保留 GitHub Releases 作为安装包分发和人工下载入口。现有 GitHub API 检查器可作为旧版迁移入口；新客户端由 Sparkle 统一管理更新检查，避免两个调度器重复工作。

技术适配度高，主要工作集中在版本规则、发布包结构、签名和安装前的任务协调，并非替换一个网络请求就完成。建议第一阶段交付“自动检查 + 用户确认下载和安装 + 安全重启”，之后再评估自动下载、退出时安装、测试版通道和灰度更新。

截至调研时，Sparkle 最新正式版为 **2.10.0**，发布于 2026-09-13；其 Swift Package 清单最低要求 macOS 12，低于 Capricorn 的 macOS 14 最低要求。[S1][S2]

最初研究阶段检查了源码、工程配置、CI、当时的发布说明、GitHub Release 元数据及桌面的 `Capricorn V2.10.1.app`。研究阶段尚未集成框架或进行真实升级测试；后续实施结果见前文。

## 当前机制与差距

| 项目 | 已核实的 Capricorn 状态 | 接入影响 |
| --- | --- | --- |
| 更新来源 | `GitHubReleaseService` 请求公开仓库的 `/releases/latest`，拒绝草稿和预发布 | GitHub Release JSON 不能直接作为 Sparkle appcast |
| 触发 | 主窗口启动后每进程检查一次；设置页出现时检查；菜单也可触发 | 改为 Sparkle 调度，合并菜单与设置入口，避免重复请求 |
| 实际行为 | 展示版本、发布正文和网页链接，无下载、校验、替换、重启 | Sparkle 提供这段缺失流程 |
| 版本 | `CFBundleShortVersionString=2.10`，`CFBundleVersion=1`，当前代码拼为 `2.10.1` | Sparkle 默认比较 `CFBundleVersion`，现有规则不能直接沿用 |
| 应用名称 | 发布包内为 `Capricorn V2.10.1.app`；工程产物名为 `Capricorn` | Sparkle 官方发布指引要求更新包内 App 名称保持一致，建议固定为 `Capricorn.app` [S10] |
| 系统与架构 | macOS 14+；当前桌面 App 为 arm64/x86_64 universal | 无最低系统版本冲突；继续发布 universal 完整包 |
| 沙盒与运行时 | 工程关闭 App Sandbox，启用 Hardened Runtime | 不需引入沙盒专用 XPC 开关；必须验证实际分发包能加载框架 |
| 发布签名 | 当前桌面 App 仅有 linker ad-hoc 签名，无 TeamIdentifier；严格验证报告 `code object is not signed at all` | 不能宣称已有 Developer ID 信任链或完整 bundle 签名 |
| 发布流水线 | `.github/workflows/quality.yml` 执行测试、严格并发和 Swift 6 构建，使用 `CODE_SIGNING_ALLOWED=NO` | 需要独立的更新产物、签名和 appcast 发布步骤 |
| 数据保存 | SwiftData 位于 Application Support 下的 `CapricornHistory/CapricornHistory.store`，已有 V2→V3→V4 迁移 | 保持 bundle ID、路径与迁移计划；替换 App 不代表数据库迁移自动成功 |

本地证据：

- `Capricorn/Services/Updates/AppUpdateService.swift`
- `Capricorn/Features/Updates/AppUpdateSettingsSection.swift`
- `Capricorn/App/CapricornApp.swift`
- `Capricorn/App/ContentView.swift` 中的侧栏版本显示
- `CapricornTests/UpdateTests.swift`
- `Capricorn.xcodeproj/project.pbxproj`
- `Capricorn/Persistence/PersistenceBoundary.swift`
- `Capricorn/Services/DiskCoordination/DiskOperationLock.swift`
- `.github/workflows/quality.yml`
- `docs/releases/v2.10.1.en.md`

远端检查：Capricorn 最新正式 Release 为 `v2.10.1`，附件为 `Capricorn-v2.10.1-macOS.zip`，大小 9,889,199 字节。本轮只核对元数据，没有重新下载或重新计算附件 SHA。[S9]

## 接入设计

### 1. 单一更新控制器

在 App 生命周期创建一个持久的更新控制器，内部持有 `SPUStandardUpdaterController`，使用 Sparkle 标准更新窗口。SwiftUI 菜单与设置页调用同一实例，依据 `canCheckForUpdates` 控制按钮是否可用。[S3]

建议调整：

- 在现有 Updates 服务目录封装 Sparkle 与应用状态的衔接，不重写下载器或安装器。
- `AppUpdateSettingsSection` 保留当前版本、上次检查时间、自动检查开关及手动下载入口。
- 设置页出现不再强制触发检查；菜单的“检查更新”直接进入 Sparkle 的用户主动检查流程。
- GitHub API 路径只保留明确用途，例如仍在维护的旧版或开发构建；线上稳定版不同时启用两套更新调度。
- 对测试和演示构建沿用 `ApplicationRuntime` 的启动任务隔离；调试构建默认不访问正式更新源。
- 原计划将偏好直接绑定 Sparkle；后续已改为应用控制启动检查，迁移与调度方式见“启动检查与偏好持久化”。下载偏好仍复用 Sparkle 的存储键与启动后的 API。[S3][S5]

### 2. 版本和应用身份

建议在首次集成版统一版本字段：

| 字段 | 建议示例 | 用途 |
| --- | --- | --- |
| `CFBundleShortVersionString` | `2.11.0` | 完整用户可见版本 |
| `CFBundleVersion` | `0042`，之后 `0043`、`0044` | 四位全局递增发布构建号，不随小版本归零 |
| `sparkle:shortVersionString` | `2.11.0` | appcast 的展示版本 |
| `sparkle:version` | `0042` | 与安装包实际构建号及四位格式一致 |
| App 文件名 | `Capricorn.app` | 后续每个更新包保持一致 |
| Bundle ID | `lex.Capricorn` | 保持现有偏好与应用身份 |
| `SUBundleName` | `Capricorn` | 避免更新提示重复拼接版本 |

营销版本示例不预定下一次公开版本。构建号 `0042` 已按 41 次历史 Release 预留，后续分配以构建号记录为准；同一 appcast 下所有可升级构建均递增，稳定版也必须能够超过先前测试版的构建号。[S4][S10]

`AppVersion.current` 及其测试已使用完整营销版本，不能把新构建号拼成 `2.11.0.0042`。设置页和侧栏显示营销版本；构建号默认隐藏，在开发者选项中开启后独立展示。不要依赖自定义版本比较器来补救字段规则：Sparkle 2.10.0 已将相关代理 API 标为弃用，安装阶段还可能使用标准比较器。[S7]

### 3. 分发、安全与密钥

需要区分两种签名：

- **Sparkle Ed25519 签名**验证更新包是否由持有私钥的发布者生成，公钥通过 `SUPublicEDKey` 嵌入已安装的 App。
- **Apple Developer ID 签名与公证**服务于 macOS 对 App、框架和辅助程序的信任与分发体验。Ed25519 签名不能代替它们。[S4][S8]

两种推进路径：

| 路径 | 条件与用途 | 交付边界 |
| --- | --- | --- |
| 小范围试运行 | HTTPS、Ed25519 包签名、有效的整体 bundle 签名及框架加载验证 | 可以验证更新链；不承诺消除 Gatekeeper 提示或首次手动允许 |
| 推荐的正式分发 | 上述条件，加 Developer ID、正确签署嵌套代码、公证及最终分发验证 | 以有下载隔离属性的真实环境验证完整体验 |

缺少 Developer ID 并不等于 Sparkle 完全无法工作。其验证逻辑可接受 Ed25519 信任链；但损坏的 Apple 代码签名仍可能导致拒绝更新，当前只有链接器签名的产物也不能直接视为可用的正式更新产物。[S8]

工程虽启用了 Hardened Runtime，当前无证书的分发方式在接入框架后仍需重新验证 Library Validation。开发环境可用现有 Apple Development 签名验证加载；发行环境优先使用 Developer ID。若研究 ad-hoc 试运行路径，须单独证明其加载和验证行为，不能直接把开发包验证结论用于分发包。[S4]

建议首版启用 `SUVerifyUpdateBeforeExtraction=YES`。同时将 `SURequireSignedFeed=YES` 纳入首版验证，保护版本信息和发布说明；签名后的 feed/说明一旦变更必须重新签名。其默认 20 天失败过期回退需要明确记录并测试，不能把默认行为描述为永不回退的严格模式。[S6]

私钥保存在受控 Keychain 或受保护的发布环境，不进入仓库、日志或安装包。建立加密备份与恢复演练。启用解压前验证后，Ed25519 密钥轮换的 Developer ID 后备要求是已签名的 DMG；只有 ZIP 的现有流程不能假定具备该恢复能力。[S4]

### 4. Appcast 与发布流程

建议架构：

```text
Capricorn -> HTTPS appcast -> GitHub Releases 中的固定版本 ZIP
          -> Sparkle 校验 -> 等待任务安全结束 -> 安装并重启
```

appcast 和发布说明可托管在 GitHub Pages 或独立静态 HTTPS 站点；安装包继续放 GitHub Releases。无需新增业务后端。当前项目中未配置 Sparkle 托管地址，需要在实施前确定一个长期稳定的 `SUFeedURL`。GitHub 相关网络可达性仍然需要实测，换框架本身不能解决访问受限。[S4]

发布顺序建议：

1. 确认递增构建号、营销版本、最低系统要求和目标提交。
2. 完成测试与 universal Archive；正确签署 smartctl、Sparkle 框架、辅助程序和主 App，按选定分发路径完成公证验证。
3. 用保留符号链接与权限的打包方式生成最终 ZIP，包内只放固定名称的 App。
4. 使用已锁定版本的 `generate_appcast` 生成元数据及签名。首版关闭 delta 生成，只发布完整更新包。
5. 上传不可变版本附件及发布说明，核对公开地址、字节长度和签名对应的最终字节；签名后不再修改包。
6. 确认附件可下载后，再发布 appcast，防止客户端看到未就绪的更新。签名 feed 与其引用资源一起校验。
7. 从前一集成版真实更新，检查新版本启动、内置 smartctl、历史数据和偏好；保留本次验证记录。

官方支持 ZIP 和增量更新，但当前完整 ZIP 约 9.9 MB，首版采用完整包更便于验证。是否引入增量包，待框架接入后测量最终体积和实际收益再决定。[S4][S9]

发布工作应继续覆盖现有双语文档、旧版源码归档和 CI 验证，并增加 appcast 与密钥流程。产物摘要只在必要发布检查点计算并复用，不反复对同一文件计算 SHA。

### 5. 安装与磁盘任务协调

这是 Capricorn 相比普通工具的主要定制工作。应用退出可能中断正在运行的命令、临时文件清理、结果保存和进度监控。

| 运行状态 | 建议行为 |
| --- | --- |
| 空闲 | 用户确认后安装并重启 |
| 测速或大文件负载运行、停止清理中 | 等待工作停止、清理和结果保存完成，再允许更新退出 |
| 磁盘检查、急救、装载/卸载等命令运行中 | 等待命令和必要刷新完成；不为更新强制结束任务 |
| SMART 自检启动、监控或停止中 | 首版保守延后更新；之后单独研究跨重启恢复监控 |
| 只读活动监控 | 停止采样并保存应保存的记录后进入安装 |
| 数据保存或迁移尚未完成 | 等待完成；保存失败时阻止更新退出并提示原因 |

设备内部 SMART 自检与 App 监控不是同一个生命周期，不能笼统宣称退出 App 必然停止设备自检；首版延后安装是为保留现有监控和会话记录。

实现时复用现有 session 状态、磁盘操作锁和任务完成事件，建立集中安装许可判断；现有磁盘锁以磁盘为粒度，不能直接当作整个 App 的退出许可。进入最终安装阶段后阻止新磁盘任务启动，避免“检查空闲后又开始任务”的竞态。

不能仅依赖 `shouldPostponeRelaunchForUpdate`：官方明确说明该代理并非所有安装路径都会调用。需结合更新代理与 AppKit 退出协商，验证手动安装、已下载后安装、退出时安装等路径；完成清理和保存后再继续退出。[S7]

### 6. 数据与故障恢复

保持 `lex.Capricorn`、历史目录、数据库文件名和现有 SwiftData 迁移边界。首次集成版尽量不同时改变业务 schema，降低升级变量。

更新前完成保存；对有 schema 变化的后续版本，设计并验证 SQLite 一致性备份，不能在数据库仍写入时只复制主 `.store` 文件。安装失败保护旧 App 与数据库，安装后迁移失败提供明确错误和恢复路径。

线上有问题时先停止继续投放，再以更高构建号发布修复。人工恢复旧 App 需要同时检查数据库兼容性；Sparkle 的安装保护不等于升级后数据库可以自动降级。

更新请求不附带磁盘型号、序列号、SMART 或历史记录，保持 `SUEnableSystemProfiling=NO`；托管方仍可收到正常 HTTP 请求信息，不能宣称零网络元数据。[S6]

## 新功能计划

| 阶段 | 交付功能 | 完成标准 |
| --- | --- | --- |
| P0：接入验证 | 锁定 Sparkle 2.10.0；验证两代测试 App 的框架加载、签名、固定文件名、版本比较与完整包更新 | 在独立测试 feed 下从 A 升到 B 并重启，保留设置及历史；明确是否具备正式签名条件 |
| P1：首个集成版 | 手动检查；用户同意后的每日自动检查；标准更新说明、下载进度、取消、稍后提醒及确认安装；自动安装默认禁止；GitHub 手动下载入口；任务安全退出 | 完成以下验收矩阵后发布，旧版用户手动安装一次进入新链路 |
| P2：更新体验 | 用户可选自动下载/退出时安装、温和提醒；进一步适配应用内中英文偏好；改进可操作错误和诊断 | 所有后台和退出安装路径通过任务协调与数据保存验证 |
| P3：发布运营 | beta 通道、分阶段推送、必要时增量包和密钥轮换演练 | 测试通道可回归更高构建号稳定版；灰度、签名和恢复演练记录完整 |

P1 建议不设置 `SUEnableAutomaticChecks`，采用 Sparkle 第二次启动询问的默认机制；检查周期为每天。设置 `SUAllowsAutomaticUpdates=NO`，确保首版不能被标准窗口的偏好选项切到自动安装。保持系统画像关闭。[S4][S6]

Sparkle 自动下载偏好可能连带退出时安装，P2 不能把它误标成单纯的“仅预下载”。[S6]

Capricorn 使用自己的 `AppLanguage` 切换文案，不能假定 Sparkle 标准窗口会立即跟随。P1 验证系统语言下的中文和英文及应用偏好不一致时的表现；如热切换需要额外适配，明确记录并安排 P2，不在首版承诺未经验证的一致性。

## 首版验收矩阵

| 验收项 | 必须提供的证据 |
| --- | --- |
| 版本比较 | 相同构建无更新；同营销版本新构建可更新；跨小版本不漏报；旧构建拒绝降级；侧栏和设置不拼入内部构建号 |
| 升级全链路 | 两个实际归档构建，从下载、校验到替换和重启；在可获得的 Apple silicon、Intel 及最低支持系统上验证 |
| 安全失败 | 损坏 ZIP、错误签名、错误公钥、错误 feed 签名均不能被当作成功更新；原 App 和数据仍可用 |
| 网络与权限 | 离线、超时、404、拒绝授权、取消下载、只读路径和下载隔离场景均有可恢复结果 |
| 安装竞态 | 测速、急救、自检、停止清理、保存中均不被强制重启；安装许可检查后不能插入新任务 |
| 数据保持 | 已有 SMART、测速、自检和活动历史及偏好保留；保存失败能阻止继续；schema 迁移用真实旧数据副本验证 |
| 用户选择 | 自动检查拒绝后不偷偷检查；稍后提醒有效；后台失败不打断磁盘工作，主动检查错误可见 |
| CI 与隔离 | 测试、严格并发、Swift 6、universal Archive 通过；测试/演示不启动正式更新器；dSYM 留存 |
| 发布一致性 | appcast 版本、包长、签名、下载地址和实际 bundle 一致；GitHub 附件先可用，feed 后发布 |

单元测试覆盖应用自己的版本显示、任务许可、偏好与代理衔接；Sparkle 的安装器和密码学不重复实现，使用集成测试验证。没有实际 Intel 或最低系统测试环境时，应明确写出覆盖缺口。

## 迁移与投入

现有 `v2.10.1` 及更早客户端不含 Sparkle 和公钥，无法仅通过服务器配置获得应用内安装能力。它们仍可用当前 GitHub 检查器发现首个集成版，用户需要手动下载并安装一次；该版本开始的后续更新进入 Sparkle 链路。

首次迁移在说明中引导将 App 放到本地可用位置并使用固定名称 `Capricorn.app`。兼容用户已自行改名、应用位于桌面或其他目录、多副本并存及签名身份变化的行为，要通过真实迁移验证，不能假定能透明合并旧副本或保留全部系统授权。

预计投入属于工程估算，不是已验证工期：

- P0 约 1–2 个开发日。
- P1 与发布流程约 3–5 个开发日，包含任务协调和真实升级验证。
- P2/P3 按实际需求再拆分，首版不绑定交付日期。

证书取得、静态托管配置和 Intel/旧系统测试环境准备时间另计。实施前需要落实：稳定 feed 地址、分发签名路径、私钥保管与备份责任人。建议下一步先做 P0，验证成功后再安排首个正式集成版。

## 官方来源

以下资料于 2026-10-17 在线读取。API 与源码固定到 Sparkle 2.10.0，官网文档可能继续更新。

- [S1：Sparkle 最新正式 Release API](https://api.github.com/repos/sparkle-project/Sparkle/releases/latest)；[2.10.0 发布说明](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0)
- [S2：2.10.0 Package.swift](https://github.com/sparkle-project/Sparkle/blob/2.10.0/Package.swift)
- [S3：SwiftUI 和程序化接入、API 使用约束](https://sparkle-project.org/documentation/programmatic-setup/)
- [S4：基本接入、签名、发布及密钥轮换](https://sparkle-project.org/documentation/)
- [S5：更新设置界面及持久化约束](https://sparkle-project.org/documentation/preferences-ui/)
- [S6：默认配置、安全选项及自动更新语义](https://sparkle-project.org/documentation/customization/)
- [S7：2.10.0 更新代理定义与限制](https://github.com/sparkle-project/Sparkle/blob/2.10.0/Sparkle/SPUUpdaterDelegate.h)
- [S8：2.10.0 更新校验与签名策略源码](https://github.com/sparkle-project/Sparkle/blob/2.10.0/Sparkle/SUUpdateValidator.m)
- [S9：Capricorn 最新正式 Release API](https://api.github.com/repos/LexTheAries2209/Capricorn/releases/latest)
- [S10：Appcast、内部版本、通道与灰度发布](https://sparkle-project.org/documentation/publishing/)
- [S11：Sparkle 2.10.0 完整许可及附带组件声明](https://github.com/sparkle-project/Sparkle/blob/2.10.0/LICENSE)

实际集成时，在 `THIRD_PARTY_NOTICES.md` 及随包资源中纳入 Sparkle 的完整许可和附带组件声明，并核对分发所用版本的实际依赖。[S11]
