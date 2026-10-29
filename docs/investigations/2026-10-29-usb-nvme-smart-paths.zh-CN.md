# macOS USB-NVMe SMART：三条实现路线与依赖边界

研究日期：2026-10-29，Asia/Shanghai。

范围：用户态独占读取、DriverKit、内核扩展（KEXT）。本文是技术调查和实验建议，不是实现完成记录。

证据标记：

- **已核实**：本轮阅读了 Apple 文档、本机 SDK 头文件或指定版本的源码。
- **上游报告**：公开项目的作者或测试者报告，不代表我们已经复现。
- **工程判断**：根据接口和源码推导，仍需实验。
- **待验证**：现有公开证据不足，不能承诺。

本轮没有接管设备、卸载卷、加载驱动、改变系统安全设置或修改应用代码。

## 结论

1. 对已有透传协议的 JMicron、Realtek、ASMedia 桥接设备，开发基本 SMART 读取不必先获得芯片厂商配合。smartmontools 已有协议实现；我们要补的是 macOS 访问通道、授权、设备生命周期和兼容性验证。[S1][S2]
2. 用户态 DeviceCapture 能实现按需读取，但会终止整台 USB 设备的现有驱动。它不能用于维持挂载和正常文件 I/O 的透明后台监控。[S3]
3. DriverKit 有更接近 SAT 架构的 SCSIPeripheralsDriverKit，不应只看面向控制器的 SCSIControllerDriverKit。但其公开厂商命令接口也有独占和卸载限制。[S4][S5][S6]
4. 自己接管全部 USB 存储，再向系统提供磁盘，绕开了与 Apple USB 存储驱动争用的问题，却引入完整存储驱动和请求缓冲区访问问题。目前不能把这条路线当成确定可交付的高速方案。[S7][S8][S9]
5. 类似 SAT 的 KEXT 在架构上最接近“保留系统 USB 传输，在 SCSI 外设层加入 SMART”。但 Apple DTS 已提示 KEXT 证书计划基本关闭；若无已有签名资格或可承担发行责任的合作方，不应把它当作默认可发行的透明监控路线。[S9][S10][S11]
6. 真正无法由上位机软件补足的是：设备端确实没有相关入口、需要我们无法签名的固件才能增加入口、设备要求未知认证密钥，或 SSD 本身根本不报告所需信息。未知协议则属于调查成本，不等于绝对不可能。

## 共用的技术问题

### 把三个层次分开

```text
NVMe 数据语义：Identify、SMART/Health Log 等
        |
桥接封装：JMicron / ASMedia / Realtek SNT
        |
macOS 访问通道：谁拥有设备、谁发送 CDB、谁管理传输与恢复
```

SNT 是 SCSI-NVMe Translation。现有 USB 桥接器使用不同封装，不是给所有 USB-NVMe 设备安装一个统一驱动即可解决。[S2]

| 桥接路径 | 所查源码的外层 CDB | 已有实现的重要边界 |
| --- | --- | --- |
| JMicron | `0xA1`，12 字节，多个阶段 | 先发送 NVMe 命令封套，再执行数据阶段，最后取得完成信息 |
| ASMedia | `0xE6`，16 字节 | 现有适配器主要处理 Identify / Get Log Page，部分请求字段受限 |
| Realtek | `0xE4`，16 字节 | 现有适配器主要处理 Identify / Get Log Page，保守限制 Get Log Page 为 512 字节 |

表中限制是所查适配器的行为，不是所有芯片和固件的不可改变硬件上限。[S2]

**上游报告**：2026-09-20，有测试者对特定 RTL9210B 硬盘盒移除软件限制后，读取到超过 512 字节的日志，并做了前一条命令数据污染检查。这只能说明该具体设备值得放宽验证，不能推广到整个 RTL9210 系列。[S12]

### “只读”不等于只允许 USB Data-In

