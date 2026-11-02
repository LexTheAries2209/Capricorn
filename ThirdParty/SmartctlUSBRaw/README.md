# Experimental Darwin raw USB smartctl

This component is separate from the production smartctl 7.5 executable.
It is based on smartmontools PR #639 at the immutable commit
`c68a1b9af76ba9ca3a2e987def6384377f73a4b8`:

https://github.com/smartmontools/smartmontools/pull/639

`smartmontools-c68a1b9.tar.gz` contains the corresponding upstream Git tree,
including its GPL-2.0-or-later COPYING file. `capricorn-manual.patch` records
the complete local changes: capture requires `CAPRICORN_USBRAW_MANUAL=1` and
an explicit `usbraw:` selector; lifecycle events are emitted to stderr.
Before unmounting, the tool verifies root credentials, the requesting user's
audit identity, and read-only access to the physical raw-device node. It does
not read device bytes during this authorization check. The diagnostic command
`--capricorn-usb-preflight usbraw:ID` runs only those checks, without capture.
Events are diagnostic evidence, not proof of hardware compatibility.

Build both architectures with `sh scripts/build-smartctl-usbraw.sh`.
Build prerequisites include Xcode Command Line Tools, autoconf, automake, and
GNU libtool (`brew install autoconf automake libtool`).
The output is `Capricorn/Resources/Smartmontools/smartctl-usbraw`, with an ad-hoc
build signature and stable identifier `lex.Capricorn.smartctl-usbraw`.
Xcode's **Embed SNT Executable** phase copies it into `Contents/MacOS` and
signs it with the application's configured signing identity. Do not run the
privileged application workflow against the source-tree copy or an old
`Contents/Resources` copy: those do not have the intended nested-code identity.
The normal
smartctl executable and its automatic scans remain unchanged.
`dist-version.sh` embeds the pinned revision and Capricorn patch identifier;
the source snapshot does not contain the upstream Git ancestry.

Only a confirmed manual SNT workflow or an explicitly enabled automatic SNT
workflow may invoke raw capture. The signed app sends distinct typed XPC consent
for these operations; the service translates either into the native tool's
legacy `CAPRICORN_USBRAW_MANUAL=1` capture gate. Passive discovery
uses `--scan -d usb --json=c`, never `--scan-open`. An unsupported or ambiguous
device is refused; no forced unmount, self-test, or firmware operation is used.

The application uses a recognized SNT type from passive discovery directly.
An unknown/SAT type triggers JMicron, ASMedia and Realtek protocol attempts
within the confirmed manual operation. Each attempt uses this same tool and
finishes release and restoration before another can begin; the application
re-enumerates and verifies a unique stable device identity and fresh USB target
between attempts. It stops at a SMART payload or uncertain restoration.
Ordinary periodic SMART refresh never starts this sequence. The separate,
opt-in automatic SNT queue runs once on app launch or physical connection,
checks service readiness and mounted-volume access without invoking the manual
volume authorization function, and checks all mounted volumes for open files
before each protocol. Unknown or incomplete occupancy defers capture. A
successful cached protocol is preferred. Three retryable read failures or one
complete unsuccessful three-protocol probe pause automatic attempts; busy
responses do not consume that budget. Cleanup uncertainty also pauses the
device. A successful manual read replaces its cached conclusion. The app
records an unfinished-operation marker before dispatch, so an interrupted GUI
cannot silently assume mount restoration completed on its next launch.

Patch `capricorn4` retries a completed whole-disk unmount busy response
(`unix_err(EBUSY)` or `kDAReturnBusy`) at most twice, after one and two seconds.
Each attempt revalidates the original media registry ID and USB registry ID.
Timeouts, identity changes and other errors stop immediately. All attempts
retain the original mount list and use ordinary, non-forced unmounting.
`CAPRICORN_USBRAW_UNMOUNT` records each attempt and status;
`CAPRICORN_USBRAW_UNMOUNT_BUSY` marks an exhausted busy failure.

Patch `capricorn3` adds a user-authorized mount-identity exception for CODEX
Compact Drive media when Disk Arbitration supplies neither a volume UUID nor
a media UUID. It requires USB VID/PID `2818:0012`, a reader serial and location,
whole-media UDF, and the exact media name `CODEX COMPACT DRIVE Media`. The
original volume name, physical capacity and block size are recorded before
unmounting. Restoration requires the same USB identity and a unique matching
volume; a missing or ambiguous match is refused. Other UUID-less media keep
the existing refusal. The application uses the corresponding narrow name
identity when publishing and retaining the SMART result.

`--capricorn-usb-mount-preflight usbraw:ID` checks mount-identity eligibility
without administrator credentials, unmounting, capture or device-byte reads.
For the CODEX exception it emits `CAPRICORN_USBRAW_CODEX_NAME` with the volume
name. Passing this check does not establish SNT command compatibility.
Chipset detection and vendor transport selection are unchanged.

The application first requests filesystem access to its selected mounted
volumes in the user's context. Its administrator command uses
`launchctl asuser <requesting UID>` while preserving root credentials and
sets `CAPRICORN_USBRAW_USER_UID` to that UID. The tool checks that the real
audit identity matches before touching mount state. `bsexec` was tested on
macOS 26.5 and left the process in the system audit session despite exiting
successfully; it is not used. No TCC database changes or private responsibility
APIs are part of this integration.

When redistributing this binary, include this corresponding source archive,
patch, build script, README, and license, or otherwise provide corresponding
source in accordance with GPL-2.0-or-later.
