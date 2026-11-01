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
snapshot path are authorized. Native NVMe reads through the daemon and signed
snapshot passed the installed hardware validation below. That connection did
not exercise raw USB removable-volume TCC; the SNT path still needs separate
validation with a USB mass-storage device.

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

The ordinary suite does not simulate system approval, a successful raw USB
TCC check, a full hardware SNT read/restoration or self-test start/abort.
The explicit hardware suite described below performs only SMART/log reads.
No hardware self-test or USB capture is started by either suite.

## First Installed Hardware Baseline

On 2026-11-01, the user supplied an external test disk and authorized the next
validation step. The existing universal Release-configuration development
build was verified with `codesign --verify --deep --strict`, copied to
`/Applications/Capricorn.app`, verified again and launched from that location.
No existing app at that path was replaced.

The attached test disk was `Lexar SSD ARES 4TB`, 4,096,805,658,624 bytes,
currently `/dev/disk6`. Disk Utility reported `PCI-Express`, an
`IONVMeController` device-tree path, external physical media and native SMART.
This connection is not the USB mass-storage / raw SNT transport. The APFS
volume `40G4T_APFS_F` remained mounted at `/Volumes/40G4T_APFS_F`.

At 12:15:28 CST, the installed ordinary smartctl 7.5 was run **as the normal
user**, without the privileged service:

```sh
/Applications/Capricorn.app/Contents/Resources/smartctl \
  -a --json -d nvme /dev/disk6
```

It returned exit status 0, SMART passed, 44 C, 2% percentage used, 978
power-on hours, no media errors and no error-log entries. These are a
point-in-time baseline, not a general disk-health guarantee and not evidence
of a successful privileged XPC request.

Clicking Enable Device Service registered a pending approval. `SMAppService`
reported `requiresApproval`; the system log said the job was not allowed to
bootstrap. The first registration call also returned `Operation not
permitted`, so the existing Review System Approval button was used to open
System Settings > Login Items & Extensions. The `Capricorn.app` background
checkbox was observed off. The launchd system job was not loaded.

The user's system approval is required before the daemon and its staged
worker/TCC path can be tested. No service approval was automated, no
administrator password was collected, no real self-test was started, and
no volume was unmounted or USB device captured in this baseline step.
Testing SNT additionally requires a USB mass-storage connection rather than
this disk's current native PCIe/NVMe connection.

## Approved Service Hardware Validation

After the user confirmed system approval on 2026-11-01, launchd exposed the
registered system Mach service. The first real XPC test revealed two runtime
issues that had not been covered by ordinary unit tests:

1. `BundleProgram` launches with a relative `argv[0]`
   (`Contents/MacOS/CapricornDeviceHelper`). Interpreting that as an absolute
   image location made startup verify the wrong containing directory and exit
   before listening. Commit `29c6474` resolves the actual loaded image using
   `_NSGetExecutablePath`, checks standard app embedding, and records startup
   failures with unified logging.
2. Foundation canonicalizes `/private/var` to `/var`. Comparing a resolved
   framework symlink to an unresolved snapshot root falsely rejected legitimate
   internal Sparkle links as external. Commit `7d8167c` canonicalizes both
   paths while preserving the descendant boundary check. Regression coverage
   includes the alias, a valid framework link and an external sibling target.

For each replacement, the service was disabled/unregistered and the older app
was moved into `output/DeviceHelperBackups/` before installing a newly verified
universal development build. No bundle was replaced while a device worker was
active. Once startup worked, the actual authenticated prepare-to-stop and
unregister sequence also completed successfully.

At 14:07 CST, the opt-in Xcode hardware test passed against the installed
service and external `disk6`. A second successful run at 14:09 CST used the
production `DeviceHelperClient.perform` for the initial SMART request.
Both client and server retained their production signing requirements.

Verified results:

- SMART, self-test capability, self-test log and error-log reads all returned
  exit status 0. No self-test was started or aborted.
- The production client received `Lexar SSD ARES 4TB` data: 56 C, 2% endurance
  used, zero media errors in the second run. Values are point-in-time readings.
- The helper was a launchd child with real/effective UID 0. Its execution logs
  reported `euid 0` and authenticated console UID 501 for every operation.
