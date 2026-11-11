# SNT diagnostics visibility

## Current display gate

By default, `SmartAttributesView` requires the saved SMART diagnostics preference and
`SmartDiagnosticsVisibilityPolicy.showsPanel`. The policy excludes system and
network disks and requires at least one attribute whose source equals
`smartctl`, ignoring case.

Raw USB SNT snapshots use `Darwin Raw USB (Experimental)` as their provider and
attribute source. Their capture timestamp has another source. Neither matches
the policy, so the whole panel containing self-tests and error logs is hidden,
even after a successful SNT health read.

`showsSelfTestPanel` also explicitly excludes SNT providers and transports,
including snapshots with mixed attribute sources.

## Command boundary

`USBRawSmartService` and the helper's `readSNT` operation only request
`-i -H -A --json=c`. They do not retrieve error-log details or self-test history
and do not start or abort self-tests.

`SmartSelfTestService` and `SmartErrorLogService` use the ordinary bundled
smartctl executable and its target resolver. They do not reuse raw USB capture.
Self-tests also explicitly reject native NVMe, ASMedia NVMe and Realtek NVMe
transports on macOS; the ordinary JMicron path has a separate passthrough test.
A successful raw SNT health read is therefore not evidence that either
diagnostic operation is supported.

## Settings change

The error entry reader now lives under Developer Options and defaults off.
Displaying it requires developer options, the error reader preference, and
the existing SMART diagnostics preference. Turning developer options off
preserves the saved error reader choice but hides the tools.

This change leaves SNT panel admission and command routing unchanged.
Validation uses simulated SNT results and commands, without physical capture.

## Self-test display override

Developer Options contains `Always show SMART self-tests`, defaulting off.
With developer options and this override enabled, the self-test panel bypasses
the ordinary diagnostics switch, source and disk-type display filters.
Actual SMART data or a verified health result is still required; inventory-only
status text such as `Not Supported` is insufficient. SNT disks remain excluded.

This overrides presentation only. Command support, confirmation, system-disk
and other operation restrictions remain unchanged. The error entry reader
still requires the original diagnostics switch and ordinary eligibility.
Disabling developer options suspends the override without clearing its saved
choice; resetting all settings restores it to off.

## Verification

For the error-reader settings change, the signed Debug build and 19 focused
tests passed, covering settings defaults,
persistence, reset, visibility, SNT admission and existing bridge restrictions.
Two older screen-capture tests skipped because Screen Recording access was
unavailable. A new cached-view rendering test verified the developer option in
English and Chinese without that permission; both images were also inspected.

The subsequent self-test display override passed 22 focused tests with no
failures; two older screen-capture tests again skipped without Screen Recording
access. Policy tests cover all drive kinds, default behavior, missing data,
verified health-only results, and SNT exclusions. Cached-view rendering tests
verify both languages, the developer master switch, the independent diagnostics
switch and the unchanged error-reader visibility.