JMicron 读取健康信息时也需要向设备发送命令封套。禁止一切 Data-Out 会把正常读取一并禁止。应审核封套中的 NVMe 操作码、日志号、长度和字段，而不是只看 USB 方向。[S2][S13]

同理，读取健康信息、读取自检历史、启动自检、更新固件是不同能力。当前适配器没有实现某个命令，不能直接推导为桥接固件永远不可能支持该命令。

## 路线一：用户态临时独占读取

### 具体技术路径

**已核实 / 上游报告**：smartmontools PR #639 是可复用起点。截至本轮查询仍为 open、Draft、未合并。检查的提交为 `c68a1b9af76ba9ca3a2e987def6384377f73a4b8`。[S1]

建议原型采用：

1. 通过 I/O Registry 被动识别物理 USB 设备、桥接类型、BOT/UASP、存储接口和卷。
2. 由用户主动触发读取；使用 Disk Arbitration 非强制卸载相关卷，无法卸载就停止。
3. 在授权的独立读取进程内使用 `IOUSBHostDevice` 和 DeviceCapture。
4. 复用 smartmontools SNT，底层用 `IOUSBHostPipe` / `IOUSBHostStream` 实现 BOT 或 UASP。
5. 初版仅支持固定设备名单及 Identify / SMART Health。
6. 释放设备，等待系统驱动重新匹配，按稳定身份确认原设备和卷恢复。

PR 已实现主要传输与生命周期逻辑，但不能因为代码存在就接受其全部默认行为。[S13]

### 我们可以独立完成什么

- 编译、审查和裁剪现有 PoC；沿用 smartmontools 的数据解析与 JSON 输出。
- 开发本机管理员授权、进程间通信、超时和取消管理。
- 做设备白名单、固件兼容记录、失败诊断、结果缓存和 Capricorn Provider。
- 改进卷恢复、设备身份和失败后的用户操作提示。
- 为已知桥接器修复传输问题，无须重新开发 SSD 的 SMART 协议。

以上是建议工程范围，不是已完成实现。

### 硬边界

**已核实**：DeviceCapture 会终止整个 USB 设备及其接口上的客户端和驱动；销毁对象时设备会复位并重新进行 IOKit 匹配。这是接口定义，不是增加线程、管理员权限或提高轮询间隔就能避免的行为。[S3]

因此不能承诺：

- 卷保持挂载，同时后台读取。
- 接管前后的文件句柄、BSD 设备号和运行中的文件操作连续不变。
- 只影响一块盘，而不影响同一 USB 设备上的其他接口或逻辑单元。

初版应限制为单存储接口、单整盘、已核实 LUN 的设备；不能把“USB Hub 下其他独立设备”与“同一复合 USB 设备的其他功能”混为一谈。

### 最难的工程问题

- APFS 物理盘、容器、合成磁盘和多个卷之间的关系。
- 复位后 I/O Registry ID 与 `/dev/diskN` 可能变化，不能仅按旧节点重试。
- 异步 USB I/O 超时后，确认传输真正结束，才能释放缓冲区。
- UASP 的状态 IU、数据 IU、tag、streams 和错误恢复；低频 SMART 不必一开始实现高队列深度。
- 应用或读取进程异常退出后的恢复，不能只依赖正常流程里的清理代码。
- TCC、应用责任链和实际授权环境需要单独测试；root 不是所有 macOS 隐私权限的同义词。

**上游报告**：2026-10-02，JMicron 路径成功返回健康数据后，仍报告卷没有重新出现。因此“SMART 读取成功”和“操作完整成功”必须分别验收。[S14]

### 权限与厂商依赖

Apple 对 DeviceCapture 允许两类授权：root；或者 `com.apple.vm.device-access` 加对应 `IOServiceAuthorize` 授权。所查 PoC 直接要求 root。不能把 VM entitlement 当成普通工具一定能取得的权限。[S3][S13]

研究建议采用受限管理员读取进程，不让主 GUI 长期以 root 运行。是否需要常驻 helper 另行选型，单次原型不必先决定。

