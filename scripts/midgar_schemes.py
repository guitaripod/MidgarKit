#!/usr/bin/env python3
"""Prints the URL schemes every Midgar host app must list in LSApplicationQueriesSchemes.

A scheme is the lowercased bundle identifier of an app in worker/catalog.json, unless the entry
names its own `scheme`. Newer apps claim one of the reserved slots midgar-01 to midgar-30 instead,
and every host lists all slots from day one, so a new app never needs a change in any existing
host. Hosts register their own scheme in CFBundleURLTypes and list everything printed here in
LSApplicationQueriesSchemes, which is how the portal tells installed apps from the rest.

    midgar_schemes.py            one scheme per line
    midgar_schemes.py --yaml     an xcodegen info.properties fragment
    midgar_schemes.py --plist    the same lists as plist XML
"""
import json
import pathlib
import sys

CATALOG = pathlib.Path(__file__).resolve().parent.parent / "worker" / "catalog.json"
SLOT_COUNT = 30
LIMIT = 50


def slots():
    """The reserved scheme slots every host declares."""
    return [f"midgar-{index:02d}" for index in range(1, SLOT_COUNT + 1)]


def schemes():
    """Every scheme a host must list: the apps' own schemes plus all reserved slots."""
    apps = json.loads(CATALOG.read_text())["apps"]
    own = {(app.get("scheme") or app["bundleId"]).lower() for app in apps}
    result = sorted(own | set(slots()))
    if len(result) > LIMIT:
        raise SystemExit(f"{len(result)} schemes exceed the iOS limit of {LIMIT}")
    return result


def main():
    names = schemes()
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "--yaml":
        print("LSApplicationQueriesSchemes:")
        for name in names:
            print(f"  - {name}")
    elif mode == "--plist":
        print("<key>LSApplicationQueriesSchemes</key>\n<array>")
        for name in names:
            print(f"\t<string>{name}</string>")
        print("</array>")
    else:
        print("\n".join(names))


if __name__ == "__main__":
    main()
