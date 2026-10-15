#!/usr/bin/env python3
"""Prints the URL schemes every Midgar host app must list in LSApplicationQueriesSchemes.

iOS 27 limits apps linked against it to 25 LSApplicationQueriesSchemes entries, so the list is
exactly that long: the lowercased bundle identifiers of the apps that shipped before reserved slots
existed (their only scheme, which they keep registering), then as many reserved slots midgar-01,
midgar-02, ... as still fit. Each app claims its `slot` in worker/catalog.meta.json and registers it
in CFBundleURLTypes at its next release; once every app has, hosts can drop the bundle-id schemes
and list midgar-01 to midgar-25 only. Hosts register their own scheme in CFBundleURLTypes, which
is how the portal tells installed apps from the rest.

    midgar_schemes.py            one scheme per line
    midgar_schemes.py --yaml     an xcodegen info.properties fragment
    midgar_schemes.py --plist    the same lists as plist XML
"""
import sys

QUERY_SCHEME_CAP = 25
"""Apple: apps linked on or after iOS 27 may declare at most 25 LSApplicationQueriesSchemes entries."""

LEGACY_BUNDLE_IDS = (
    "com.guitaripod.embr",
    "com.guitaripod.helia",
    "com.guitaripod.payday",
    "com.guitaripod.pixie",
    "com.guitaripod.psybeam",
    "com.guitaripod.tailscode",
    "com.marcusziade.aotd",
    "com.marcusziade.doublekick",
    "com.marcusziade.dreameater",
    "com.marcusziade.inventory",
    "com.marcusziade.knowtheflag",
    "com.marcusziade.psywave",
    "com.marcusziade.sforesight",
    "com.marcusziade.solarbeam",
    "com.midgarcorp.flaccy",
    "com.midgarcorp.flaccy.mac",
)
"""The apps that shipped before slots: their bundle-id scheme is already in hosts' query lists."""


def legacy_schemes():
    """The bundle-id schemes of the apps that shipped before reserved slots, sorted."""
    return sorted(bundle_id.lower() for bundle_id in LEGACY_BUNDLE_IDS)


def slots():
    """The reserved scheme slots that fit under the cap after the legacy schemes."""
    return [f"midgar-{index:02d}" for index in range(1, QUERY_SCHEME_CAP - len(LEGACY_BUNDLE_IDS) + 1)]


def schemes():
    """Every scheme a host must list: the legacy bundle-id schemes, then the slots that fit."""
    result = legacy_schemes() + slots()
    if len(result) > QUERY_SCHEME_CAP:
        raise SystemExit(f"{len(result)} schemes exceed the iOS 27 limit of {QUERY_SCHEME_CAP}")
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
