# Build artifact quarantine, 2026-10-28

The user requested moving the reviewed cleanup candidates into the project-root
`trush/` directory. No files were deleted. All moves used same-filesystem rename
and preserved the original project-relative directory structure.

## Results

271 selected files or directory roots were moved, accounting for approximately
31.10 GiB of allocated space reported by `du`. Moving within the same filesystem
does not free disk space. APFS clones and snapshots can also affect the space
eventually recovered by deletion.

| Category | Selected roots | Allocated KiB before move |
| --- | ---: | ---: |
| Build caches inside old source snapshots | 47 | 19065352 |
| Two discarded archive snapshot directories | 2 | 3788560 |
| Historical version directories in root DerivedData | 18 | 4501212 |
| Temporary historical build directories | 7 | 2819120 |
| Temporary Sparkle archive build directory | 1 | 337436 |
| Historical release xcresult reports | 6 | 1999996 |
| Historical Sparkle validation xcarchive | 1 | 86720 |
| Temporary interface preview applications | 15 | 3720 |
| smartctl intermediate build outputs | 1 | 4936 |
| Personal Xcode state directories | 2 | 320 |
| Standalone Finder metadata files | 171 | 1824 |

Directory entries include all their descendants; they are not counted again.
The earlier inspection's shell glob total for version-named DerivedData
directories counted `Release-v2.6.3` twice. The move manifest contains each
selected path once.

After the move, old-version archives occupy approximately 1.49 GiB, root
DerivedData occupies 1.89 GiB, and tmp occupies 0.18 GiB.

## Retained

- Existing tracked and untracked source changes, tests, and host-port review tools.
- Current shared DerivedData directories, including HostPortReview.
- Archived release apps, source code, release assets, and verification records.
- Temporary source scripts and investigation records not approved for removal.
- Sparkle command-line tools and their symbols.
- Bundled resources, third-party source archive, and license notices.

## Verification And Recovery

`trush/manifest.json` records every original and destination path, reason,
allocated size, device, inode, and move completion status.
`trush/quarantine_artifacts.py` preserves the exact selection and move procedure.
Both are intentionally local and excluded from Git with `trush/`.

All 271 selected roots were verified at their destination with the same device
and inode, and absent from their original location. No content hashes were
calculated. The preflight rejected any selection containing Git-tracked files.

To restore an item, use its manifest entry to move it from the destination to
the original path, first checking that the original path has not been recreated.
Do not overwrite newly generated files.

No application code changed and no application build or tests were run for
this filesystem-only operation.
