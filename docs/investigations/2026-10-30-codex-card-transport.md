# Codex Card USB Transport Investigation

## Capacity Fix

The Codex card is exposed as a whole USB IOMedia device `disk13` with:

- physical IOKit/Size: `960197124096` bytes
- filesystem/TotalSize/VolumeSize: `960191528960` bytes
- mounted filesystem: UDF at `/Volumes/B_0022_1DOZ`

`DriveDevice.sizeBytes` now uses the first positive physical media field in
`IOKitSize`, `Size`, `TotalSize`. The mounted volume keeps its own filesystem
capacity. The raw USB target resolver therefore compares the frozen target
against physical media size without confusing it with the UDF capacity.

## Why `sat,auto` Appears

The live USB identity is:

```text
VID: 0x2818 (10264)
PID: 0x0012 (18)
bcdDevice: 0x4104
USB product: CX.0001005
USB serial: 000001053430
interface class/subclass/protocol: 08/06/62
USB link: 10 Gb/s
macOS driver: IOUSBMassStorageUASDriver
```

The USB interface is a standard USB Mass Storage / UAS interface. macOS exposes
the block device through its SCSI storage layer, so the passive scan reports
`protocol: SCSI` and an info label of `SCSI/SAT`.

In the upstream PoC, `get_usb_dev_type_by_id()` looks up a known bridge mapping
by VID, PID and device version. The tuple `0x2818:0x0012:0x4104` is not in the
bundled USB bridge table. When the lookup is unknown or unsupported, the PoC
deliberately falls back to `sat,auto` for a safe standard SAT INQUIRY. This is
a passthrough type guess, not proof that the media is SATA. It also does not
prove that the underlying device is NVMe; the USB descriptors alone identify
only the USB mass-storage transport. A failed SAT command would be expected if
the bridge does not implement SAT or if it is an NVMe bridge with a different
vendor protocol.

No transport behavior was changed in this investigation. The `sat,auto` result
is recorded for future bridge identification and a possible dedicated transport
implementation.

## Validation

The two new parser tests failed before the capacity fix and pass after it.
They cover separate physical and filesystem capacities and reject non-positive
media fields before falling back. The complete suite passed 627 tests with
8 existing environment-dependent skips and no failures.

A live probe using the application's inventory provider and USB target
resolver returned:

```text
CODEX physical=960197124096 volume=960191528960 target=usbraw:4297324860
```

The signed application was rebuilt and launched. Clicking Try SNT on the
Codex card now opened the confirmation sheet with its mounted UDF volume.
The sheet was cancelled without administrator authorization, unmount or
capture. The existing SNT/USB transport implementation remains unchanged.

## Authorized CODEX Name Exception

The user authorized using the unique CODEX recording volume name instead of
a missing persistent UUID. Patch `capricorn3` implements this for the observed
USB reader `2818:0012` and whole-media UDF named `CODEX COMPACT DRIVE Media`.
It records the exact volume name, physical capacity and block size. Restoration
also requires the same USB location, serial and bridge identity, and rejects
multiple matching media. Other UUID-less devices retain the original refusal.

The application now recognizes this same narrow identity across BSD device
renumbering, publishes a completed manual SMART read only to a unique device,
and retains it during ordinary refresh. USB bridge detection and vendor
command selection were not changed.

The rebuilt universal tool passed a live, read-only mount preflight:

```text
smartctl-usbraw --capricorn-usb-mount-preflight usbraw:4297324860
CAPRICORN_USBRAW_CODEX_NAME B_0022_1DOZ
CAPRICORN_USBRAW_MOUNT_PREFLIGHT passed (no unmount or capture)
```

All 3 upstream test programs passed, including synthetic CODEX metadata
coverage. The application suite passed 630 tests with 8 existing
environment-dependent skips and no failures. New coverage includes narrow
eligibility, BSD renumbering, SMART publication and refresh retention, and
rejection of duplicate CODEX names.

The application was rebuilt with its Apple Development identity and launched.
Its embedded, signed universal executable reports `capricorn3` and passed the
same live mount preflight.

At this stage only removal of the UUID precondition had been validated.
The subsequent live capture and publication checks are recorded below.

## Post-Capture Result Reconciliation

The user's 02:36:10 diagnostic confirms that `sntjmicron` returned the CODEX
NVMe identity and SMART log with exit status zero, followed by `restored`.
The application nevertheless rejected publication because its one inventory
refresh did not produce a unique stable identity. That diagnostic did not
include the expected or rediscovered identity fields, so it does not establish
which field differed or whether there were zero or multiple matches.

The application now allows up to four inventory refreshes, separated by
500 ms, when a successful reading has zero identity matches. Multiple matches
remain an immediate refusal. These retries only re-enumerate inventory and
perform normal read-only SMART refresh; they do not repeat USB capture.
`CAPRICORN_USBRAW_IDENTITY` records the expected identity, external physical
device candidates and matches for each attempt in the diagnostic transcript.
The existing CODEX name exception and other stable-identity rules are unchanged.

Two regression tests cover incomplete metadata followed by a complete,
renumbered CODEX device, and immediate rejection of ambiguous CODEX names even
when a later inventory would contain only one of them.

A live manual JMicron read at 02:47:42 completed all six lifecycle stages.
It returned model `CDXCDC0096M200N30A`, temperature 31 C, percentage used 5,
power-on hours 617 and zero media errors. Reconciliation found exactly one
match, `disk13`, on attempt one, with volume `B_0022_1DOZ`, physical size
`960197124096`, 512-byte blocks and USB identity `2818:0012`.
Closing the result sheet displayed the SMART attribute table and good health
in the sidebar. A subsequent manual refresh retained those readings.
Diskutil independently confirmed the UDF volume was mounted at its original
path. This run did not reproduce the original identity mismatch, so the
bounded-retry regression coverage should not be mistaken for proof of its
precise cause.

Validation: all 29 focused SNT tests passed. The full application suite passed
632 tests with 8 existing environment-dependent skips and no failures.
