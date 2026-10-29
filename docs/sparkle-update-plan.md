# Capricorn 自动更新：Sparkle 适配研究与功能计划

## V2.12.0 / Build 0048：发布候选

2026-10-29 准备共享硬盘连接拓扑版本，继续使用固定 `Capricorn.app`、既有公钥和稳定 feed，不改变更新下载与安装策略。

最终全量 601 项测试通过，无失败或跳过；严格并发、Swift 6、Universal Archive、双架构 dSYM UUID、完整 bundle 签名和归档 App 启动通过。首轮系统截屏命令失败经单项和最终全量复测通过。19 个真实 Sparkle 隔离场景通过，手动与自动安装保留测试历史及偏好；下载中冲突场景使用两秒延迟确保冲突注入。安装测试没有替换真实用户 App 或数据库。

候选签名源已由真实 Sparkle 核验：`0047` 发现 `2.12.0 / 0048`，`0048` 无更新。最终 ZIP 为 12,290,365 字节，SHA-256 为 `d9270836dac1634e2c38e2709cc94386cd13f1c4128f3f70b75adf44e39ee9f0`；更新包和清单使用既有 Ed25519 密钥签名并复验。App 继续使用有效 ad-hoc bundle 签名，没有 Developer ID 或 Apple 公证。

存档源码已通过独立 Universal Release 构建，完整 xcarchive/dSYM 和版本备份保留；无额外桌面副本。

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
