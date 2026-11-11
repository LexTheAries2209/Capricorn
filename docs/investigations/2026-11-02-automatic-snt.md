# Automatic SNT

The separate automatic SNT queue is opt-in and does not display the manual
confirmation sheet. It runs after a complete ordinary scan, on launch,
connection, or enabling the preference. A two-second settling delay coalesces
inventory changes. Capture-induced re-enumeration retains its connection token.
Ordinary periodic refresh does not repeat a completed connection's SNT read.

## Admission and ownership

- Read-only media and disks containing any read-only volume are excluded from
  automatic SNT, including CODEX UDF cards. The queue rechecks before dispatch,
  and the service rechecks after re-enumeration before another bridge probe.
  This skip does not consume retries or persist a failure; manual SNT remains
  available with confirmation.
- The privileged service must be enabled and pass its version/installation
  handshake. Automatic requests carry typed consent distinct from manual
  unmount confirmation; helper protocol version 3 rejects mismatched clients.
- The automatic path checks mounted-volume accessibility with `access`, and
  never calls the manual directory-enumeration authorization function.
- Every distinct mounted volume is checked with bounded `lsof`. Diagnostics,
  unusual exit codes and unparseable output are unknown occupancy, not idle.
  A final target check precedes the request. Native unmount remains non-forced.
- Existing app task conflicts and the cross-process disk lease prevent
  overlapping work. Capture workers retain ownership of cleanup independently
  of the GUI's lifetime.

## Results and retry policy

Busy, incomplete occupancy, missing authorization and identity changes defer
without consuming a read failure. Occupancy is checked again after 30 seconds.
Actual recoverable reads retry after 30 seconds and two minutes, stopping after
three consecutive failures. A completed unsuccessful probe of all three bridge
protocols stops immediately, rather than repeating three whole probe rounds.

An exclusion survives reconnect/relaunch. A successful manual read with
confirmed restoration overwrites the exclusion and resets failures. Unknown
restoration pauses automatic operation immediately; manual recovery is required.
An unfinished marker is persisted before dispatch to cover GUI interruption.

There is one replaceable record for each bridge/media identity, containing the
current conclusion, retry budget, last protocol, latest diagnostics and last
valid snapshot. Exact reading timestamps survive cache encoding. Volume UUIDs
distinguish media sharing an enclosure serial; the existing narrow CODEX name
identity is also supported. Other UUID-less media use connection-local records.
Ambiguous persistent identities are excluded from automatic admission.

## Validation boundary

Tests use simulated inventories, commands and SNT results. UI tests render
English and Chinese controls. They never unmount or capture physical disks.
Real-device acceptance must cover authorized and revoked removable-volume
access, permission prompts, system-wide occupancy visibility, copying during
admission, unplugging during capture, multiple volumes, and mount restoration.
The accessibility precheck is not a public TCC authorization-status API; prompt
behavior after permission changes must be checked on supported macOS versions.

## Local verification

- Certificate-backed Xcode regression run: 124 tests, zero failures, covering
  automatic SNT, caching, settings rendering, existing manual SNT, helper
  lifecycle, update safety, response validation and target identity.
- A subsequent focused queue run passed all eight tests, including the added
  disappearing-target case. Together these runs exercise 125 distinct tests.
- English and Chinese settings/status renderings were visually inspected.
- `./script/build_and_run.sh --verify` built and launched the signed Debug app.
- `codesign --verify --deep --strict` passed for the complete app, including
  the certificate-signed helper and both SMART tools.
- The automatic-read preference remains off. No physical USB capture, volume
  unmount, helper re-registration, or hardware self-test was performed.

The helper protocol changed from 2 to 3. An existing installed helper must pass
the new handshake; when the app reports an installation/version mismatch,
re-enable the privileged device service in Settings before using automatic SNT.
