# Privileged Device Service

Branch: `codex/privileged-device-helper`

## Scope

One demand-started root LaunchDaemon, `lex.Capricorn.DeviceHelper`, serves
multiple typed, restricted SMART operations over authenticated XPC:

| Operation | Allowed behavior |
| --- | --- |
| SMART read | Bundled smartctl `-a --json`; optional standby check |
| Self-test capability | `-c --json` |
| Self-test history | `-l selftest --json` |
| SMART error log | `-l error --json` |
| Short / extended self-test | `-t short --json` / `-t long --json`, supported transports only |
| Abort self-test | `-X`, supported transports only |
| Manual SNT | Bundled raw-USB tool, explicit USB Registry ID and one allowlisted SNT type |

The ordinary 7.5 executable remains the default for passive discovery and
normal reads. An administrator-denied read can retry through the service
only when the user has already enabled it. No background refresh registers
the service or opens administrator authentication. SNT does not run as an
automatic SMART fallback.

No arbitrary executable, shell, command line, environment, database path,
filesystem path or disk-management command crosses XPC. First Aid, benchmarks,
imaging, arbitrary mounts and firmware commands are not part of this service.

## User Activation

1. Build and sign the application and all embedded executables with the same
   certificate-backed development team. Ad-hoc signing is insufficient.
2. Install the complete application at `/Applications/Capricorn.app` before
   enabling the service. Distribution builds must also follow the normal
   Developer ID / notarization process.
3. Open Settings, then **Privileged Device Service**, and choose
   **Enable Device Service**.
4. Approve the daemon in macOS System Settings when requested. The settings
   section refreshes the system's status when returning to the application.
5. Continue to grant removable-volume privacy access when macOS requests it.
   LaunchDaemon approval and TCC privacy consent are separate system policies.

Once the service is enabled, the listed operations no longer use a fresh
AppleScript administrator prompt for each command. This does not grant all
future USB access, bypass TCC, or add unsupported hardware self-test commands.
The existing macOS native NVMe / ASMedia / Realtek self-test limitations remain.

## SNT Confirmation And Ownership

The existing **Unmount and Try SNT** confirmation, mounted-volume permission
check, physical-disk lease, application busy checks, refresh protection and
post-read identity reconciliation remain in place. A raw request is rejected
unless it explicitly confirms unmounting and identifies an external physical
USB disk. The three bridge types are ASMedia, JMicron and Realtek.

Each raw tool invocation owns the full non-forced unmount, USB capture, read,
release and restoration cycle. The service must not put another `diskutil`
unmount/mount wrapper around it. If the application disconnects, the worker
continues cleanup; disconnecting an XPC client is not cancellation.

A process-wide gate admits only one worker across XPC connections and users.
It rejects service stop while a worker is active and rejects new requests
after a successful stop reservation. Failed unregister attempts cancel that
reservation when possible. Ordinary commands receive SIGTERM after 45 seconds;
the raw worker is not forcibly terminated, because it owns restoration and
has transport-specific timeouts. A hung raw worker can therefore keep the
service busy and prevent safe stop. Shutdown, cable removal, force-killing
processes or manually disabling the daemon outside Capricorn are not covered
by the application's stop protection.

Up to eight completed responses are cached in memory, bound to the peer UID
and request UUID. Replaying the same completed UUID returns its result without
recapturing USB. The protocol exposes result lookup; the current UI does not
automatically recover results after a broken connection or app crash. It
warns that restoration may still be running. There is no persistence across
daemon termination or reboot.

## Authentication And Disk Validation

- Both sides use the macOS XPC code-signing requirement APIs. The client
  requires the helper identifier and its own signing team; the server
  requires `lex.Capricorn` with that same team and an Apple-backed signature.
- The executable's actual signing identifier is explicitly set to
  `lex.Capricorn.DeviceHelper`. A command-line target's product bundle
  identifier alone does not set that code-signing identifier.
- The service obtains UID and audit session from the XPC connection, never
  from JSON. Only the current console user can perform a device operation.
- Requests carry the whole physical disk's BSD name, media Registry ID,
  size, internal/external state and USB Registry ID. The service re-resolves
  and compares all fields immediately before opening it.
- A normal IOService target is rebuilt from an allowed storage ancestor's
  Registry ID. Arbitrary IOService paths, virtual/synthesized disks and
  partitions are not accepted.
