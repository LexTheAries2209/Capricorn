# 真实测速线程、五类配置及 Q/T 联动验收报告

日期：2026-10-19，Asia/Shanghai。
分支：`codex/benchmark-real-threads-profiles`。

## 1. 结果

- 异步测速的 T 已改为真正创建的独立工作线程，不再仅参与 Q × T 的乘算。
- 测速配置改为默认、快速、SSD、HDD、自定义；自定义直接可选，不再需要开发者设置开关。
- 所有生成的配置均限制 Q × T ≤ 16。自定义 Q、T 从 1、2、4、8、16 中选择，T 的可选值随 Q 调整。
- 快速模式只有顺序 1 MiB Q1T1、随机 4 KiB Q1T1 两个项目组，默认分别执行读取、写入，共四个结果单元。
- 最终定向回归：56 项，54 项通过、2 项因屏幕录制权限不足跳过、0 项失败。
- E 盘独立目录验证：五种总目标为 16 的组合 × 缓存/非缓存写入，共 10 组全部通过；实际线程数符合 T，总在途峰值均为 16，fsync 后重新打开文件完整回读非零数据一致，结束后共享额度占用为 0。
- 应用的 Swift 6 严格并发构建通过；独立验收程序也以 Swift 6、完整严格并发检查、编译警告视为错误编译通过。

以上不表示已进行全项目测试、全盘扫描、断电持久性测试，或验证过所有 SSD/HDD 型号的最优性能。

## 2. 原因与实现

此前异步测速把 `queueDepth * threads` 传给单个 AIO 调度循环，因此 Q16T1 与 Q4T4 都只是同一个循环的总目标 16，T 没有对应独立的工作线程。

新增 `AIOBenchmarkTransfer`，每轮传输创建 T 个命名工作线程，并通过起跑屏障让线程都准备好后开始工作。每个线程：

1. 使用独立的复制文件描述符，持有自己的 AIO 请求与缓冲区。
2. 将文件划分为按块对齐、彼此不重叠的连续区间；顺序访问推进自己的区间，随机访问在自己的区间内选择位置，尾部不足整块的部分也计入总量。
3. 将 Q 作为自己的目标在途深度，所有线程通过既有 `AIOBudget` 共享进程额度。
4. 完成或失败时先回收已经提交的请求，再关闭描述符；主调用等待所有线程退出后才返回、刷盘或释放上层文件。

线程首个错误会保留并通知其他线程停止继续提交；既有 EAGAIN/ENOMEM/ENOBUFS 重试及取消后的安全回收仍由生产 `AIOTransfer` 执行。异步字节进度回调已串行发布，避免多个线程的回调先后颠倒。

同步测速也改为创建真实工作线程，替代依赖并行迭代调度的实现。不过同步引擎仍使用阻塞 I/O：每线程实际最多一个请求在途，原 Q 参数为串行批次，不应与异步 Q 等价比较。本次五种配置均默认异步；用户已有的同步引擎偏好仍予保留。

为防止新旧线程模型的测速结果混在一起，配置和测试结果标识新增 `workers-v2`。历史结果继续保留。

## 3. 配置选择

每个普通项目组默认包含读取和写入，自定义可选择增加混合负载。

| 配置 | 项目组 | 最大 Q × T | 目的 |
| --- | --- | ---: | --- |
| 默认 | SEQ1M Q8T1、SEQ1M Q1T1、RND4K Q4T1、RND4K Q1T1 | 8 | 对比连续传输及小块随机访问的低、中并发表现 |
| 快速 | SEQ1M Q1T1、RND4K Q1T1 | 1 | 用较小传输量检查基本读写是否可完成及其表现 |
| SSD | SEQ1M Q8T2、SEQ1M Q1T1、RND4K Q4T4、RND4K Q1T1 | 16 | 对比多工作线程吞吐与低并发响应 |
| HDD | SEQ1M Q1T1、SEQ1M Q4T1、RND4K Q1T1、RND4K Q4T1 | 4 | 使用单工作线程比较 Q1/Q4，减少独立访问流的竞争 |
| 自定义 | 最多四组，自选顺序/随机、块大小、Q、T、混合负载及循环 | 16 | 检验用户指定的负载 |

