#!/usr/bin/env python3
"""Create and audit marked acceptance directories without deleting any files."""

import argparse
import datetime
import json
import os
import pathlib
import plistlib
import stat
import subprocess
import tempfile
import uuid

VOLUME = pathlib.Path("/Volumes/40G4T_NTFS_E")
VOLUME_UUID = "EC9303C9-933A-E6EC-BFEC-E6A4FFE6A4CA"
PURPOSE = "Capricorn AIO P0-P1 acceptance"


def snapshot():
    entries = {}
    errors = []

    def visit(folder):
        try:
            children = sorted(os.scandir(folder), key=lambda entry: entry.name)
        except OSError as error:
            errors.append({"path": str(folder.relative_to(VOLUME)), "error": str(error)})
            return
        for entry in children:
            try:
                value = entry.stat(follow_symlinks=False)
                entries[str(pathlib.Path(entry.path).relative_to(VOLUME))] = {
                    "kind": stat.S_IFMT(value.st_mode),
                    "size": value.st_size,
                    "mtime_ns": value.st_mtime_ns,
                    "inode": value.st_ino,
                }
                if entry.is_dir(follow_symlinks=False):
                    visit(pathlib.Path(entry.path))
            except OSError as error:
                errors.append({"path": entry.path, "error": str(error)})

    visit(VOLUME)
    return {"entries": entries, "errors": errors}


def volume_info():
    info = plistlib.loads(subprocess.check_output(["diskutil", "info", "-plist", str(VOLUME)]))
    if info.get("VolumeUUID") != VOLUME_UUID or not info.get("WritableVolume"):
        raise RuntimeError("E volume identity or write access changed")
    return info


def write_new(path, value):
    with path.open("x") as output:
        json.dump(value, output, ensure_ascii=False, indent=2)


def prepare():
    info = volume_info()
    if info["FreeSpace"] < 40 * 1024**3:
        raise RuntimeError("Less than 40 GiB free; no tests started")
    identity = "Capricorn-AIO-P0P1-20261019-" + uuid.uuid4().hex[:8]
    local = pathlib.Path.home() / "Desktop" / identity
    local.mkdir()
    write_new(local / "existing-before.json", snapshot())
    root = VOLUME / identity
    root.mkdir()
    marker = {
        "purpose": PURPOSE,
        "root": str(root),
        "volume_uuid": VOLUME_UUID,
        "local_artifacts": str(local),
        "created_at": datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
        "existing_free_bytes": info["FreeSpace"],
        "cleanup_policy": "Retain all artifacts. No deletion is authorized by this manifest.",
        "previous_task_artifacts": [
            "/Volumes/40G4T_NTFS_E/Capricorn-AIO-20261018-6032b33b",
            "/Users/lex./Desktop/Capricorn-AIO-20261018-6032b33b",
        ],
        "other_generated_locations": [
            "/Users/lex./Desktop/XcodeProjects/Capricorn/DerivedData",
            "/tmp/capricorn-aio-build-20261019.log",
            "/tmp/capricorn-aio-unit-20261019.log",
            "/tmp/capricorn-aio-unit-v2-20261019.log",
            "/tmp/capricorn-aio-acceptance-local-20261019.log",
            str(pathlib.Path(tempfile.gettempdir()) / "Capricorn-AIO-*") + " (inspect each marker)",
        ],
    }
    write_new(root / "CAPRICORN_TEST_ARTIFACTS.json", marker)
    write_new(local / "CAPRICORN_TEST_ARTIFACTS.json", marker)
    (local / "volume-before.plist").write_bytes(plistlib.dumps(info))
    print(json.dumps(marker, ensure_ascii=False))


def verify(local):
    marker = json.loads((local / "CAPRICORN_TEST_ARTIFACTS.json").read_text())
    root = pathlib.Path(marker["root"])
    if marker["purpose"] != PURPOSE or root.parent != VOLUME:
        raise RuntimeError("Unrecognized test manifest")
    info = volume_info()
    before = json.loads((local / "existing-before.json").read_text())
    changes = []
    for name, expected in before["entries"].items():
        try:
            value = (VOLUME / name).lstat()
            actual = {
                "kind": stat.S_IFMT(value.st_mode),
                "size": value.st_size,
                "mtime_ns": value.st_mtime_ns,
                "inode": value.st_ino,
            }
            if actual != expected:
                changes.append({"path": name, "before": expected, "after": actual})
        except OSError as error:
            changes.append({"path": name, "error": str(error)})
    inventory = [
        {"path": str(path.relative_to(root)), "bytes": path.stat().st_size}
        for path in sorted(root.rglob("*")) if path.is_file()
    ]
    report = {
        "root": str(root),
        "existing_entries_checked": len(before["entries"]),
        "existing_changes": changes,
        "baseline_unreadable": before["errors"],
        "retained_files": len(inventory),
        "retained_bytes": sum(entry["bytes"] for entry in inventory),
        "free_bytes_after": info["FreeSpace"],
        "inventory": inventory,
        "local_temporary_fixtures": [
            str(path.parent)
            for path in sorted(pathlib.Path(tempfile.gettempdir()).glob("Capricorn-AIO-*/CAPRICORN_TEST_ARTIFACTS.json"))
            if json.loads(path.read_text()).get("purpose") == PURPOSE
        ],
    }
    destination = local / ("verification-" + uuid.uuid4().hex[:8] + ".json")
    write_new(destination, report)
    print(json.dumps({key: value for key, value in report.items() if key != "inventory"}, ensure_ascii=False))
    print(str(destination))
    if changes:
        raise SystemExit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["prepare", "verify"])
    parser.add_argument("--local", type=pathlib.Path)
    arguments = parser.parse_args()
    if arguments.action == "prepare":
        prepare()
    elif arguments.local is None:
        parser.error("--local is required for verification")
    else:
        verify(arguments.local)