现有协议、固件已能响应时，不要求厂商提供签名或 NDA 文档。若协议未知，厂商资料可以显著降低成本；若固件根本不支持目标命令，则此路线无能为力。

**判断**：最适合先做原型和按需诊断功能，不适合实时监控。

## 路线二：DriverKit

### 二 A：SCSIPeripheralsDriverKit，优先研究的窄路径

**已核实**：该框架工作在 SCSI 逻辑单元层。Type00 对应磁盘和 SSD，provider 为 `IOSCSIPeripheralDeviceNub`，可通过 `UserSendCDB` 向匹配设备发送命令。[S4][S5]

候选结构：

```text
Capricorn
    -> 受限 IOUserClient
    -> 自定义 IOUserSCSIPeripheralDeviceType00
    -> Apple 原有 SCSI / USB 存储传输
    -> USB-NVMe 桥接器
```

这条路线的优点是不用重新实现 BOT/UASP 传输。我们仍须验证匹配优先级、正常磁盘枚举、与已装 SAT/厂商驱动的关系，以及应用端通信。

但公开接口有关键限制：

- `UserSendCDB` 对 `0xC0–0xFF` 厂商命令要求独占。
- `UserSuspendServices` 要求先卸载上层卷。
- 完成后调用 `UserResumeServices` 恢复服务。
- CDB 接口为 16 字节，sense 格式和缓冲区长度也有具体要求。[S5][S6]

**直接推导**：Realtek 的 `0xE4`、ASMedia 的 `0xE6` 落在这个范围，按公开 API 契约不能直接实现挂载中的后台读取。

**待验证**：JMicron 的外层 `0xA1` 不在上述数值区间，但有 12 字节 CDB、多阶段封套、Data-Out、sense 和并发语义问题。仅凭操作码不能承诺可以在挂载状态运行。尤其不能把接口未明说的情况当成稳定兼容能力。

原型必须分开验证：

1. Type00 DEXT 能否只匹配指定硬盘盒并保持正常磁盘工作。
2. 卸载后发送 Identify / Health 是否成功，能否恢复。
3. JMicron 外层 CDB 是否被接口正确解释；失败发生在系统检查还是设备返回状态。
4. 即便允许发送，普通磁盘 I/O 与完整 SNT 事务并发是否安全。

**判断**：作为无需接管整台 USB 设备的按需读取路径值得验证；对透明后台监控，Realtek / ASMedia 的公开接口限制已经明确。

### 二 B：自己拥有 USB 存储接口，并向系统提供磁盘

USBDriverKit 的 `IOUSBHostInterface::Open` 同一时间只允许一个服务打开接口。不能让 Apple USB 存储驱动和我们的驱动各自向同一组存储端点发请求。[S15]

要解决争用，就必须由我们作为唯一所有者，统一处理系统读写与 SMART，并向上提供块设备。这已经是存储驱动项目：

- BOT/UASP、请求调度、并发、取消与复位。
- READ/WRITE、缓存同步、写入顺序、FUA、容量和扇区大小。
- 睡眠唤醒、热拔插、电源管理。
- 可选的 UNMAP、设备能力声明、性能和数据完整性。

更重要的是，不能假定“找到 BlockStorage 框架，普通 USB I/O 就能接上”：

- **已核实**：`IOUserBlockStorageDevice::DoAsyncReadWrite` 只提供 `dmaAddr`，不是可直接用于 USB 传输的 `IOMemoryDescriptor`。[S7][S8]
- **Apple DTS 说明**：公开接口缺少对应的描述符访问路径；SCSIControllerDriverKit 的 `UserGetDataBuffer` 提供另一条路径，但讨论中仍涉及无 DART 时的分段/单页配置及每请求开销。[S9]
- 同一讨论后来有软件存储读写报告及本地缓解措施。不能沿用 2025 年旧答复，把 SCSIController 路线简单判为绝对不可能。测试者也修正过受缓存影响的吞吐量判断，因此不能把网络场景的某个读写数字当成 USB 路径、10/20 Gb/s 性能或全部现代系统的证明。
- 该讨论记录过描述符代理生命周期、端口配额、单页请求开销，以及部分问题的本地缓解。它是证明“值得做小型原型”的证据，不是直接可用的 USB-NVMe 驱动，也不能据此断言后续系统永远无法修复。