普通配置继续使用已有的测试次数、文件大小、数据模式等页面偏好；没有给每种硬盘编造固定的“最佳参数”。

快速模式固定：

- 顺序项目：每次传输 128 MiB；随机 4 KiB 项目：每次传输 1 MiB。
- 1 轮预热 + 1 轮正式测量，不启用加量去极值，不再附加项目/轮次间等待。
- 不应用普通配置保存的小块文件比例，避免把快速随机项目再次放大或缩小。
- 界面显示实际的 1 轮、128 MiB，并禁用相应编辑；返回普通配置恢复原先保存的次数、文件大小、去极值及小块效率选择。
- 两组测试不能排除全部坏块、容量造假或其他硬件故障，也不是全文件数据校验。读取测试仍需要先写入临时源文件。

完成耗时由设备实际速度、准备与刷盘决定，不承诺固定秒数。

## 4. 自定义联动及兼容

| 已选 Q | T 可选值 |
| ---: | --- |
| 1 | 1、2、4、8、16 |
| 2 | 1、2、4、8 |
| 4 | 1、2、4 |
| 8 | 1、2 |
| 16 | 1 |

选 Q 时一次性更新 Q、T；当前 T 超限则下调到最大允许值。例如 Q1T16 改选 Q8 后变成 Q8T2。降低 Q 不会自动提高 T。

持久化读取和写入均执行相同的约束，旧的 Q32T16 等配置会变成 Q16T1，保留行标识、访问类型、块大小和混合负载选择。旧的隐藏实验配置也通过统一构造函数限制乘积。

运行时另外检查乘积，防止直接构造非法测试绕过界面。测速进度原来的“每路目标 Q…”改成“目标在途…”，避免把多线程合计目标误认为每线程 Q。

自定义成为普通功能后，移除设置中的旧启用开关；旧偏好键继续保留用于兼容，不清除用户的历史配置。

## 5. 验收证据

### 5.1 定向 XCTest

结果包：

`/Users/lex./Desktop/XcodeProjects/Capricorn/DerivedData/Logs/Test/Test-Capricorn-2026.10.19_14-52-52-+0800.xcresult`

日志：

`/Users/lex./Desktop/Capricorn-RealThreads-20261019-e40ca67/Capricorn-real-threads-final-20261019.log`

| 范围 | 项数 | 结果 |
| --- | ---: | --- |
| AIOBenchmarkTransferTests | 4 | 通过；线程标识、独立队列、连续区间无重叠/遗漏、失败与取消回收、重跑、非零回读及非法乘积拒绝 |
| AIOTransferTests | 10 | 通过；共享额度、资源错误重试、短传输及错误回收等 |
| AIOAcceptanceTests | 6 | 通过；保留原负载验收，新增同步/异步快速模式端到端检查 |
| BenchmarkProfileConfigurationTests | 6 | 通过；配置集合、乘积、旧值迁移、快速模式大小/轮次、结果隔离及双语文案 |
| BenchmarkControlsTests | 4 | 2 通过、2 跳过；真实菜单联动、快速模式双语有效值及偏好恢复通过，旧的窗口服务器截图检查因权限不足跳过 |
| CapricornTests 中的配置/操作筛选/单项/帮助等回归 | 21 | 通过 |
| WorkloadStoppingPresentationTests | 5 | 通过；停止等待说明及最终停止状态回归 |
| 合计 | 56 | 54 通过，2 跳过，0 失败 |

实际界面测试通过菜单项目的 action 操作 SwiftUI 控件，并检查保存值及重新呈现的选项。早期测试仅发送 NSPopUpButton action，未真正触发菜单绑定，造成两次测试定位失败；修正测试驱动后通过，没有将这两次失败算作验收成功。

另外保留了英、中快速模式的视图缓存截图，已检查中文截图的配置、固定次数/大小和两行结果矩阵。缓存截图不等同于获授权的完整窗口服务器截图；后者仍明确记为跳过。

### 5.2 E 盘验证

目录：

`/Volumes/40G4T_NTFS_E/Capricorn-RealThreads-20261019-e40ca67`

验证记录：

`/Volumes/40G4T_NTFS_E/Capricorn-RealThreads-20261019-e40ca67/verification.json`

