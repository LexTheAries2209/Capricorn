# smartmontools 7.5

Capricorn bundles the `smartctl` command from smartmontools 7.5. The source
archive is the upstream `RELEASE_7_5` GitHub tag and is kept here so every
Capricorn build can be traced to an exact source snapshot.

- Upstream: https://github.com/smartmontools/smartmontools/tree/RELEASE_7_5
- Source archive: `smartmontools-7.5.tar.gz`
- SHA-256: `ef721052992f2f6a57b369da625abd8dc30417e7a1e7234857619f8fc43fd4bc`
- License: GNU GPL version 2 or later

The application embeds only `smartctl` and `drivedb.h`. It does not embed or
start `smartd`, and it does not install anything outside the application
bundle.