**工程判断**：SCSIController + 用户态 USB transport 是可做研究原型的候选；BlockStorage + USB 目前有明确的缓冲区访问缺口。必须先解决请求内存传递并测出真实读写性能，才能估算产品工期。

这类限制的责任方是 Apple 平台接口，不是桥接器厂商。芯片厂商提供 SNT 文档不能补出缺少的 DriverKit API。

### DriverKit 签名与权限，不应一概说“等 Apple 审批才能开始”

**已核实**：Apple DTS 的较新签名说明指出，付费开发者账号可使用 development entitlement；Xcode 16 及以上支持相应自动签名，不应默认要求关闭 SIP 才能开发。该说明后来补充了 Xcode 27 的 DEXT 模板及 USB / PCI 签名支持；USB / PCI 的发行范围和团队权限仍须核实，不能把旧教程中手工申请、手工签名的步骤当成所有版本的固定要求。[S16]

Type00 框架列出的基本 family 是 `com.apple.developer.driverkit.family.scsicontroller`；它的 provider 是 SCSI nub。不能因为物理设备接在 USB 上，就自动断言它必须采用 USBDriverKit 的 VID 授权方案。[S4]

建议：

- 窄路径先用实际最小 target 验证 family、profile 和激活，不添加用不到的 transport entitlement。
- 若直接打开 USB provider，再处理 USB transport entitlement、目标设备匹配范围和发行配置。
- 开发 wildcard 不等于允许 wildcard 分发。
- 发行所需 profile、签名、安装应用、用户批准和公证独立验收。

本轮没有登录开发者账号验证当前团队的能力，也没有为 Capricorn 申请权限。

## 路线三：类似 SAT 的 KEXT

### 具体技术路径

**已核实**：开源 SAT 驱动的 `IOSATDriver` 继承 `IOSCSIPeripheralDeviceType00`，匹配 `IOSCSIPeripheralDeviceNub`，通过 SCSI task 发送附加命令，同时提供用户客户端。这说明不必为了 SMART 从 USB 电气层重写传输驱动。[S10][S11]

候选结构：

```text
Capricorn / 专用读取工具
    -> 自定义只读 IOUserClient
    -> 自定义 Type00 KEXT
    -> Apple SCSI task / 原有 USB 存储传输
    -> 桥接器 SNT
```

实现上应先复用已有 SNT 语义，内核端只暴露严格限制的健康信息操作或受限传输。不能直接把 NVMe 健康数据伪装成 ATA SMART 属性。

如果目标是 Capricorn 自用，可以设计专用接口；若希望原版 smartctl、DriveDx 等也自动兼容，还需要额外的用户态适配和客户端契约。安装 KEXT 本身不等于这些应用自然认识它。

### 我们可以独立完成什么

- 指定 VID/PID、设备类型和实际桥接身份的匹配。
- Type00 派生类、SNT CDB、缓冲区、超时与结果解析。
- 自定义用户客户端，以及 Capricorn 或 smartctl 后端适配。
- 限制为基本健康读取的原型。
- 已知桥接协议的兼容性修复和回归测试。

这属于可自行开发的工程范围；当前没有可加载原型，不代表现代 macOS 上已经验证可行。

### 真正困难的边界

