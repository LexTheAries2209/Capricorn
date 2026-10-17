#!/usr/bin/env python3
"""Exercise the real Sparkle installer using isolated, locally signed fixture apps.

All artifacts are retained under the user's Caches directory. No production preferences, history, feed,
or signing keys are used. The fixture deliberately has no hardened runtime;
Developer ID / notarized distribution requires separate release validation.
"""
import argparse
import functools
import http.server
import json
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import threading
import time


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sparkle-root", required=True, type=pathlib.Path)
    parser.add_argument("--scenario", choices=["update", "automatic", "conflict", "archive-signature", "feed-signature", "missing-feed"], default="update")
    options = parser.parse_args()
    repo = pathlib.Path(__file__).resolve().parents[1]
    tools = options.sparkle_root.resolve()
    fixtures = pathlib.Path.home() / "Library/Caches/CapricornUpdateFixtures"
    fixtures.mkdir(parents=True, exist_ok=True)
    root = pathlib.Path(tempfile.mkdtemp(prefix=f"sparkle-{options.scenario}-", dir=fixtures))
    private_key = root / "fixture-key"
    public_key = run(
        "xcrun", "swift", str(repo / "script/fixtures/GenerateTestUpdateKey.swift"), str(private_key),
        capture_output=True
    ).stdout.strip()
    executable = root / "CapricornUpdateFixture"
    sources = repo / "Capricorn/Services/Updates"
    run("xcrun", "swiftc", "-swift-version", "6", "-target", "arm64-apple-macos14.0",
        "-F", str(tools), "-framework", "Sparkle", "-framework", "SwiftData",
        "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
        str(repo / "script/fixtures/SparkleUpdateFixture.swift"),
        *(str(sources / name) for name in [
            "AppUpdateSafety.swift", "AppUpdateConfiguration.swift",
            "AppUpdater.swift", "GuardedUpdateUserDriver.swift"
        ]), "-o", str(executable))
    feed_dir = root / "feed"
    feed_dir.mkdir()
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(feed_dir))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    base_url = f"http://127.0.0.1:{server.server_port}/"
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        def make_app(parent, build):
            app = parent / "Capricorn.app"
            contents = app / "Contents"
            (contents / "MacOS").mkdir(parents=True)
            (contents / "Frameworks").mkdir()
            shutil.copy2(executable, contents / "MacOS/CapricornUpdateFixture")
            shutil.copytree(tools / "Sparkle.framework", contents / "Frameworks/Sparkle.framework", symlinks=True)
            info = {
                "CFBundleIdentifier": "lex.Capricorn.UpdateFixture",
                "CFBundleName": "Capricorn Update Fixture",
                "CFBundleExecutable": "CapricornUpdateFixture",
                "CFBundlePackageType": "APPL",
                "CFBundleVersion": str(build),
                "CFBundleShortVersionString": "0.0.1" if build == 1000 else "0.0.2",
                "LSMinimumSystemVersion": "14.0",
                "SUFeedURL": base_url + "appcast.xml",
                "SUPublicEDKey": public_key,
                "SUVerifyUpdateBeforeExtraction": True,
                "SURequireSignedFeed": True,
                "SUSignedFeedFailureExpirationInterval": 0,
                "SUEnableAutomaticChecks": options.scenario == "automatic",
                "SUAutomaticallyUpdate": options.scenario == "automatic",
                "SUEnableSystemProfiling": False,
                "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True},
                "CapricornFixtureRoot": str(root),
                "CapricornFixtureScenario": options.scenario,
            }
            with (contents / "Info.plist").open("wb") as stream:
                plistlib.dump(info, stream)
            run("codesign", "--force", "--sign", "-", str(app), capture_output=True)
            run("codesign", "--verify", "--deep", "--strict", str(app), capture_output=True)
            return app

        installed = make_app(root / "installed", 1000)
        update = make_app(root / "new", 1001)
        archive = feed_dir / "Capricorn-0.0.2.zip"
        run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(update), str(archive))
        run(str(tools / "bin/generate_appcast"), "--ed-key-file", str(private_key),
            "--maximum-deltas", "0", "--download-url-prefix", base_url, str(feed_dir))
        run(str(tools / "bin/sign_update"), "--ed-key-file", str(private_key), "--verify", str(feed_dir / "appcast.xml"))
        if options.scenario == "archive-signature":
            with archive.open("r+b") as stream:
                stream.seek(128)
                value = stream.read(1)
                stream.seek(128)
                stream.write(bytes([value[0] ^ 1]))
        elif options.scenario == "feed-signature":
            feed = feed_dir / "appcast.xml"
            feed.write_bytes(feed.read_bytes().replace(b"<title>", b"<title>tampered ", 1))
        elif options.scenario == "missing-feed":
            shutil.move(feed_dir / "appcast.xml", feed_dir / "unpublished.xml")
        launch = ["open", "-n", "--stdout", str(root / "stdout.log"), "--stderr", str(root / "stderr.log"), str(installed)]
        run(*launch)
        deadline = time.monotonic() + 55
        relaunched = False
        result_path = root / "result.json"
        while time.monotonic() < deadline and not result_path.exists():
            if options.scenario == "automatic" and not relaunched:
                with (installed / "Contents/Info.plist").open("rb") as stream:
                    version = plistlib.load(stream)["CFBundleVersion"]
                if version == "1001":
                    run(*launch)
                    relaunched = True
            time.sleep(0.2)
        if not result_path.exists():
            # Terminate only the fixture launched from this unique test directory.
            processes = run("ps", "-axo", "pid=,command=", capture_output=True).stdout
            for line in processes.splitlines():
                pid, _, command = line.strip().partition(" ")
                if command.strip() == str(installed / "Contents/MacOS/CapricornUpdateFixture"):
                    run("kill", "-TERM", pid)
            raise RuntimeError(f"No fixture result; artifacts retained at {root}")
        result = json.loads(result_path.read_text())
        print(json.dumps({"scenario": options.scenario, "artifacts": str(root), **result}, indent=2))
        if options.scenario in ("update", "automatic"):
            assert result["result"] == "updated", result
            assert result["historyRetained"] and result["preferencesRetained"], result
        else:
            assert result["result"] == "blocked" and result["build"] == "1000", result
            if options.scenario == "conflict":
                assert "Benchmark" in result["detail"], result
            elif options.scenario == "missing-feed":
                assert "confirm the update files are available" in result["detail"], result
                assert "could not be reached" not in result["detail"], result
            else:
                assert "signature" in result["detail"].lower(), result
            with (installed / "Contents/Info.plist").open("rb") as stream:
                assert plistlib.load(stream)["CFBundleVersion"] == "1000"
    finally:
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    main()
