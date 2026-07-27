#!/usr/bin/env python3
"""Populate `screenshots` in worker/catalog.json from App Store Connect.

The iTunes lookup feed returns no `screenshotUrls` for this catalogue, so the storefront falls back
to an icon-on-gradient hero. App Store Connect has the real assets: every `appScreenshot` carries an
`imageAsset.templateUrl` of the form `.../{w}x{h}bb.{f}`, which resolves to a CDN image once the
placeholders are substituted. Writing those into the catalog upgrades every featured card with no
client change and no app release.

Usage:  scripts/sync-screenshots.py [--width 800] [--max 5] [--dry-run]
"""
import argparse
import json
import os
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.expanduser("~/Dev/operator/lib"))
import asc  # noqa: E402

# Widest iPhone frames first — the catalog wants one consistent aspect ratio per app.
DISPLAY_PRIORITY = [
    "APP_IPHONE_69", "APP_IPHONE_67", "APP_IPHONE_65", "APP_IPHONE_61", "APP_IPHONE_58",
    "APP_IPHONE_55", "APP_IPHONE_47",
]
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(HERE, "worker", "catalog.json")


def screenshot_sets_for(app_id):
    """Yields (display_type, [screenshot]) for the first version/locale that has any."""
    versions = asc.get(f"/v1/apps/{app_id}/appStoreVersions", **{"limit": 5}).get("data", [])
    for version in versions:
        locales = asc.get(
            f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations"
        ).get("data", [])
        locales.sort(key=lambda l: l["attributes"]["locale"] != "en-US")
        for locale in locales:
            sets = asc.get(
                f"/v1/appStoreVersionLocalizations/{locale['id']}/appScreenshotSets"
            ).get("data", [])
            by_type = {s["attributes"].get("screenshotDisplayType"): s for s in sets}
            for display in DISPLAY_PRIORITY:
                if display not in by_type:
                    continue
                shots = asc.get(
                    f"/v1/appScreenshotSets/{by_type[display]['id']}/appScreenshots"
                ).get("data", [])
                usable = [s for s in shots if (s["attributes"].get("imageAsset") or {}).get("templateUrl")]
                if usable:
                    usable.sort(key=lambda s: s["attributes"].get("fileName") or "")
                    return display, usable
    return None, []


def resolve(shot, width):
    asset = shot["attributes"]["imageAsset"]
    src_w, src_h = asset.get("width") or 0, asset.get("height") or 0
    if not src_w or not src_h:
        return None
    height = round(width * src_h / src_w)
    return (asset["templateUrl"]
            .replace("{w}", str(width))
            .replace("{h}", str(height))
            .replace("{f}", "jpg"))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--width", type=int, default=800)
    parser.add_argument("--max", type=int, default=5)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    with open(CATALOG) as handle:
        catalog = json.load(handle)

    total = 0
    for entry in catalog["apps"]:
        display, shots = screenshot_sets_for(entry["appId"])
        urls = [u for u in (resolve(s, args.width) for s in shots[: args.max]) if u]
        entry["screenshots"] = urls
        total += len(urls)
        status = f"{len(urls)} ({display})" if urls else "none in ASC"
        print(f"  {entry['name'][:34]:<36} {status}")

    if args.dry_run:
        print(f"\ndry run — {total} screenshots resolved, catalog not written")
        return

    catalog["version"] = int(catalog.get("version", 0)) + 1
    catalog["updatedAt"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    with open(CATALOG, "w") as handle:
        json.dump(catalog, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    print(f"\nwrote {total} screenshots across {len(catalog['apps'])} apps "
          f"-> catalog v{catalog['version']}")


if __name__ == "__main__":
    main()