1. **现代系统可加载性**：所查历史源码最后一次提交在 2016 年。不能把它作为当前 macOS、Apple silicon 和所需 KPI 的兼容证明。先验证最小驱动能匹配、加载并保持正常磁盘服务。
2. **共享 I/O 的正确性**：内核能够提交 CDB，不等于桥接固件允许它与普通读写任意交错。特别是 JMicron 的多阶段事务，要验证完整事务的串行化和异常恢复。
3. **内核生命周期**：拔插、并发回调、取消和睡眠期间的锁与内存错误可能影响整个系统，测试范围远大于用户态工具。
4. **发行条件**：自行修改的二进制不能沿用第三方签名。2026 年 8 月的 Apple DTS 回复明确提示，KEXT 证书计划基本关闭；本地降低保护以测试，不代表取得可分发的签名资格。有现成资格的团队愿意承担发行责任，与“借用其证书”也不是一回事。Apple silicon 加载第三方 KEXT 涉及 Reduced Security、用户批准和重启。[S9][S17][S18]
5. **持续维护**：系统更新、KPI 政策和其他存储驱动冲突都要持续验证，不能以当前 SAT 已能加载来承诺新的 SNT 驱动必然可加载。

**工程判断**：如果透明监控是刚性目标，这条路线在架构上比“共享 USB 端点”更合理；但必须先确认可用的签名与发行路径，再验收现代系统加载和并发读写。没有前者时，它更适合作为研究原型，不能按普通应用功能排期。

厂商文档有助于确认事务原子性、复位和固件行为，但无法替代 Apple 的签名与系统政策。

## 哪些需要厂商，哪些不需要

| 情况 | 我们可做的事 | 外部依赖与结论 |
| --- | --- | --- |
| 已知 SNT、固件能响应 | 移植、构建、授权、读取、解析和集成 | 基本读取可独立开发 |
| 协议未知，但存在可用厂商工具 | 获取合法测试日志，分析命令并做只读验证 | 厂商资料可省时间，不能说没有资料绝对做不了 |
| 某命令被软件白名单或保守长度限制拦住 | 定位拦截层，固定设备版本后实验 | 不应误判成硬件无能力；Realtek 512 字节案例是例子 |
| 不确定固件是否有相关入口 | 跨平台对照、命令状态分析、询问厂商 | 当前是未知，不应当作已证实不能支持 |
| 固件确实没有健康查询/透传入口 | 换桥接器、换连接方式、提出固件需求 | 增加驱动不能创造设备端入口 |
| 必须修改受签名保护的固件才能增加入口 | 完成主机侧代码及接口设计 | 无合法签名路径时需要有权限的厂商或平台方 |
| 入口要求未知认证密钥 | 识别认证边界、接入合法授权机制 | 无密钥或授权机制时不能完成正常支持 |
| 已知桥接固件缺陷 | 能做的先限长、分块、降并发和重试 | 无可行规避时需固件修复或换硬件；并非所有缺陷都能主机侧修复 |
| DriverKit 拒绝厂商 CDB 并发 | 按公开契约卸载后操作，或更换架构 | Apple API 边界，不是让桥接厂商提供资料就能解除 |
| DEXT/KEXT 无发行权限 | 本地研究、完善最小复现和签名配置 | Apple/开发者账号问题；新 KEXT 资格尤其不能假定能取得，与 SSD 厂商配合分开处理 |
| 要求所有 USB-NVMe 零配置全兼容 | 建立有条件的支持矩阵 | 三条路线都不能作这种承诺 |

## 如果争取厂商合作，具体索取什么

优先联系硬盘盒品牌的技术团队，再追到桥接方案商；零售品牌不一定有芯片固件修改能力。

索取以下可验收内容：

1. 芯片和硬件修订、实际固件版本、VID/PID 与版本对应关系。
2. SNT 命令格式、方向、长度、日志偏移、NSID 和完成状态的定义。
3. Identify、Health Log、自检日志、自检启动分别是否支持。
4. BOT / UASP 两种模式的支持差别，以及与普通读写并发的规则。
5. 复位、掉电、休眠和超时后的恢复要求。
6. 若需升级，取得可合法分发的签名固件和升级路径；不只是一个未知来源的刷写工具。

