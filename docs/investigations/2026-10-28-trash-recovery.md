# Trash recovery and artifact quarantine, 2026-10-28

The user requested restoring all four previously inspected Trash folders,
moving only unneeded contents into `trush/`, and retaining useful material.
Finder's Put Back command restored each folder to its recorded original path.
Finder subsequently showed no remaining Trash items.

## Restored Locations

| Folder | Original project-relative location |
| --- | --- |
| Capricorn-main-ui-fix | Capricorn旧版软件/Capricorn-main-ui-fix |
| Discarded | Capricorn旧版软件/Discarded |
| output | output |
| release-v2.9.8 | tmp/release-v2.9.8 |

The separate, pre-existing empty root `Discarded/` directory was retained.

## Retained Material

- The complete clean `Capricorn-main-ui-fix` Git worktree.
- Its nested `Capricorn旧版软件/Capricorn V2.8.1/` release App, source snapshot,
  and README. No separate top-level V2.8.1 archive was substituted or overwritten.
- Both V2.7.6 backups under `Capricorn旧版软件/Discarded/`, including their Apps,
  source snapshots, README, ZIP, and Xcode archive with debugging symbols.
- The V2.9.5 README and release-note drafts.
- PDF generation and spreadsheet inspection source scripts.
- Both PDFs and the October 19 cleanup inventories in `output/`.
- V2.11.0 release JSON records, signing and verification logs, existing digest
  records, notes, and Sparkle tool symlinks in `output/release-v2.11.0/`.

After organization, the retained worktree occupies approximately 37.43 MiB,
retained `Capricorn旧版软件/Discarded/` occupies 132.94 MiB, and retained `output/`
occupies 1.94 MiB, as reported by `du`.

## Quarantined Material

40 selected file or directory roots, approximately 6.34 GiB, were renamed into
`trush/restore-20261028/data/` with their original relative paths preserved.

| Material | Approximate GiB |
| --- | ---: |
| Historical V2.9.2 DerivedData caches | 2.685 |
| Historical V2.9.3 release build directories | 1.133 |
| Historical V2.9.8 build directory, test result and logs | 1.325 |
| Four V2.11.0 DerivedData directories | 1.187 |
| Generated PDF previews, bytecode, profiling outputs and metadata | 0.008 |

The V2.9.8 directory was first restored, inspected, and then moved in its entirety
because its contents were build outputs, a test result, and temporary logs.
It contained no standalone release source snapshot or distribution archive.
The restored V2.7.6 `.xcarchive` was preserved as a release artifact.

## Verification And Recovery

The local, ignored `trush/restore-20261028/manifest.json` records the four restored
locations, every quarantine move and its reason, and a baseline inventory of
1,067 retained filesystem entries. All retained entries remained present with
unchanged device, inode, and type. File sizes and modification times were also
unchanged; parent directory size and modification time changes from moving
children were expected and excluded.

All 40 moved roots were verified at their destination with the same recorded
metadata and absent from their source path. The worktree remained clean.
The primary project's pre-existing source and test edits were left untouched.
No content hashes were calculated and no file contents were deleted.
Moving within the same filesystem does not release disk space.

The exact procedure is saved in the ignored
`trush/restore-20261028/organize_restored.py`. Use the manifest's original and
destination paths for any later restoration, checking for newly created paths
before moving an item back. Never overwrite a recreated original path.

This operation changed filesystem organization only. No application build or
tests were run.
