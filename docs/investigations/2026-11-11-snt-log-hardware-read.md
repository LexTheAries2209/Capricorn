# SNT log hardware read experiment

## Scope and device

On November 11, 2026, the user explicitly confirmed testing the connected CODEX
Compact Drive after its read-only UDF mount was identified. This was one manually
authorized raw USB capture, not an automatic SNT attempt.

- Volume: `B_0044_1DOZ`, `/Volumes/B_0044_1DOZ`.
- Physical capacity: 1,920,383,410,176 bytes; 512-byte sectors.
- NVMe model: `CDXCDC0192M300N40A`, firmware `35E278FU`.
- Transport: `sntjmicron`, using the signed bundled
  `smartctl-usbraw` version `pre-8.0-c68a1b9-capricorn4`.

## Command and ownership

The opt-in `SNTLogHardwareTests` harness freezes the physical USB target, checks
the specified mounted volume, acquires the existing disk-operation lease,
verifies the tool signature, requests mounted-volume access, checks open files
and passes the non-capturing mount-identity preflight.

It invokes the existing native administrator-consent runner with this fixed
command, once, without protocol fallback:

```text
smartctl-usbraw -i -c -l error -l selftest --json=c -d sntjmicron usbraw:<registry-id>
```

The experiment keeps the raw backend's read-only command allowlist. It sends no
self-test start/abort, format, firmware or filesystem write command. Evidence
is stored on the host's local filesystem, away from the tested volume.

## Observed result

The response is timestamped 14:43:44 CST and records exit status 0. All lifecycle stages
were present, in order: `unmounting`, `capturing`, `reading`, `releasing`,
`restoring`, `restored`. The non-forced unmount succeeded on its first attempt.

| Requested operation | Device response | Conclusion |
| --- | --- | --- |
| Error Information Log | `nvme_error_information_log`: `size=64`, `read=16`, `unread=0`, no entry table | The log read succeeded. The returned slots contain no valid error entries. This is not a claim that all possible historical device faults are absent. |
| Existing Self-test Log | Identify reports `nvme_optional_admin_commands.value=6`, `self_test=false`; no `nvme_self_test_log` | This device reports no standard NVMe self-test support. smartctl skips reading log page 0x06 when that capability is absent. Reading existing records was therefore not demonstrated. |

Independent inventory matching and a subsequent `diskutil info` check confirmed
the same disk and original mount path, UDF filesystem and read-only volume
state. No second physical capture was performed.

## Evidence and validation

The original response, transcript, arguments, before/after inventories and
summary remain under the ignored local directory:

```text
DerivedData/SNTLogEvidence/FF213CFE-450F-45B7-85AC-97A151BA108A/
```

The first hardware XCTest reported one assertion failure because it initially
required a self-test log even from a controller advertising no self-test
support. The actual smartctl command succeeded and restoration was verified.
The harness was corrected to distinguish explicit unsupported capability from
an empty history or a failed read. Offline replay of the original response
verifies both existing parsers and the recorded lifecycle/mount checks.

The signed build and 56 existing simulated SNT tests passed before capture.
The captured-response regression and offline replay passed afterward; the live
hardware test correctly skips without its explicit opt-in environment.

## Integration boundary

This is a hardware feasibility result, not a released app feature. The normal
app UI and device-helper SNT command allowlist remain unchanged. Error-log
reading can proceed to integration. Standard self-test history reading still
needs verification with a drive that advertises self-test support.

The hardware harness requires `CAPRICORN_SNT_LOG_TEST_READ_LOGS=1`, an exact
`CAPRICORN_SNT_LOG_TEST_DISK`, mounted `CAPRICORN_SNT_LOG_TEST_VOLUME`, explicit
`CAPRICORN_SNT_LOG_TEST_BRIDGE` and absolute local
`CAPRICORN_SNT_LOG_TEST_OUTPUT`. Supply these to xcodebuild with the
`TEST_RUNNER_` prefix. `CAPRICORN_SNT_LOG_TEST_REPLAY` instead selects an existing
evidence directory for an offline replay with no USB or diskutil access.