**合作设计建议，尚未实现**：如果目标是长期后台监控，最有价值的厂商改动可能是增加独立的管理接口，例如专用 USB 接口或 HID 健康报告，让存储传输和健康查询有清晰的独立通道。是否可行取决于其 USB 控制器、固件空间和并发实现。这不能由 Capricorn 单方面给现有设备添加。

## 对 Capricorn 的影响

本轮检查当前源码：

- `SmartServices.swift` 中内置 smartctl 元数据仍为 7.5。
- `commandArguments` 已把已解析的设备类型作为 `-d` 参数传给 smartctl。
- `resolvedTargetDescriptors` 根据设置使用 `--scan` 或 `--scan-open`。
- `SmartctlCommandCoordinator` 仅串行化本应用内的 smartctl 操作，无法阻止文件系统或其他进程向磁盘发送 I/O。
- `scripts/build-smartctl.sh` 固定构建 7.5 源码包；PR 使用的源码和构建结构不能当作现有二进制的原位替换。

**工程判断**：实验版 raw USB 工具应与现有自动刷新路径隔离。尤其不能直接替换当前 smartctl：在 PR 中，`--scan-open` 本身可能进入卸载、接管和恢复流程。[S1]

建议独立工具和显式按需动作，结果再映射到 `SmartSnapshot`。捕获期间必须协调 Capricorn 自身的测速、负载、刷新和拓扑状态；应用内部协调仍不代替系统独占。

## 推荐验证顺序与停止条件

以下是未来实验计划，本轮未执行。

| 阶段 | 实验 | 通过标准 | 失败后的决策 |
| --- | --- | --- | --- |
| 0 | 固定一款桥接器、固件和 SSD，在可用平台做基线 | 确认同一设备的型号、日志和健康数据可读 | 失败只能记为待定位，不能立即断言硬件不支持 |
| 1 | 独立 raw USB 工具读取 Identify + Health | 返回有效结构、实际传输长度和完成状态正确 | 先定位权限/传输/封装，不接入 App |
| 2 | 释放、重新枚举、恢复卷及错误注入 | 读数和恢复分别可核实；超时、拔插、取消不错误操作其他设备 | 任何设备身份混淆或无法恢复都阻止产品化 |
| 3 | Type00 DEXT 最小原型 | 指定匹配、有效签名、正常存储服务和卸载后 CDB 成功 | 无收益或权限成本过高则保留路线一 |
| 4 | 如需要，单独验证 JMicron 挂载共存 | 接口允许且长时间普通 I/O 与完整事务并发通过 | 不将 `0xA1` 视为通用绕行方案 |
| 5 | 如实时监控仍为刚需，先查 KEXT 签名资格，再验证驱动 | 有可用发行资格，现代测试系统可加载，读写和监控共存，不需侵入 USB 端点 | 资格/加载/并发任一关键门槛失败就停止产品路线 |
| 6 | 仅当其他路线均不满足时研究完整 DEXT 存储栈 | 先解决描述符访问，再证明真实持续读写与错误恢复 | 平台接口缺口未解决前不投入完整产品 |

建议首次支持矩阵只声明已测试的硬盘盒和固件。后续再扩展架构、macOS 版本、BOT/UASP、APFS/加密卷、休眠和热拔插组合。读取 100 次不是数据安全证明；测试数据量和循环数应按原型表现制定，不能在未测量时承诺稳定性。

难度判断：路线一最适合近期投入；窄 Type00 DEXT 是有价值的对照实验；KEXT 必须先查签名资格，不能把能在自己机器上加载等同于能发行；完整 USB 存储 DEXT 的平台与性能风险最高。此时不宜给后三者承诺固定交付日期。

## 证据与复查入口

