# Device Service Location And Updates

Branch: `codex/privileged-device-helper`

## Locations

`DeviceHelperLocation` replaces the `/Applications` parent-directory check.
It resolves the app's actual path and checks volume attributes. A complete,
correctly signed app can enable its service in a permanent directory on a
local, writable, non-removable disk. Examples include `/Applications`,
`~/Applications`, a user tools folder, or the desktop.

Read-only disk images, removable/ejectable or network volumes, system app
translocation paths, and temporary roots (`/tmp`, `/var/tmp`, `/var/folders`
and their `/private` aliases) are rejected. `/Applications` remains the
recommended location because a boot-time daemon needs its bundle available
before user login. No installer or signing checks are bypassed.

Changing folders is not equivalent to preserving a running process's source
path. Move an enabled app only after disabling its service, then re-enable
from the new location. Connection identity includes the signed build, so
different copies with different signatures cannot silently share stale
workers. Manual replacement still requires safe stop; automatic coordination
applies to in-app Sparkle installation.

## Update Transaction

An enabled service no longer blocks metadata checks or downloads. The service
is prepared only after installation is actually requested:

1. Check disk-task conflicts, reserve installation and save history.
2. Write an update journal containing the signing team and preparing phase.
3. Ask the authenticated root service for an idle stop reservation.
4. Await `SMAppService.unregister()` completion, then record the stopped phase.
5. Only then reply `.install` to Sparkle or invoke its relaunch handler.
6. At next startup, the replacement app verifies its location and signature,
   restores the previously enabled service, and checks the new XPC connection.

The existing daemon gate refuses stop while a worker is active, including
raw USB capture and mount restoration. Disk tasks remain blocked while the
installation reservation is held. A failed or busy preparation blocks
installation; it does not force-stop a worker or silently retry installation.

Settings use the same observable service manager as the update coordinator.
Service buttons are disabled during prepared installation, preparation and
restoration. A manual enable/disable already in progress is also treated as
requiring installation preparation, avoiding the unregister completion window.

## Approval And Recovery

The journal is stored under `deviceHelper.pendingUpdateRestoration` in the
app's preferences. It stores no password or authorization token. It is
written before the first asynchronous stop call and synchronized only at
transaction boundaries.

- An app that never enabled the service does not create a journal or enable it
  during update. Existing `requiresApproval` also does not count as enabled.
- Cancellation during preparation invalidates the pending installer reply;
  late completion can restore service but cannot switch the reply back to
  installation.
- Cancellation, an installer error, or failure of a final save/conflict check
  triggers restoration in the running app.
- If the app exits or crashes first, the next launch reads the journal. A
  preparing journal with a still-enabled service releases its idle stop
  reservation. A stopped/unregistered service is registered again.
- Restoration runs even if automatic version checks are disabled; it does not
  enable network checks.
- System `requiresApproval` takes priority. The journal is consumed and the
  settings section explains that user approval is needed; it is not repeatedly
  registered or automatically approved.
- A changed signing team cannot consume another team's update intent.
- A failed connection check retains the journal for a later retry. Explicit
  successful disable clears it, preventing a later launch from undoing that
  choice. Stop-cancellation failures retain recovery information as well.

The expected result is automatic service continuity when macOS retains consent.
It is not a guarantee that a different macOS version, changed signature,
changed service policy or user revocation will never require authentication.
The first upgrade from an older Capricorn without this transaction code still
uses that older version's manual stop procedure.

## Connection Identity

The XPC protocol is version 2. After mutual code-signing authentication, the
client checks both protocol version and the code-signature identity of the app
containing the service at its startup. The latter is captured once, before
listening, and compared with the requesting client's expected app bundle.
It reads the existing code-signing identity rather than hashing app files.

This check also detects UI-only app replacements that retain the same displayed
version/build but have a different code seal. The client fails before sending
a disk request if an older root process is still associated with another build.
The existing stop control remains callable while migrating from protocol 1.
No arbitrary command, path or process-control API is added to XPC.

## Validation

Final validation on 2026-11-01: **688 tests, 9 skipped, 0 failures**.
The skips are the existing environment-dependent cases and the explicit
hardware test. The Release configuration built for arm64 and x86_64; the app
and helper architectures were inspected and the app passed strict nested
signature verification. This is an Apple Development-signed local build,
not a notarized distribution release.

Focused tests cover location restrictions, real local-volume attribute access,
busy workers, stop cancellation, durable journal recovery, signing-team changes,
revoked approval, new approval requirements, restoration retries, manual disable,
deferred Sparkle replies, late cancellation, installer failure, final conflict
checks and startup recovery with automatic update checks disabled.

The real Sparkle fixture scenario `device-service-update` downloads a locally
signed build 0042, awaits an asynchronous service preparation, replaces build
0041 and relaunches. It verified service-stop evidence before replacement,
restoration in the new process, and retained history/preferences. The fixture
uses the production updater/driver with a **mock service coordinator**; it does
not simulate system consent as a successful real daemon authorization.

```sh
python3 scripts/test-sparkle-update.py \
  --sparkle-root DerivedData/SourcePackages/artifacts/sparkle/Sparkle \
  --scenario device-service-update
```

The successful fixture run retained its evidence under
`~/Library/Caches/CapricornUpdateFixtures/sparkle-device-service-update-s66tfmiu`.

Real installed root SMART/log reads and non-app client rejection were previously
verified, as recorded in the service document. A real Developer ID/notarized
old-to-new update across machines/macOS versions, moved-app registration and
renewed authorization behavior still require distribution acceptance testing.
No GitHub release is published by this implementation.

For an opt-in hardware test launched from a separate Debug host, set
`TEST_RUNNER_CAPRICORN_HELPER_TEST_BUNDLE` to the installed app whose service
is being tested, in addition to the existing explicit disk/type variables.
The test remains read-only and skipped by default; it does not capture USB
or start a self-test. SNT's existing manual unmount confirmation is unchanged.
