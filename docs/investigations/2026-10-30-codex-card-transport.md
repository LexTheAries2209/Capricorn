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

The two new parser tests pass. They cover separate physical and filesystem
capacities and reject non-positive media fields before falling back. The
existing SNT/USB implementation remains unchanged.
