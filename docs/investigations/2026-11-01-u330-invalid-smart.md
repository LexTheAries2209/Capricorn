# U330 Invalid SMART Responses

## Observations

The aigo U330 volume `声音U盘` intermittently displayed an escaped `\x01`
serial, unknown ATA attributes and implausible health indicators. After
reconnection it returned no SMART payload, including the user's manual SNT
attempt.

Independent read-only smartctl 7.5 queries to the same physical disk also
returned escaped binary identity fields or an empty model, with exit status
4 and no usable SMART data. An ATA ioctl trace reported successful IDENTIFY
completion but showed a 512-byte buffer starting with `USBC` and containing
directory-like bytes instead of coherent ATA identity information.

IORegistry showed SATSMARTDriver 0.10.3 attached to this U330, with
`SATSMARTCapable` enabled and the `jmicron` pass-through mode. These observations
establish an invalid response from the SAT path. They do not determine whether
the device firmware, driver, or their interaction supplied the incorrect bytes.
There was no evidence that the initial screenshot contained another disk's
coherent SMART record.

The appropriate state is **no verified SMART data through the current path**.
The earlier attributes and power-on hours are not a verified historical reading.
This does not prove that every firmware or command path for this device lacks
health information.

## Response Validation

The parser previously treated a nonempty attribute table as payload without
checking malformed identity fields or explicit SMART checksum errors. It could
also accept payload with a fatal exit status if smartctl supplied no message.

Snapshot, self-test capability and error-log parsing now reject binary identity
text and explicit SMART/IDENTIFY checksum failures. Empty reported models and
SMART payloads that contradict an explicit unsupported flag are rejected.
Fatal open/identify failures no longer require an accompanying message.
Dedicated capability/log requests reject command-failure bit 2.

Aggregate reads still accept valid partial results, real failed-health reports,
vendor-specific attribute names and large raw values. A nonzero exit status or
an unfamiliar attribute is not sufficient to reject a reading. Valid Native
macOS readings and earlier verified manual SNT readings survive a failed
ordinary transport.

Binary serials are excluded from inventory normalization, display and stable
identity matching. Previously cached snapshots with such serials cannot provide
health, serials or retained data during refresh, standby, Native retry or
manual-read retention. User history files are not rewritten.

## Target Selection

A separate review found a genuine wrong-target risk: scan selection used
substring matching, allowing `disk70` or `disk7s1` to match `disk7`.
Regression fixtures reproduced both cases before the fix. Target selection now
matches complete BSD names or path components, preserving exact device-node
and bare-BSD-name matches. This was an additional defect, not evidence that
it caused the U330 screenshot.

## Verification Boundaries

The response regressions cover the observed escaped identity patterns,
synthetic corrupted attribute payloads, checksum messages from JSON and stderr,
legacy cache retention, Native/SNT fallback, real failed health and valid
partial reads. The tests do not claim to reconstruct the complete raw response
behind the initial screenshot, which was unavailable.

No SNT capture, unmount, self-test start/abort, driver configuration change or
history cleanup was performed for these fixes. Applying them requires a newly
built application; published V3.1.0 artifacts remain unchanged.

Final validation: **705 tests, 10 skipped, 0 failures**. The skips comprise
eight Screen Recording-dependent checks and two opt-in hardware checks.
Strict concurrency with warnings treated as errors and Swift 6 compatibility
builds passed. Swift 6 retains existing C-string deprecation warnings.

The 13 response-validation regressions include negative and positive controls;
eight initially failed against the old implementation. Three target-selection
regressions cover exact selection, prefix/partition collisions and bare BSD
names; the collision cases failed before the matching fix.
