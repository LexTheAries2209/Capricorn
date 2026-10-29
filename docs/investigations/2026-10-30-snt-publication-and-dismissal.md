# SNT Publication And Sheet Dismissal

## Missing SMART After Successful Read

The user's 00:18:24 screenshot showed successful SMART/volume restoration but
no attributes on the selected ASMedia disk. The earlier refresh-retention fix
did not cover a separate identity ambiguity when more disks were attached.

A read-only probe using the application's actual inventory provider found:

| Physical disk | User data volume UUID | EFI filesystem UUID |
| --- | --- | --- |
| ASMT 2462 NVME Media (`disk6`, no serial) | `7D9E2270-0778-4D7D-9212-697D6AB4022D` | `0E239BC6-F960-3107-89CF-1C97F78BB46B` |
| GeIL P4S 4TB (`disk14`) | `CF64F70E-C347-4668-85A2-9B2691AF499A` | `0E239BC6-F960-3107-89CF-1C97F78BB46B` |

The previous matcher considered any shared volume UUID sufficient when one
disk lacked a serial. It therefore matched the ASMedia disk to both physical
disks. SNT correctly refused to assign the reading to an ambiguous identity,
but its completion message did not explain the failed publication.

Commit `f822846` restricts fallback identity matching to user data volumes.
EFI partitions, including mounted FAT32 EFI partitions, APFS auxiliary volumes
and container backing stores do not establish identity. Serial checks and the
requirement for a unique match remain. Stored UUID metadata and exported
history are unchanged. A successful raw read that cannot be published now
shows an explicit bilingual explanation and retains its diagnostic output.

The regression test uses the real UUID relationship above. It failed before
the change and passes after it, including an ordinary refresh following result
publication. A subsequent read-only probe of all four attached disks reported
`disk6 -> [disk6]` and `disk14 -> [disk14]`. The unrelated UDF device, which has
neither a serial nor a data-volume UUID, correctly remains unmatchable.

## White Rectangle On Close

The SNT sheet used `usbRawSmartSession != nil` as its presentation flag, while
its body also depended on that session. Clicking Close cleared the session
before the native sheet's closing animation finished. The fixed-size body
became empty and collapsed.

This was reproduced in a hosted result-sheet test: its fitting height changed
from 362 to 0 immediately after Close. Commit `d0a7276` separates presentation
from session lifetime. Close changes the presentation flag; `onDismiss` clears
the session only after the sheet has closed. A running read still prevents
closing. Stale dismissal callbacks cannot clear a newly presented session.

The test now verifies that the result contents and fitting height survive
Close, and that cleanup happens only when dismissal completes.

## Validation

All 24 focused SNT tests passed after both changes. The complete application
suite passed 625 tests with 8 existing environment-dependent skips and no
failures. The signed Debug application was rebuilt and launched through
`script/build_and_run.sh --verify`.

A fresh SNT attempt was started from the ASMedia disk's context menu with all
four disks attached. It is awaiting the user's native administrator
authentication at 00:47 CST; no successful hardware outcome is claimed for
this follow-up until the live validation is complete.
