# Manual Darwin raw USB SMART experiment

Branch: `codex/darwin-usb-smart-poc`

## User Flow

1. Wait for the normal disk/SMART refresh to finish.
2. Right-click an external USB disk that has no SMART payload and choose
   **Try SNT Read** / **尝试 SNT 读取**.
   The SMART empty state also offers this same action for eligible USB devices.
3. Review the physical disk and mounted volumes. Chipset selection is automatic.
4. Choose **Unmount and Try SNT** and approve the native administrator prompt.
5. The isolated tool attempts non-forced unmount, exclusive USB capture,
   Identify/Health reads, release, and mount restoration.
6. Review both the SMART result and restoration result. Diagnostic output
   includes the tool's lifecycle events and JSON. A restore failure does not
   discard health data that was successfully obtained.

Passive discovery first selects a recognized JMicron, ASMedia or Realtek SNT
type. For an unknown/SAT type, the confirmed manual operation tries JMicron,
ASMedia and Realtek in that order, stopping at the first SMART payload.
Identify-only JSON and ordinary text do not count as a successful read.
Each protocol owns a complete unmount/capture/read/release/restore cycle.
A failed or unconfirmed restoration stops further probing immediately.
If all three return no SMART payload after confirmed restoration, the result
reports that SMART could not be queried. There is no manual chipset picker.
Composite devices and ambiguous multi-disk/LUN configurations are refused by
the upstream raw USB discovery policy.

Normal automatic SMART reads continue to use the original smartctl 7.5.
The experiment is never used as an automatic fallback and does not run
`--scan-open`. Passive experiment discovery is `--scan -d usb --json=c`.

## Overview USB Passthrough Status

The overview provider panel now uses the neutral title **USB SMART Passthrough**
for both SAT and SNT. Transport guesses no longer label a failed read as a
confirmed USB-SATA device. A successful read, a limited read and a read returning
no valid SMART payload have separate messages. Eligible devices with no data
from ordinary USB access are guided toward a manual SNT read.

The state follows the selected manual SNT provider when present, otherwise
the ordinary smartctl provider. A failed ordinary read cannot override selected
SNT success. Available or limited provider status without a SMART payload is
downgraded to unavailable. Existing exclusions for internal/system/network/
virtual disks and memory cards, and the transport-diagnostic visibility
requirement, remain in place.

Validation includes selected SNT success alongside ordinary smartctl failure,
limited SNT status, no-data states, SNT guidance eligibility, and English/Chinese
overview rendering for both successful and unsuccessful reads.
All 46 focused tests passed. The complete application suite passed 648 tests
with 8 existing environment-dependent skips and no failures.

## Coordination And Device Identity

The live whole-disk size and USB ancestry are checked before confirmation.
The USB Registry ID is frozen, rechecked before administrator authorization,
and passed as an explicit `usbraw:ID` target. The transport does not fall back
from a missing Registry ID to a reused BSD name.
Between protocol attempts, a unique stable identity match is required in a
fresh inventory, and its current USB Registry ID is resolved and revalidated.
Missing or ambiguous identity stops further capture. The command coordinator
remains held across the complete protocol sequence.

During execution, refresh, diagnostics, new disk operations, monitoring,
workloads, benchmarks and updates are blocked. The existing physical-disk
lease coordinates participating Capricorn processes. Normal application quit
and sheet dismissal are blocked until the process finishes its cleanup.
This lease does not lock other applications or the file system; the transport
must still obtain system-level exclusive access.

After release, Capricorn refreshes the inventory and publishes the reading only
against a unique stable identity match (serial, volume UUID, or the narrowly
authorized CODEX Compact Drive name exception). It does not
assign data to another disk merely because it reused the old BSD name.
If no stable match is available, the reading remains in the session result.
Diagnostics retain every protocol attempt with `CAPRICORN_USBRAW_ATTEMPT`,
its selector, lifecycle events and JSON. The visible lifecycle list represents
the final attempt.

## Validation On 2026-10-29

- Built `smartctl-usbraw` for arm64 and x86_64; verified its ad-hoc signature,
  system-only dynamic dependencies and embedded pinned version
  `pre-8.0-c68a1b9-capricorn1`.
- Upstream `make -C lib check`: 3 test programs passed
  (`scsinvme_test`, `os_darwin_scan_test`, `os_darwin_usb_test`).
  These use synthetic devices and do not capture hardware.
