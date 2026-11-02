# APFS Physical-Target Ambiguity

## Reproduction

The user reported "The SMART target does not identify exactly one physical
disk" while attempting SNT with one ASMT 2462 NVMe USB enclosure attached.
The screenshot identifies physical disk `disk6`, the APFS volume
`40G4T_APFS_D`, and Capricorn V3.1.2.

A read-only probe compiled against the V3.1.2 resolver reproduced the exact
error on the currently connected device:

```text
RESOLVED disk6 media=4297778613 usb=4297778448 bytes=4096805658624
TARGET_ERROR disk6: The SMART target does not identify exactly one physical disk.
RESOLVED disk7 media=4297778628 usb=4297778448 bytes=4096594542592
TARGET_ERROR disk7: The SMART target does not identify exactly one physical disk.
```

`diskutil list` identifies `disk6` as external physical storage and `disk7`
as its synthesized APFS container, backed by `disk6s2`. IORegistry confirms:

```text
disk7 (AppleAPFSMedia, Whole=true)
  AppleAPFSContainerScheme
    disk6s2 (IOMedia, Whole=false)
      IOGUIDPartitionScheme
        disk6 (IOMedia, Whole=true)
          IOBlockStorageDriver
            IOSATServices (conforms to IOBlockStorageDevice)
              ...
                USB storage device
                  upstream USB hub
```

## Root Cause

`DeviceHelperDeviceResolver.resolve` accepted a whole `diskN` whenever any
ancestor conformed to `IOBlockStorageDevice`. APFS synthesized whole media
inherit a path to that same physical ancestor. The enumeration in
`disk(forTarget:)` therefore accepted both `disk6` and `disk7` and matched both
to one USB registry ID. The correct unique-target refusal was being applied
to an incorrect candidate list.

This is unrelated to the number of external disks connected, and occurs
before the smartctl worker is started. No unmount, USB capture or SMART command
is required to reproduce it. It can affect both USB SNT targets and ordinary
IOService SMART targets.

Previous fixes addressed separate defects: selecting the nearest storage USB
device instead of an upstream hub, exact BSD-name matching instead of prefix
matching, and bounded busy-unmount retries. They did not change the helper's
physical-media classification. Earlier tests did not include an APFS
synthesized whole disk in the helper's candidate registry tree.

The bundled raw USB backend already checks the immediate block-storage
provider in its physical-only enumeration. The helper's independent earlier
check used the weaker ancestor criterion, rejecting the request before the
backend's correct classification could run.

## Correction

- Require whole IOMedia provided directly by an `IOBlockStorageDriver`,
  including subclasses, as well as a physical storage-device ancestor.
- Exclude file-backed and explicitly virtual storage interfaces. Disk images
  can also have whole IOMedia and a block-storage driver.
- Use this classification in both client-side target resolution and the
  privileged service's pre-execution disk revalidation.
- Preserve the nearest USB identity, registry IDs, capacity verification and
  true multi-physical-disk refusal. Never select the first candidate merely
  because the user connected one enclosure.
- Distinguish no matching physical disk from multiple matching physical disks
  in both English and Chinese.

The registry API boundary is injectable so fixture trees exercise the actual
resolver, including candidate enumeration and balanced retain/release handling.
Fixtures cover APFS containers and volumes, multiple containers on one disk,
two real disks behind one USB identity, unrelated USB storage, upstream hubs,
internal storage, block-driver subclasses, disk images and incomplete trees.

## Evidence And Limits

The corrected read-only probe on the same connected hardware reports:

```text
RESOLVED disk6 media=4297778613 usb=4297778448 bytes=4096805658624
TARGET_MATCH disk6 -> disk6
TRANSPORT_MATCH disk6 -> disk6
RESOLVE_ERROR disk7: Virtual and synthesized disks are not allowed.
RESOLVED disk0 media=4294970118 usb=nil bytes=1000555581440
TRANSPORT_MATCH disk0 -> disk0
RESOLVE_ERROR disk3: Virtual and synthesized disks are not allowed.
RESOLVE_ERROR disk4: Virtual and synthesized disks are not allowed.
```

`disk4` is an existing simulator disk image; it was inspected without changing
its mount state. The user's external USB disk also passed a read-only
USB/IOService identity check through its upstream hub. Hardware identity probes
do not establish SNT command compatibility or successful SMART reads.

No real SNT capture, unmount, self-test, driver configuration change or history
cleanup was performed. The published V3.1.2 artifacts remain unchanged. Both
the application and bundled helper must be rebuilt to use the corrected shared
resolver; installation/service lifecycle checks still apply.

Validation:

- Full suite: 721 tests, 719 passed, two skipped, zero failures. The skips are
  the opt-in privileged SMART hardware-operation test and the certificate-only
  check on the unsigned XCTest host.
- Eight fixture-tree regressions passed; every exercised retain/release path
  balanced its registry references.
- The strengthened hardware identity test passed on `disk6` through its USB
  hub, confirming both USB and IOService round trips and exclusion of `disk7`.
  Its final focused run, including all eight fixture tests, passed nine tests
  with no skips or failures.
- Strict concurrency with warnings treated as errors passed.
- Swift 6 compatibility passed, retaining existing C-string deprecation
  warnings elsewhere in the project.
- Certificate-backed `script/build_and_run.sh --verify` passed.
- `git diff --check` passed.

Read-only probes and validation logs are retained locally under
`~/Library/Caches/CapricornDiskIdentityFix/`.
