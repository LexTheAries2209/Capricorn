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

Only the confirmed manual SNT workflow may invoke raw capture. Passive discovery
uses `--scan -d usb --json=c`, never `--scan-open`. An unsupported or ambiguous
device is refused; no forced unmount, self-test, or firmware operation is used.

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