- Added 12 focused application tests for eligibility, confirmation,
  administrator output/exit preservation, passive discovery, device changes,
  independent read/restoration outcomes, conflict handling and bilingual UI.
- Full Xcode test run: 613 tests, 8 skipped, 0 failures.
- Rendered and inspected English and Chinese confirmation sheets.
- Started the signed Debug build using `./script/build_and_run.sh --verify`.
- Verified the actual context menu and confirmation sheet on the attached
  ASMedia USB-NVMe disk, including its mounted APFS volume, then cancelled.
- Passive USB scan identified `sntasmedia`. An invocation without explicit
  manual authorization was rejected before unmount/capture.

No real disk was unmounted or captured during this implementation session.
End-to-end hardware reads and restoration remain unverified.

Commands:

```sh
sh scripts/build-smartctl-usbraw.sh
xcodebuild test -project Capricorn.xcodeproj -scheme Capricorn \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY='Apple Development'
./script/build_and_run.sh --verify
```

## Limits Of This First Experiment

- Capturing the device interrupts normal storage service; open files must be
  closed before confirming. This is not continuous background monitoring.
- The progress view waits for the authorized process to finish; its detailed
  lifecycle transcript is shown afterwards. There is no force-stop control.
- Capture, timeouts, unplugging, APFS restoration and chipset firmware behavior
  still require controlled hardware testing. Normal quit protection cannot
  prevent a forced process kill, shutdown or cable removal.
- A new block device with no serial and no usable volume UUID cannot be
  uniquely matched for automatic publication after re-enumeration.
- No firmware changes, SMART self-test commands, forced unmount or privileged
  driver installation are included.

Pinned corresponding source, local patch and license information are recorded
in `ThirdParty/SmartctlUSBRaw/README.md` and `THIRD_PARTY_NOTICES.md`.

## Privileged TCC Follow-Up (2026-10-29)

The user's first hardware attempt reached unmount/capture but failed creating
`IOUSBHostInterface` with `0xe00002c9`. The system log identified the concrete
denial as `kTCCServiceSystemPolicyRemovableVolumes`. The old root tool had
audit user `-1`, a build-dependent ad-hoc signing identifier, and its own TCC
identity instead of the application bundle.

The revised `capricorn2` integration:

- Embeds the tool in `Contents/MacOS`, signed on copy with the app's identity,
  retaining the stable identifier `lex.Capricorn.smartctl-usbraw`.
- Includes `NSRemovableVolumesUsageDescription` in the app and requests access
  to the selected mounted directories in the user's process before elevation.
  Directory names are discarded; file contents are not read.
- Runs administrator commands through `launchctl asuser <requesting UID>`.
  A tested `bsexec` alternative exited successfully but retained the system
  audit identity/session, so it was rejected.
- Requires root plus the expected audit UID in a non-default audit session.
  The raw-device node must open read-only and is immediately closed, with no
  reads. These checks run before every capture, before any unmount.
- Provides `--capricorn-usb-preflight usbraw:ID` for that same check without
  invoking unmount, USB capture, or SMART commands.

Observed on the attached ASMedia disk at 23:16:47 CST:

```text
CAPRICORN_USBRAW_CONTEXT uid=0 euid=0 auid=501 asid=100024 audit_status=0
CAPRICORN_USBRAW_ACCESS granted
CAPRICORN_USBRAW_PREFLIGHT passed (no unmount or capture)
PROBE_EXIT=0
```

The TCC log validated the helper signature, resolved its executable to
`Capricorn.app`, and evaluated removable-volume access as
`Sub:{lex.Capricorn}` with `Allowed (User Consent)`. `sandboxd` confirmed
`kTCCServiceSystemPolicyRemovableVolumes granted by TCC for smartctl-usbraw`.
An earlier `SystemPolicyAllFiles` policy denial in the same request fell
through to this successful removable-volume authorization; it is not evidence
that Full Disk Access is required for this device.

The selected APFS volume remained mounted at `/Volumes/40G4T_APFS_F`.
No hardware capture was run during this authorization follow-up. Passing the
preflight proves the tested identity/TCC/raw-node-access path, not subsequent
IOUSBHost interface creation, bridge commands, or mount restoration.