- The service constructs fixed arguments itself. A manual marker on the
  client adapter is not a substitute for the UI confirmation; the signed
  application remains responsible for obtaining that confirmation.

## Executable Integrity And TCC Session

The service snapshots its containing signed app into a private root-owned
directory under `/private/var/run/lex.Capricorn.DeviceHelper.XXXXXX`.
Before exposing that directory to TCC, it assigns root ownership, removes
writable ACLs, restricts permissions, rejects external symbolic links and
special files, and verifies the app's strict nested signature and both
worker signatures. The workers and drive database must be regular files.

Workers execute from this verified snapshot rather than the user-writable
installed app. This closes the signature-check / executable-path replacement
window. The root-owned containing app also preserves a verifiable bundle
identity for TCC. Snapshot directories are retained until reboot; this
prototype does not delete them. Failed staging leaves its parent private.

`launchctl asuser` joins the requesting console user's bootstrap/audit
context without dropping root. The UID comes from the authenticated peer.
The existing raw worker still checks root UID, audit UID/session and raw-node
access before unmounting. Its user-side volume permission request is retained.

The earlier one-shot runner's TCC success is not proof that a new daemon and
snapshot path are authorized. This new path needs a first-run hardware/TCC
validation after the user approves the installed service.

## Stop And Updates

Use **Disable Device Service** in Capricorn Settings. The client first asks
the service to reserve an idle stop, then calls `SMAppService.unregister()`.
It does not stop a worker that might be restoring mounts.

The in-app updater blocks application replacement while the service is
enabled or awaiting approval. For this first version, explicitly disable it,
update the app, then enable it again. Follow the same procedure for manual
app replacement. Automatic helper-version replacement is not implemented.

## Verification

On 2026-11-01, the initial focused suite passed 63 tests, followed by 35
update/settings tests. After the final bilingual rendering test was added,
the complete application suite passed 666 tests with 8 existing
environment-dependent skips and no failures. Both service settings pages
were rendered and visually checked.
The signed Debug app passed strict nested code-signature verification.
The Release configuration also built successfully with both arm64 and x86_64
in the app and helper. This is an Apple Development-signed validation build,
not a notarized distribution release.

The focused suite checks fixed command generation, invalid transport/identity
rejection, manual SNT gating, bounded UID-bound result caching, concurrent
admission, stop protection, client adapter output/exit preservation, passive
refresh behavior, actual embedded signing identifiers, daemon packaging and
unprivileged direct-launch rejection. Existing SNT tests cover confirmation,
volume-access denial, bridge probing, restoration evidence, refresh retention,
stable identity matching and dismissal behavior.

System service approval, the first daemon-launched TCC check, a full hardware
SNT read/restoration, and self-test start/abort are not simulated as successful
by these unit tests. They require a controlled hardware validation after
installation. No hardware self-test or USB capture is started automatically
by building or running the test suite.

## 中文操作摘要

- 在设置中启用一次“特权设备服务”，经系统批准后，受限的 SMART 功能共用一个
  root 服务，不再逐条弹出 AppleScript 管理员密码框。
- 可移动卷的 TCC 隐私授权仍由系统单独管理，不能用 XPC 一次性绕过。
- SNT 每次仍须确认卸载；后台扫描、刷新不能主动接管 USB。
- 不提供任意 shell、路径、命令或通用磁盘操作接口。
- 正在执行或恢复挂载时不能通过 Capricorn 停用服务。
- 第一版更新前须先停用服务，更新完成后再启用。
- 新服务的真实 TCC 归属、硬件读取和挂载恢复必须在系统批准后另行验证；
  单元测试通过不代表这些硬件步骤已经完成。

### 首次真机验收

1. 安装完整签名 App、在设置中启用服务，并由用户完成系统批准。
2. 先验证普通 SMART/日志只读请求；确认未逐条要求管理员密码。
3. 用户确认 SNT 卸载后，核对诊断中的 root UID、请求用户的 audit UID/
   session、SMART 数据和 `restored` 证据，再检查卷实际挂载状态。
4. 刷新与关闭提示窗口后，确认 SMART 数据仍显示且没有额外 USB 接管。
5. 自检仅在受支持的设备上、用户明确确认后验证短测及中止；不对不支持的
   NVMe/SNT 通路宣称自检能力。
6. 活动操作期间尝试停用应被拒绝；操作及挂载恢复完成后方可停用。
