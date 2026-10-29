# Manual Darwin raw USB SMART experiment

Branch: `codex/darwin-usb-smart-poc`

## User Flow

1. Wait for the normal disk/SMART refresh to finish.
2. Right-click an external USB disk that has no SMART payload and choose
   **Try SNT…** / **尝试 SNT…**.
3. Review the physical disk and mounted volumes. Keep **Detect Bridge** unless
   the enclosure's chipset has been independently identified.
4. Choose **Unmount and Try SNT** and approve the native administrator prompt.
5. The isolated tool attempts non-forced unmount, exclusive USB capture,
   Identify/Health reads, release, and mount restoration.
6. Review both the SMART result and restoration result. Diagnostic output
   includes the tool's lifecycle events and JSON. A restore failure does not
   discard health data that was successfully obtained.

The bridge selector permits JMicron, ASMedia and Realtek explicitly. Automatic
detection refuses an unknown/SAT bridge instead of guessing vendor commands.
Composite devices and ambiguous multi-disk/LUN configurations are refused by
the upstream raw USB discovery policy.

Normal automatic SMART reads continue to use the original smartctl 7.5.
The experiment is never used as an automatic fallback and does not run
`--scan-open`. Passive experiment discovery is `--scan -d usb --json=c`.

## Coordination And Device Identity

The live whole-disk size and USB ancestry are checked before confirmation.
The USB Registry ID is frozen, rechecked before administrator authorization,
and passed as an explicit `usbraw:ID` target. The transport does not fall back
from a missing Registry ID to a reused BSD name.

During execution, refresh, diagnostics, new disk operations, monitoring,
workloads, benchmarks and updates are blocked. The existing physical-disk
lease coordinates participating Capricorn processes. Normal application quit
and sheet dismissal are blocked until the process finishes its cleanup.
This lease does not lock other applications or the file system; the transport
must still obtain system-level exclusive access.

After release, Capricorn refreshes the inventory and publishes the reading only
against a unique stable identity match (serial or volume UUID). It does not
assign data to another disk merely because it reused the old BSD name.
If no stable match is available, the reading remains in the session result.

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