- `smartctl`'s returned arguments referenced the database in
  `/private/var/run/lex.Capricorn.DeviceHelper.C3w60z/Capricorn.app`.
  The test independently verified the snapshot's strict nested signature,
  root ownership, and absence of group/other write permission on the app,
  database and SMART executable.
- Replaying a completed request UUID returned identical cached output.
- A request with an altered media Registry ID was rejected by the server
  before another device command ran.
- A separate probe signed by the **same development team**, but with identifier
  `lex.Capricorn.UntrustedProbe`, received an XPC interruption instead of a
  version reply. The helper's system log explicitly recorded
  `Dropping check-in message due to code signing requirement`.
- `40G4T_APFS_F` remained mounted at `/Volumes/40G4T_APFS_F`, with its original
  volume UUID. No unmount, raw USB capture or forced operation was performed.

The added hardware test is skipped unless both environment variables are set:

```sh
TEST_RUNNER_CAPRICORN_HELPER_TEST_DISK=disk6 \
TEST_RUNNER_CAPRICORN_HELPER_TEST_TYPE=nvme \
xcodebuild test -project Capricorn.xcodeproj -scheme Capricorn \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath DerivedData \
  -only-testing:CapricornTests/DeviceHelperHardwareTests \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY='Apple Development'
```

The disk name above is historical; select and verify the currently connected
external physical disk before enabling this test. It refuses internal disks
and sends no SNT/self-test-control request. SMART health-warning exit bits are
preserved rather than confused with transport failures.

The non-app rejection probe is `script/device_helper_client_rejection.swift`.
Compile it outside the app and sign with a different identifier; it only asks
for the protocol version, never a device operation. A reply is failure and a
timeout is inconclusive. Its observed rejection was corroborated by the
service's signing-requirement log, not just a disconnected socket.

Final ordinary regression run at 14:13 CST: **669 tests, 9 skipped, 0 failures**.
The skips comprise the previous 8 environment-dependent skips and the new
explicitly opt-in hardware test. The hardware test separately passed with
opt-in enabled. The installed helper and app remain system-approved and
development-signed; no distribution notarization is claimed.

The NVMe path emitted no matching removable-volume TCC record in the inspected
window. Therefore these results do **not** establish raw USB audit-session/TCC,
SNT capture/restoration, UI publication after SNT, or hardware self-test
start/abort. Those still need the appropriate USB connection or supported
self-test transport and manual confirmations.

## 中文操作摘要

- 在设置中启用一次“特权设备服务”，经系统批准后，受限的 SMART 功能共用一个
  root 服务，不再逐条弹出 AppleScript 管理员密码框。
- 可移动卷的 TCC 隐私授权仍由系统单独管理，不能用 XPC 一次性绕过。
- SNT 每次仍须确认卸载；后台扫描、刷新不能主动接管 USB。
- 不提供任意 shell、路径、命令或通用磁盘操作接口。
- 正在执行或恢复挂载时不能通过 Capricorn 停用服务。
- 第一版更新前须先停用服务，更新完成后再启用。
- 已完成系统批准后的真实 XPC、root 工具快照、NVMe SMART 与日志只读验证，
  并验证错误磁盘身份和非本 App 客户端会被拒绝。
- USB-SNT 的 TCC 归属、接管与挂载恢复仍需 USB 通路真机验证；本轮的 PCIe/
  NVMe 成功不能替代这些步骤。

### 首次真机验收

1. 安装完整签名 App、在设置中启用服务，并由用户完成系统批准。
2. 先验证普通 SMART/日志只读请求；确认未逐条要求管理员密码。
3. 用户确认 SNT 卸载后，核对诊断中的 root UID、请求用户的 audit UID/
   session、SMART 数据和 `restored` 证据，再检查卷实际挂载状态。
4. 刷新与关闭提示窗口后，确认 SMART 数据仍显示且没有额外 USB 接管。
5. 自检仅在受支持的设备上、用户明确确认后验证短测及中止；不对不支持的
   NVMe/SNT 通路宣称自检能力。
6. 活动操作期间尝试停用应被拒绝；操作及挂载恢复完成后方可停用。
