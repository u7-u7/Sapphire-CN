#!/usr/bin/env python3
"""Publish real GitHub Release metadata to the public CN update feed."""

import argparse
import json
from pathlib import Path
import re
import subprocess


REPOSITORY = "u7-u7/Sapphire-CN"
VERSION = re.compile(r"^v?(\d+(?:\.\d+){1,2})-cn\.(\d+)(-preview)?$")


def version_key(tag):
    match = VERSION.fullmatch(tag)
    if not match:
        raise ValueError("Expected a CN release tag")
    core = tuple(int(part) for part in match.group(1).split("."))
    return core + (0,) * (3 - len(core)) + (int(match.group(2)), not match.group(3))


def release_metadata(tag):
    raw = subprocess.check_output(
        ["gh", "api", f"repos/{REPOSITORY}/releases/tags/{tag}"], text=True
    )
    release = json.loads(raw)
    if release.get("draft") or release.get("tag_name") != tag or not release.get("published_at"):
        raise ValueError("Publish the release and finish its assets before updating the feed")
    assets = [validated_asset(asset, tag) for asset in release["assets"]
              if asset["name"].lower().endswith("-update.zip")]
    if not assets:
        raise ValueError("The release needs an app-only -update.zip")
    keys = ("name", "tag_name", "body", "html_url", "prerelease", "draft", "published_at")
    return {**{key: release.get(key) for key in keys}, "assets": assets}


def validated_asset(asset, tag):
    prefix = f"https://github.com/{REPOSITORY}/releases/download/{tag}/"
    if (asset.get("state") != "uploaded"
            or not asset.get("browser_download_url", "").startswith(prefix)
            or not 0 < asset.get("size", 0) <= 1024 ** 3
            or not re.fullmatch(r"sha256:[0-9a-f]{64}", asset.get("digest") or "")):
        raise ValueError(f"Incomplete or unverified update asset: {asset['name']}")
    keys = ("name", "browser_download_url", "size", "digest", "content_type")
    return {key: asset.get(key) for key in keys}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag", help="Published tag, for example v3.0-cn.4-preview")
    args = parser.parse_args()
    version_key(args.tag)
    release = release_metadata(args.tag)
    destination = Path(__file__).resolve().parents[1] / "updates/releases.json"
    existing = json.loads(destination.read_text()) if destination.exists() else []
    releases = [release] + [item for item in existing if item["tag_name"] != args.tag]
    releases.sort(key=lambda item: version_key(item["tag_name"]), reverse=True)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(releases[:10], ensure_ascii=False, indent=2) + "\n")
    temporary.replace(destination)
    print(f"Updated {destination.relative_to(destination.parents[1])} from {args.tag}")


if __name__ == "__main__":
    main()
