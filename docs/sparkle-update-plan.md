# Capricorn 自动更新：Sparkle 适配研究与功能计划

调研日期：2026-10-17，Asia/Shanghai。状态：提案，尚未实现。

## 结论

建议采用 Sparkle 2 承担 Capricorn 的应用内更新流程，保留 GitHub Releases 作为安装包分发和人工下载入口。现有 GitHub API 检查器可作为旧版迁移入口；新客户端由 Sparkle 统一管理更新检查，避免两个调度器重复工作。

技术适配度高，主要工作集中在版本规则、发布包结构、签名和安装前的任务协调，并非替换一个网络请求就完成。建议第一阶段交付“自动检查 + 用户确认下载和安装 + 安全重启”，之后再评估自动下载、退出时安装、测试版通道和灰度更新。

截至调研时，Sparkle 最新正式版为 **2.10.0**，发布于 2026-09-13；其 Swift Package 清单最低要求 macOS 12，低于 Capricorn 的 macOS 14 最低要求。[S1][S2]

本轮检查了源码、工程配置、CI、当前发布说明、GitHub Release 元数据及桌面的 `Capricorn V2.10.1.app`。没有集成框架、生成密钥、构建更新包、修改线上资源或进行真实升级测试。

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
- Sparkle 的偏好直接绑定其已有持久化属性，不在 `AppPreferences` 再维护一份冲突的开关。[S3][S5]

### 2. 版本和应用身份

建议在首次集成版统一版本字段：

| 字段 | 建议示例 | 用途 |
| --- | --- | --- |
| `CFBundleShortVersionString` | `2.11.0` | 完整用户可见版本 |
| `CFBundleVersion` | `1000`，之后 `1001`、`1002` | 全局递增构建号，不随小版本归零 |
| `sparkle:shortVersionString` | `2.11.0` | appcast 的展示版本 |
| `sparkle:version` | `1000` | 与安装包实际构建号一致 |
| App 文件名 | `Capricorn.app` | 后续每个更新包保持一致 |
| Bundle ID | `lex.Capricorn` | 保持现有偏好与应用身份 |
| `SUBundleName` | `Capricorn` | 避免更新提示重复拼接版本 |

以上版本和构建号仅作示例，不预定下一次发布版本。起始构建号实施时要核对历史和测试通道；同一 appcast 下所有可升级构建均递增，稳定版也必须能够超过先前测试版的构建号。[S4][S10]

必须同步修改 `AppVersion.current` 及其测试：不能继续把新构建号拼成 `2.11.0.1000`。设置页和侧栏统一显示营销版本；构建号可独立展示。不要依赖自定义版本比较器来补救现有字段规则：Sparkle 2.10.0 已将相关代理 API 标为弃用，安装阶段还可能使用标准比较器。[S7]

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
