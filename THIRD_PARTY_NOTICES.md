# Third-Party Notices

## smartmontools 7.5

Capricorn includes the `smartctl` executable and `drivedb.h` from smartmontools
7.5. It does not include `smartd` or any SAT SMART Driver component.

- Project: <https://www.smartmontools.org/>
- Source archive: `ThirdParty/smartmontools/smartmontools-7.5.tar.gz`
- Source SHA-256: `ef721052992f2f6a57b369da625abd8dc30417e7a1e7234857619f8fc43fd4bc`
- License: GPL-2.0-or-later; the complete license text is at
  `ThirdParty/smartmontools/COPYING` and in the App resource bundle.
- Corresponding source and reproducible build instructions:
  `ThirdParty/smartmontools/README.md` and `scripts/build-smartctl.sh`.

The source is retained without source-code modifications. The build script configures
and combines separate arm64 and x86_64 `smartctl` binaries, then copies `drivedb.h`
into the App resource bundle. The resulting universal binary and database are checked
by `scripts/verify-smartctl-bundle.sh`.

When distributing a Capricorn binary that contains these resources, distribute the
corresponding source archive, build script, license, and this notice with that binary
or provide the complete corresponding source as required by GPL-2.0-or-later.
