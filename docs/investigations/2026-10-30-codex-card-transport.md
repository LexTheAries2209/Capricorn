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

This validates removal of the UUID precondition for the attached card.
Actual USB capture, SNT commands and remount after release have not yet been
tested with this exception.