Validation: universal tool build; all 3 upstream synthetic tests; all 15
application SNT tests; nested app/tool signature validation. Three added tests
cover the user-session command, invalid requesting UID, and denied volume
access stopping before administrator invocation.

## Hardware Read And Refresh Regression (2026-10-29)

The user reported that a successful reading appeared briefly and disappeared.
This was reproduced with an application regression test: a normal refresh's
native/complete updates replaced the manual reading with an unsupported
snapshot. The existing retention rules only covered native transient failures
and smartctl reads skipped to avoid waking a disk.

Commits `e66016a` and `78a28a8` retain the manual snapshot's original timestamp
and provider when ordinary providers have no verified replacement. Retention
requires a unique stable identity across inventory refresh. It follows BSD
renumbering, is discarded on observed disconnection or device replacement, and
does not duplicate a reading across ambiguous identities. A verified new
provider reading supersedes it. Ordinary refresh does not perform another
SNT capture and does not mark the retained reading as a native read in progress.

The capture workflow now remains protected through post-read disk discovery
and result publication. Its own detach/mount events are ignored while active;
pending event debounce work is cancelled before capture. This prevents an
event-triggered refresh from cancelling inventory reconciliation.

An application-driven hardware read completed at 23:45:43 CST on
`ASMT 2462 NVME Media`, a 4.1 TB ASMedia USB-NVMe enclosure with APFS volume
`40G4T_APFS_F`. The completion status confirmed SMART data and mount
restoration. The system again logged removable-volume access granted to
`smartctl-usbraw`.

Observed device data:

| Field | Reading |
| --- | --- |
| Temperature | 38 C |
| Estimated lifetime remaining | 98% |
| Percentage used | 2% |
| Available spare / threshold | 100% / 10% |
| Power-on hours | 964 |
| Critical warning | 0 |
| Media errors / error-log entries | 0 / 0 |
| Unsafe shutdowns | 432 |
| Data units read | 592043228 (303.13 TB) |
| Data units written | 223056003 (114.2 TB) |

The same volume UUID `7D9E2270-0778-4D7D-9212-697D6AB4022D` was present
before and after at `/Volumes/40G4T_APFS_F`. Captured volume metadata is in
`DerivedData/USBRawHardwareValidation-20261029/volume-before.plist` and
`volume-after.plist`. The result sheet was closed; ordinary application
refreshes completed at 23:48:02 and 23:48:39 with the NVMe attributes,
temperature and manual source still present.

Validation: the original regression failed before the fix; 22 focused tests
passed after the fix. The full suite passed 621 tests with 8 existing
environment-dependent skips and no failures. After the follow-up native
loading-state fix, both the same 22 focused tests and the full 621-test suite
passed again, with the same 8 environment-dependent skips.

A second application-driven hardware attempt on the final build was initiated
at approximately 23:53 CST. It is awaiting the user's native administrator
authentication; it has not entered USB capture. Its outcome is not included
in the successful hardware results above.

This is controlled evidence for this enclosure and attached drive. It does not
establish compatibility with other bridge chipsets or unplugging/timeout
recovery. Retained readings are past manual samples, not new measurements from
automatic refresh.

## Automatic Protocol Attempts On 2026-10-30

The manual chipset picker was removed. A recognized passive SNT type selects
that protocol directly. If discovery returns an unknown/SAT type, the
confirmed operation tries JMicron, ASMedia and Realtek in order. A SMART
payload stops the sequence, including a valid reading with health-warning
exit bits. Model information, JSON output and ordinary error text do not
count as a SMART payload.

Each unsuccessful attempt must confirm restoration before the next capture.
The application re-enumerates inventory, requires a unique stable identity,
and resolves and rechecks the current USB Registry ID. Missing or ambiguous
identity, authorization errors and unconfirmed restoration stop further
capture. Diagnostics preserve all attempted protocols and any interruption.
These checks and attempts are part of one manual operation; normal refresh
does not invoke them.

Validation: all 36 SNT tests passed in the full application suite, which passed
639 tests with 8 existing environment-dependent skips and no failures.
Coverage includes a successful second protocol using a new USB selector,
all three returning no SMART, matched-only selection, restoration failure
or missing evidence, changed/ambiguous devices and valid health-warning data.
A further regression test confirms that an administrator-runner failure on
the second attempt cannot reuse the first attempt's restoration status.
Its cleanup is reported as unconfirmed and later protocols are not attempted.
English and Chinese confirmation sheets were rendered and inspected.

