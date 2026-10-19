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
import xml.etree.ElementTree as ET


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sparkle-root", required=True, type=pathlib.Path)
    parser.add_argument("--scenario", choices=[
        "update", "manual-only", "cancel-install", "quit-before-install",
        "developer-auto", "developer-auto-disabled", "developer-auto-conflict", "developer-auto-download-conflict",
        "developer-auto-off-during-download", "developer-auto-ready-conflict",
        "conflict", "archive-signature", "feed-signature", "missing-feed",
        "launch-checks", "launch-disabled", "launch-conflict", "launch-refresh-during-check", "launch-timeout"
    ], default="update")
    parser.add_argument("--archive-delay", type=float, default=0,
                        help="Pause a fixture ZIP response after its first byte to exercise slow downloads.")
    options = parser.parse_args()
    repo = pathlib.Path(__file__).resolve().parents[1]
    tools = options.sparkle_root.resolve()
    frameworks = tools if (tools / "Sparkle.framework").is_dir() else tools / "Sparkle.xcframework/macos-arm64_x86_64"
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
        "-F", str(frameworks), "-framework", "Sparkle", "-framework", "SwiftData",
        "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
        str(repo / "script/fixtures/SparkleUpdateFixture.swift"),
        *(str(sources / name) for name in [
            "AppUpdateSafety.swift", "AppUpdateConfiguration.swift",
            "AppUpdatePromptController.swift", "AppUpdater.swift", "GuardedUpdateUserDriver.swift"
        ]), "-o", str(executable))
    feed_dir = root / "feed"
    feed_dir.mkdir()
    requests = []
    launch_request_cancelled = threading.Event()

    class RecordingHandler(http.server.SimpleHTTPRequestHandler):
        def do_GET(self):
            requests.append(self.path)
            if options.scenario == "launch-refresh-during-check" and self.path == "/appcast.xml":
                time.sleep(1)
            if options.scenario == "launch-timeout" and self.path == "/appcast.xml":
                if requests.count("/appcast.xml") == 1:
                    data = (feed_dir / "appcast.xml").read_bytes()
                    self.send_response(200)
                    self.send_header("Content-Type", "application/xml")
                    self.send_header("Content-Length", str(len(data)))
                    self.end_headers()
                    try:
                        # Keep delivering bytes: the 15-second limit must be total, not idle time.
                        for byte in data[:30]:
                            self.wfile.write(bytes([byte]))
                            self.wfile.flush()
                            time.sleep(1)
                    except (BrokenPipeError, ConnectionResetError):
                        launch_request_cancelled.set()
                else:
                    data = (feed_dir / "manual" / "appcast.xml").read_bytes()
                    self.send_response(200)
                    self.send_header("Content-Type", "application/xml")
                    self.send_header("Content-Length", str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)
                return
            if options.archive_delay > 0 and self.path.endswith(".zip"):
                data = (feed_dir / self.path.lstrip("/")).read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "application/zip")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data[:1])
                self.wfile.flush()
                time.sleep(options.archive_delay)
                self.wfile.write(data[1:])
                return
            super().do_GET()

    handler = functools.partial(RecordingHandler, directory=str(feed_dir))
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
            shutil.copytree(frameworks / "Sparkle.framework", contents / "Frameworks/Sparkle.framework", symlinks=True)
            info = {
                "CFBundleIdentifier": "lex.Capricorn.UpdateFixture",
                "CFBundleName": "Capricorn Update Fixture",
                "CFBundleExecutable": "CapricornUpdateFixture",
                "CFBundlePackageType": "APPL",
                "CFBundleVersion": f"{build:04d}",
                "CFBundleShortVersionString": "0.0.1" if build == 41 else "0.0.2",
                "LSMinimumSystemVersion": "14.0",
                "SUFeedURL": base_url + "appcast.xml",
                "SUPublicEDKey": public_key,
                "SUVerifyUpdateBeforeExtraction": True,
                "SURequireSignedFeed": True,
                "SUSignedFeedFailureExpirationInterval": 0,
                "SUEnableAutomaticChecks": False,
                "SUAllowsAutomaticUpdates": False,
                "SUAutomaticallyUpdate": False,
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

        installed = make_app(root / "installed", 41)
        update = make_app(root / "new", 42)
        archive = feed_dir / "Capricorn-0.0.2.zip"
        run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(update), str(archive))
        run(str(tools / "bin/generate_appcast"), "--ed-key-file", str(private_key),
            "--maximum-deltas", "0", "--download-url-prefix", base_url, str(feed_dir))
        run(str(tools / "bin/sign_update"), "--ed-key-file", str(private_key), "--verify", str(feed_dir / "appcast.xml"))
        build_in_feed = ET.parse(feed_dir / "appcast.xml").findtext(
            "./channel/item/{http://www.andymatuschak.org/xml-namespaces/sparkle}version"
        )
        if build_in_feed != "0042":
            raise ValueError("The signed appcast must retain the padded build 0042.")
        if options.scenario == "launch-timeout":
            manual_feed = feed_dir / "manual"
            manual_feed.mkdir()
            run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent",
                str(installed), str(manual_feed / "Capricorn-0.0.1.zip"))
            run(str(tools / "bin/generate_appcast"), "--ed-key-file", str(private_key),
                "--maximum-deltas", "0", "--download-url-prefix", base_url, str(manual_feed))
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
        result_path = root / "result.json"
        while time.monotonic() < deadline and not result_path.exists():
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
        if options.scenario == "launch-checks":
            assert result["result"] == "checked" and result["enabledBeforeLaunch"], result
            assert result["savedChoice"] and not result["timerEnabled"], result
            assert requests.count("/appcast.xml") == 1, requests
            shutil.move(result_path, root / "first-launch-result.json")
            run(*launch)
            deadline = time.monotonic() + 45
            while time.monotonic() < deadline and not result_path.exists():
                time.sleep(0.2)
            if not result_path.exists():
                raise RuntimeError(f"No second launch result; artifacts retained at {root}")
            result = json.loads(result_path.read_text())
            assert result["result"] == "checked" and result["enabledBeforeLaunch"], result
            assert result["savedChoice"] and not result["timerEnabled"], result
            assert requests.count("/appcast.xml") == 2, requests
        if options.scenario == "launch-timeout":
            result["requestCancelled"] = launch_request_cancelled.wait(timeout=2)
        print(json.dumps({
            "scenario": options.scenario, "artifacts": str(root),
            "feedRequests": requests.count("/appcast.xml"), "archiveDelay": options.archive_delay, **result
        }, indent=2))
        if options.scenario in ("update", "developer-auto"):
            assert result["result"] == "updated", result
            assert result["historyRetained"] and result["preferencesRetained"], result
        elif options.scenario in ("manual-only", "developer-auto-disabled", "launch-conflict",
                                  "launch-refresh-during-check", "developer-auto-conflict"):
            assert result["result"] == "manual-required" and result["build"] == "0041", result
            assert result["legacyDownloadsDisabled"] and not result["preparedInstallation"], result
            assert not any(path.endswith(".zip") for path in requests), requests
            assert requests.count("/appcast.xml") == 1, requests
            time.sleep(1)
            with (installed / "Contents/Info.plist").open("rb") as stream:
                assert plistlib.load(stream)["CFBundleVersion"] == "0041"
        elif options.scenario in ("cancel-install", "quit-before-install", "developer-auto-off-during-download"):
            assert result["result"] == "cancelled", result
            assert not result["preparedInstallation"] and not result["installationReserved"], result
            assert any(path.endswith(".zip") for path in requests), requests
            if options.scenario == "developer-auto-off-during-download":
                assert result["requiredManualConfirmation"], result
            time.sleep(1)
            with (installed / "Contents/Info.plist").open("rb") as stream:
                assert plistlib.load(stream)["CFBundleVersion"] == "0041"
        elif options.scenario == "launch-checks":
            assert result["build"] == "0041", result
        elif options.scenario == "launch-disabled":
            assert result["result"] == "disabled", result
            assert not result["enabledBeforeLaunch"] and not result["started"], result
            assert not requests, requests
        elif options.scenario == "launch-timeout":
            assert result["result"] == "timed-out-then-retried", result
            assert 14.5 <= result["timeoutElapsed"] <= 18, result
            assert requests.count("/appcast.xml") == 2, requests
            assert result["build"] == "0041", result
            assert result["requestCancelled"], result
        elif options.scenario == "developer-auto-download-conflict":
            assert result["result"] == "blocked" and result["build"] == "0041", result
            assert "Refresh Disks" in result["detail"], result
            assert any(path.endswith(".zip") for path in requests), requests
            time.sleep(1)
            with (installed / "Contents/Info.plist").open("rb") as stream:
                assert plistlib.load(stream)["CFBundleVersion"] == "0041"
        else:
            assert result["result"] == "blocked" and result["build"] == "0041", result
            if options.scenario in ("conflict", "developer-auto-ready-conflict"):
                assert "Benchmark" in result["detail"], result
                if options.scenario != "developer-auto-ready-conflict":
                    assert requests.count("/appcast.xml") == 1, requests
                    assert not any(path.endswith(".zip") for path in requests), requests
            elif options.scenario == "missing-feed":
                assert result["detail"] == "Unable to download updates. Check your network or Releases.", result
                assert "could not be reached" not in result["detail"], result
            else:
                assert "signature" in result["detail"].lower(), result
            with (installed / "Contents/Info.plist").open("rb") as stream:
                assert plistlib.load(stream)["CFBundleVersion"] == "0041"
    finally:
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    main()
