#!/usr/bin/env python3
"""Check a published signed feed with real Sparkle, without downloading or installing an update."""
import argparse
import json
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import time


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, timeout=45, **kwargs)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True, type=pathlib.Path)
    parser.add_argument("--sparkle-root", required=True, type=pathlib.Path)
    parser.add_argument("--previous-build", required=True)
    parser.add_argument("--feed-url", help="Optional local staging feed before publication.")
    options = parser.parse_args()
    with (options.app / "Contents/Info.plist").open("rb") as stream:
        release_info = plistlib.load(stream)
    cache = pathlib.Path.home() / "Library/Caches/CapricornUpdateFixtures"
    cache.mkdir(parents=True, exist_ok=True)
    root = pathlib.Path(tempfile.mkdtemp(prefix="published-feed-", dir=cache))
    tools = options.sparkle_root.resolve()
    executable = root / "SparkleFeedProbe"
    source = pathlib.Path(__file__).resolve().parents[1] / "script/fixtures/SparkleFeedProbe.swift"
    run("xcrun", "swiftc", "-parse-as-library", "-swift-version", "6", "-F", str(tools), "-framework", "Sparkle",
        "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
        str(source), "-o", str(executable))
    results = []
    for label, build in [("previous", options.previous_build), ("current", release_info["CFBundleVersion"])]:
        app = root / label / "FeedProbe.app"
        contents = app / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        (contents / "Frameworks").mkdir()
        shutil.copy2(executable, contents / "MacOS/SparkleFeedProbe")
        shutil.copytree(tools / "Sparkle.framework", contents / "Frameworks/Sparkle.framework", symlinks=True)
        output = root / f"{label}.json"
        info = {
            "CFBundleIdentifier": f"lex.Capricorn.FeedProbe.{root.name.replace('_', '-')}.{label}",
            "CFBundleName": "Sparkle Feed Probe",
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": "SparkleFeedProbe",
            "CFBundleVersion": build,
            "CFBundleShortVersionString": "0.0.1",
            "SUFeedURL": options.feed_url or release_info["SUFeedURL"],
            "SUPublicEDKey": release_info["SUPublicEDKey"],
            "SURequireSignedFeed": True,
            "SUVerifyUpdateBeforeExtraction": True,
            "SUSignedFeedFailureExpirationInterval": 0,
            "SUEnableAutomaticChecks": False,
            "SUAutomaticallyUpdate": False,
            "SUEnableSystemProfiling": False,
            "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True},
            "ProbeOutputPath": str(output)
        }
        with (contents / "Info.plist").open("wb") as stream:
            plistlib.dump(info, stream)
        run("codesign", "--force", "--sign", "-", str(app), capture_output=True)
        run("open", "-n", "--stdout", str(root / f"{label}.stdout.log"),
            "--stderr", str(root / f"{label}.stderr.log"), str(app))
        deadline = time.monotonic() + 35
        while time.monotonic() < deadline and not output.exists():
            time.sleep(0.2)
        if not output.exists():
            processes = run("ps", "-axo", "pid=,command=", capture_output=True).stdout
            for line in processes.splitlines():
                pid, _, command = line.strip().partition(" ")
                if command.strip() == str(contents / "MacOS/SparkleFeedProbe"):
                    run("kill", "-TERM", pid)
            raise RuntimeError(f"Feed probe timed out; retained artifacts: {root}")
        result = json.loads(output.read_text())
        results.append({"hostBuild": build, **result})
        print(json.dumps({"label": label, "artifacts": str(root), **result}, indent=2))
        if label == "previous":
            assert result["result"] == "available", result
            assert result["build"] == release_info["CFBundleVersion"], result
            assert result["version"] == release_info["CFBundleShortVersionString"], result
        else:
            assert result["result"] == "upToDate", result
    print(json.dumps({"results": results, "artifacts": str(root)}, indent=2))


if __name__ == "__main__":
    main()