本机检查：DriverKit SDK `25.5`。读取了 `SCSIPeripheralsDriverKit.framework` 的 `IOUserSCSIPeripheralDeviceType00.iig`、`IOUserSCSIPeripheralDeviceHelper.h`，以及 `BlockStorageDeviceDriverKit.framework` 的 `IOUserBlockStorageDevice.iig`。SDK 头文件用于交叉检查，不是运行验证，也不是已经检查全部后续 SDK 或系统修复的声明；原型需针对实际目标 SDK 和 macOS 重新验证。

历史 SAT 源码检查提交：`437c58893d13e38f41b256d44b0f8685530ee3ce`，提交日期 2016-12-01。只作为架构证据，不代表 Binary Fruit 当前签名版本与其逐字一致。

- [S1: smartmontools PR #639，状态、接口与调用行为](https://github.com/smartmontools/smartmontools/pull/639)
- [S2: 所查固定提交的 SNT 实现 scsinvme.cpp](https://github.com/PeratX/smartmontools/blob/c68a1b9af76ba9ca3a2e987def6384377f73a4b8/lib/scsinvme.cpp)
- [S3: Apple IOUSBHost DeviceCapture](https://developer.apple.com/documentation/iousbhost/iousbhostobjectinitoptions/devicecapture)
- [S4: Apple SCSIPeripheralsDriverKit](https://developer.apple.com/documentation/scsiperipheralsdriverkit)
- [S5: Apple Type00 UserSendCDB](https://developer.apple.com/documentation/scsiperipheralsdriverkit/iouserscsiperipheraldevicetype00/usersendcdb)
- [S6: Apple Type00 UserSuspendServices](https://developer.apple.com/documentation/scsiperipheralsdriverkit/iouserscsiperipheraldevicetype00/usersuspendservices)
- [S7: Apple BlockStorageDeviceDriverKit](https://developer.apple.com/documentation/blockstoragedevicedriverkit)
- [S8: Apple DoAsyncReadWrite](https://developer.apple.com/documentation/blockstoragedevicedriverkit/iouserblockstoragedevice/doasyncreadwrite)
- [S9: Apple DTS 对 BlockStorage / SCSIController 缓冲区和软件存储路径的讨论，含后续修正](https://developer.apple.com/forums/thread/837879)
- [S10: SAT 驱动 Type00 派生类](https://github.com/kasbert/OS-X-SAT-SMART-Driver/blob/437c58893d13e38f41b256d44b0f8685530ee3ce/SATSMARTDriver/IOSATDriver.h)
- [S11: SAT 驱动匹配配置](https://github.com/kasbert/OS-X-SAT-SMART-Driver/blob/437c58893d13e38f41b256d44b0f8685530ee3ce/SATSMARTDriver/Info.plist)
- [S12: RTL9210B 超过 512 字节日志读取报告，2026-09-20](https://github.com/smartmontools/smartmontools/pull/639#issuecomment-5751517451)
- [S13: 固定提交的 macOS raw USB 传输、白名单与恢复实现](https://github.com/PeratX/smartmontools/blob/c68a1b9af76ba9ca3a2e987def6384377f73a4b8/lib/os_darwin_usb.mm)
- [S14: JMicron 成功读取但卷恢复失败的报告，2026-10-02](https://github.com/smartmontools/smartmontools/pull/639#issuecomment-5949941297)
- [S15: Apple USBDriverKit IOUSBHostInterface Open](https://developer.apple.com/documentation/usbdriverkit/iousbhostinterface/open)
- [S16: Apple DTS How to sign a DEXT，较新签名流程与 development/distribution 区别](https://developer.apple.com/forums/thread/809202)
- [S17: Apple Kernel extensions in macOS](https://support.apple.com/guide/security/sec8e454101b/web)
- [S18: Apple Installing a custom kernel extension](https://developer.apple.com/documentation/apple-silicon/installing-a-custom-kernel-extension)

Apple 页面提供的 Markdown 版本也已读取；若 HTML 只显示 JavaScript 提示，可在相同文档路径末尾添加 `.md` 复查。上游测试结果、接口说明和工程建议在正文中分别标注，不能互相替代。
