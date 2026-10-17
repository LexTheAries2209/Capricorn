#!/usr/bin/env python3
"""Prepare and verify a signed update feed without publishing anything."""
import argparse
import pathlib
import plistlib
import re
import shutil
import subprocess
import urllib.parse
import xml.etree.ElementTree as ET


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, timeout=60, **kwargs)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True, type=pathlib.Path)
    parser.add_argument("--sparkle-bin", required=True, type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--download-url-prefix", required=True)
    parser.add_argument("--release-notes", required=True, type=pathlib.Path)
    parser.add_argument("--previous-build", required=True, type=int,
                        help="Previous global release build in decimal, e.g. 0041 at the migration baseline.")
    parser.add_argument("--key-account", default="lex.Capricorn")
    parser.add_argument("--allow-development-signing", action="store_true")
    options = parser.parse_args()
    app = options.app.resolve()
    tools = options.sparkle_bin.resolve()
    destination = options.output.resolve()
    prefix = urllib.parse.urlparse(options.download_url_prefix)
    if prefix.scheme != "https" or not prefix.netloc or prefix.username or prefix.password or prefix.query or prefix.fragment:
        parser.error("The download prefix must be an HTTPS URL without credentials, query, or fragment.")
    if not options.download_url_prefix.endswith("/"):
        parser.error("The download prefix must end with '/'.")
    if app.name != "Capricorn.app":
        parser.error("The bundle must have the stable name Capricorn.app.")
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info.get("CFBundleIdentifier") != "lex.Capricorn":
        parser.error("Unexpected bundle identifier.")
    version = info["CFBundleShortVersionString"]
    build = info["CFBundleVersion"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version) or not re.fullmatch(r"[0-9]{4}", build) or int(build) == 0:
        parser.error("A complete marketing version and a four-digit build (0001-9999) are required.")
    if options.previous_build < 0 or int(build) <= options.previous_build:
        parser.error("The build must be strictly greater than the previous published build.")
    if not info.get("SURequireSignedFeed") or not info.get("SUVerifyUpdateBeforeExtraction"):
        parser.error("Signed feeds and validation before extraction must be enabled.")
    run("codesign", "--verify", "--deep", "--strict", str(app))
    identity = run("codesign", "-dv", "--verbose=2", str(app), capture_output=True).stderr
    if not options.allow_development_signing:
        if "Authority=Developer ID Application:" not in identity:
            parser.error("Public updates require Developer ID signing. Use --allow-development-signing only for local validation.")
        run("spctl", "--assess", "--type", "execute", "--verbose=2", str(app))
        run("xcrun", "stapler", "validate", str(app))
    public_key = run(str(tools / "generate_keys"), "--account", options.key_account, "-p", capture_output=True).stdout.strip()
    if info.get("SUPublicEDKey") != public_key:
        parser.error("The signing account does not match the public key in the app.")
    destination.mkdir(parents=True, exist_ok=False)
    archive = destination / f"Capricorn-v{version}-macOS.zip"
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(archive))
    shutil.copy2(options.release_notes, archive.with_suffix(".md"))
    run(str(tools / "generate_appcast"), "--account", options.key_account,
        "--maximum-deltas", "0", "--embed-release-notes",
        "--download-url-prefix", options.download_url_prefix,
        "--link", "https://github.com/LexTheAries2209/Capricorn/releases", str(destination))
    feed = destination / "appcast.xml"
    run(str(tools / "sign_update"), "--account", options.key_account, "--verify", str(feed))
    ns = {"s": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
    item = ET.parse(feed).find("./channel/item")
    if item is None or item.findtext("s:version", namespaces=ns) != build:
        raise ValueError("Generated appcast build does not match the app.")
    enclosure = item.find("enclosure")
    if enclosure is None or int(enclosure.attrib["length"]) != archive.stat().st_size:
        raise ValueError("Generated appcast length does not match the archive.")
    signature = enclosure.attrib["{" + ns["s"] + "}edSignature"]
    run(str(tools / "sign_update"), "--account", options.key_account, "--verify", str(archive), signature)
    print(f"Verified build {build}. Upload the immutable archive first, and appcast.xml last: {destination}")
    if options.allow_development_signing:
        print("Development validation only; Developer ID, notarization, and Gatekeeper trust are not established.")


if __name__ == "__main__":
    main()