After the user reconnected both test devices, the signed Debug application
was rebuilt and launched. The following live UI reads completed:

| Device / time (CST) | Protocol attempt | Result |
| --- | --- | --- |
| `40G4T_APFS_F`, 04:59:40 | `1 sntasmedia usbraw:4297354928` | Exit 0, Lexar SSD ARES 4TB, 39 C, percentage used 2, zero media errors |
| `B_0023_1DOZ`, 05:02:26 | `1 sntjmicron usbraw:4297354374` | Exit 0, CDXCDC0096M200N30A, 35 C, percentage used 5, zero media errors |

The F disk changed from `disk15` to `disk6` and was correctly associated by
its data-volume UUID. The CODEX card changed from `disk14` to `disk13` and
was correctly associated by its authorized name identity. Both transcripts
contain all six lifecycle stages ending in `restored`, exactly one protocol
attempt and exactly one application identity match.

A subsequent passive scan reported `sntasmedia` for the F disk and `sat,auto`
for CODEX, confirming the matched-protocol and unknown-type paths,
respectively. CODEX succeeded on the first fallback protocol, so there was
no reason to send ASMedia or Realtek commands to it. Actual second/third
protocol fallback and triple failure were covered by simulated command and
inventory tests, not by deliberately sending incompatible commands to these
working devices.

Both result sheets were closed and the SMART tables displayed their data.
Manual refreshes at 05:01:31 and 05:05:00 retained the readings. Diskutil
independently confirmed both original volume paths were mounted. The running
application was left open with both manual SMART results.

## SMART Page Entry On 2026-10-30

The SMART empty state now offers **Try SNT Read** using the same eligibility,
busy-state check and confirmation action as the context menu. Both entry labels
use this wording without an ellipsis. The empty-state title is **No SMART Data
Read** rather than **No SMART Attributes**. Eligible USB devices explain that
standard access has returned no data and a USB-NVMe device may support SNT;
the guidance also states that reading temporarily unmounts volumes and requires
administrator authorization. Other devices retain their diagnostic description.

The 43 existing SNT and SMART presentation tests passed. Two additional
rendering tests passed for full English/Chinese guidance and SD-card exclusion.
The signed Debug application was rebuilt and launched. On the attached F disk,
clicking the SMART-page button opened the existing confirmation sheet with
the correct disk and mounted volume. The sheet was cancelled without unmount
or USB capture.

## Reported Device Serial On 2026-10-30

SNT returned `serial_number` in Identify JSON, but the SMART parser discarded
it and the sidebar/page headers displayed only the inventory serial. USB
bridges can leave that inventory value empty or report the bridge's identity
instead of the NVMe device's identity.

Successful SMART snapshots now retain the normalized device-reported serial.
The sidebar and shared page header prefer that value for the matching drive,
and SMART CSV metadata uses the same source. Redaction still applies.
Transport identity matching remains based on the original inventory fields;
a reported device serial does not overwrite a bridge serial used to associate
the reconnected physical disk. Retained SNT snapshots keep the serial during
refresh and BSD renumbering, and snapshot serialization preserves it without
breaking older records that lack the field.

Validation: all 38 SNT tests passed, including serial normalization, redaction,
CSV metadata, snapshot coding/legacy decoding and refresh retention for CODEX.
The full suite passed 643 tests with 8 existing environment-dependent skips
and no failures.

## Manual SNT Refresh Entry On 2026-10-30

Eligible external USB disks with a valid current SNT snapshot now offer
**Refresh SNT SMART** in the context menu. This opens the same confirmation
sheet and explicit manual read as the initial attempt, retaining operation
locks and authorization. Ordinary refresh still never starts USB capture.
Cancelling confirmation or returning no new SMART payload preserves the
previous reading. The SMART table's compact source label is now **SNT SMART**;
the underlying provider identity and diagnostic tooltip are unchanged.

Validation: all 40 SNT tests passed, including refresh eligibility, confirmation
without capture, replacement by a new sample and retention after an empty
read. The signed Debug application built and launched. Only the internal disk
was attached at UI verification time, so this change was not exercised against
an external device in that run.
