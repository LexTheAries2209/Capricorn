# SNT busy-unmount handling

The reported SanDisk Portable SSD attempt failed with
`whole-disk unmount failed (0x0000c010)`, before USB capture or SMART reads.
This is `unix_err(EBUSY)`. Authorization succeeded, and the original volume
mount was confirmed afterward. The report does not identify the process
responsible for the busy response; reconnecting and retrying succeeded.

## Unmount retries

The bundled raw USB tool is now identified as `capricorn4`.

- Retry only completed `unix_err(EBUSY)` and `kDAReturnBusy` responses.
- Allow three attempts total per whole disk, with one- and two-second delays.
- Retain the original mount list and ordinary, non-forced unmount options.
- Before each attempt, verify the original media and USB registry IDs.
- Stop on timeouts, changed identity and other failures.
- Record each attempt with `CAPRICORN_USBRAW_UNMOUNT` and terminal busy
  exhaustion with `CAPRICORN_USBRAW_UNMOUNT_BUSY`.

The application stops protocol probing after any failure before capture.
Selecting another bridge cannot resolve an unmount failure and must not
multiply the retry count.

## Occupying processes

After a terminal busy failure with confirmed mount restoration, the application
reuses `DiskOpenFileService` for every distinct mounted volume on that disk.
It verifies the USB target before each query, limits each query to five seconds
and the aggregate query budget to ten seconds, and deduplicates summary
processes by PID. When a previous protocol re-enumerated the disk, it uses the
updated drive's mounts and USB target.

The result shows:

> 磁盘可能正在被占用，无法卸载，请关闭正在使用该磁盘的程序后重试。
>
> 占用的程序可能是：Finder（PID：123）

The first reported process is a clue, not proof that it caused the refusal.
An empty result says that the process could not be identified; a failed query
says that process information is temporarily unavailable. A partial query
failure does not hide a process found on another volume. Restoration warnings
take priority and are never replaced with busy guidance.

All per-volume file records and query errors are retained as JSON under
`CAPRICORN_USBRAW_OPEN_FILES` in the existing diagnostic output. No buttons,
process termination or forced unmounting are added.

## Validation

- Universal arm64/x86_64 tool build and signature verification passed.
- Native backend `make -C lib check`: all three test programs passed, including
  retry success, exhaustion, non-busy errors, unfinished timeout and
  identity-change cases.
- Focused Xcode tests: 50 SNT tests and two existing open-file parser/service
  tests passed, with zero failures.
- Inspected rendered English and Chinese busy-result windows; both retain
  the existing Close button and diagnostic disclosure.
- Certificate-backed `script/build_and_run.sh --verify` passed.
- No physical USB disk is unmounted by these automated tests. Reproducing the
  original SanDisk busy state remains a hardware acceptance check.

The default XCTest launch stalled in dyld while opening the build-products
Sparkle framework, before connecting to the test runner. The original cache
was preserved in a temporary abandoned directory. Tests passed using the
one-run `TEST_RUNNER_DYLD_FRAMEWORK_PATH` environment override pointing to the
application's embedded frameworks and Xcode's framework directories. No
project build settings or signing configuration were changed.