使用独立可执行程序直接编译生产的 `LockedState.swift`、`AIOTransfer.swift`、`AIOBenchmarkTransfer.swift`；只对应用外围模型定义作最小辅助替代。此路径验证真实磁盘 I/O 和工作线程，不冒充在 E 盘执行过整个应用 UI 或完整测速服务。

每组文件 8 MiB + 137 字节、64 KiB 请求块，覆盖非整块尾部。预先设定大小后以 0xA7 非零数据写入，fsync，再重新打开并完整回读。

| Q/T | 观察到的实际工作线程 | 缓存写入总在途峰值 | 非缓存写入总在途峰值 | 非零回读 / 结束占用 |
| --- | ---: | ---: | ---: | --- |
| Q16T1 | 1 | 16 | 16 | 两组一致 / 0 |
| Q8T2 | 2 | 16 | 16 | 两组一致 / 0 |
| Q4T4 | 4 | 16 | 16 | 两组一致 / 0 |
| Q2T8 | 8 | 16 | 16 | 两组一致 / 0 |
| Q1T16 | 16 | 16 | 16 | 两组一致 / 0 |

每线程观察到的在途数量不超过其 Q。共保留十个数据文件，合计 83,887,450 字节，约 80 MiB，另有少量标记及验证 JSON。

程序以独占方式新建验收目录，使用 O_EXCL/O_NOFOLLOW 创建文件，所有写入均在新目录中；没有以 E 盘已有文件作为写入或删除目标。没有改动系统 AIO 参数，也没有执行清理。

复现编译命令：

```sh
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  Capricorn/Support/LockedState.swift \
  Capricorn/Services/Benchmark/AIOTransfer.swift \
  Capricorn/Services/Benchmark/AIOBenchmarkTransfer.swift \
  script/fixtures/aio_real_threads_acceptance.swift \
  -o /tmp/Capricorn-real-threads-acceptance-20261019
```

执行时必须提供 E 盘下新的 `Capricorn-RealThreads-...` 目录；工具拒绝复用已有目录，避免覆盖验收结果。

### 5.3 构建

普通 Debug 构建及测试通过，签名使用本机 Apple Development。

额外构建命令：

```sh
xcodebuild build -project Capricorn.xcodeproj -scheme Capricorn \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath DerivedData SWIFT_VERSION=6.0 \
  SWIFT_STRICT_CONCURRENCY=complete \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY='Apple Development'
```

结果：BUILD SUCCEEDED。仍有既有 SMART/磁盘枚举 String(cString:) 弃用警告及 AppIntents 元数据提示，没有把这些无关警告描述为本次新增或已修复。

## 6. 数据保留与边界

清理清单：

`/Users/lex./Desktop/Capricorn-RealThreads-20261019-e40ca67/CLEANUP_INVENTORY.json`

该目录还保存了各次构建/测试日志、E 盘 verification.json 副本及双语截图。独立验收可执行文件保留于 `/tmp/Capricorn-real-threads-acceptance-20261019`。

本轮临时目录按测试前缀、任务时间及标记文件汇总了 63 个保留目录，约 1.90 GB；清单逐个列出。测试目录带 `CAPRICORN_TEST_ARTIFACTS.txt` 或 JSON 标记。它们以及 E 盘新目录均未清理。DerivedData 为共享构建目录，不应整目录作为本任务数据清理。

限制：

- 本机查询值仍为 kern.aioprocmax=16、kern.aiomax=90；增加线程不增加进程的 POSIX AIO 额度，资源暂时不足仍需重试。
- 真正的线程数量不等于 CPU 一定在同一瞬间执行相同数量的线程。
- 本轮 E 盘验证针对小规模数据正确性和线程/队列约束，不证明长时间持续性能或全盘状态。
- 真实 T 的异步改造针对测速引擎；实时活动大文件负载沿用已有固定调度，不把其内部 T 乘数宣称为新增的真实工作线程。
- ftruncate/fsync 等阻塞系统调用的等待边界仍然存在，不承诺所有停止请求即时结束。
- 本轮未运行全项目测试，没有发布版本、推送远端或合并 Main。

实现按功能本地提交：真实线程 `e40ca67`，配置与约束 `daea7b4`，界面及快速流程 `fce4d91`；验收工具和本报告另行提交。
