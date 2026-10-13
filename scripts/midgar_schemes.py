#!/usr/bin/env python3
"""Prints the URL schemes every Midgar host app must list in LSApplicationQueriesSchemes.

A scheme is the lowercased bundle identifier of an app in worker/catalog.json. Hosts register their
own scheme in CFBundleURLTypes and list all of them here, which is how the portal tells installed
apps from the rest.

    midgar_schemes.py            one scheme per line
    midgar_schemes.py --yaml     an xcodegen info.properties fragment
    midgar_schemes.py --plist    the same lists as plist XML
"""
import json
import pathlib
import sys

CATALOG = pathlib.Path(__file__).resolve().parent.parent / "worker" / "catalog.json"


def schemes():
    apps = json.loads(CATALOG.read_text())["apps"]
    return sorted({app["bundleId"].lower() for app in apps})


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
