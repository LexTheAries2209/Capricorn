# SNT diagnostics visibility

## Current display gate

`SmartAttributesView` requires the saved SMART diagnostics preference and
`SmartDiagnosticsVisibilityPolicy.showsPanel`. The policy excludes system and
network disks and requires at least one attribute whose source equals
`smartctl`, ignoring case.

Raw USB SNT snapshots use `Darwin Raw USB (Experimental)` as their provider and
attribute source. Their capture timestamp has another source. Neither matches
the policy, so the whole panel containing self-tests and error logs is hidden,
even after a successful SNT health read.

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

## Verification

The signed Debug build and 19 focused tests passed, covering settings defaults,
persistence, reset, visibility, SNT admission and existing bridge restrictions.
Two older screen-capture tests skipped because Screen Recording access was
unavailable. A new cached-view rendering test verified the developer option in
English and Chinese without that permission; both images were also inspected.
