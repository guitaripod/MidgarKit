#!/usr/bin/env python3
"""Checks that Midgar host apps carry the portal entry the same way everywhere.

Two modes:

  audit_hosts.py --app /path/Some.app --bundle-id com.example.app
      Reads the built Info.plist and checks the host registers its own URL scheme and lists every
      scheme from worker/catalog.json in LSApplicationQueriesSchemes.

  audit_hosts.py [--hosts scripts/hosts.json]
      Static pass over each host repo: which MidgarKit requirement it declares and whether Swift
      sources use MidgarEntryView or MidgarEntryCard. Exits 1 when a host is missing the entry.
"""
import argparse
import json
import pathlib
import plistlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SKIP_DIRS = {".build", "build", "DerivedData", "Pods", "node_modules", ".git", ".scratch", "checkouts"}
ENTRY_PATTERN = re.compile(r"MidgarEntry(View|Card)")
LEGACY_PATTERN = re.compile(r"Midgar\.present|MoreAppsService|MoreAppsView")


def catalog_schemes():
    """Every scheme a host should list: the apps' own schemes plus the reserved slots."""
    output = subprocess.run([sys.executable, str(ROOT / "scripts" / "midgar_schemes.py")], capture_output=True, text=True)
    return output.stdout.split()


def audit_app(path, bundle_id):
    plist = plistlib.loads((pathlib.Path(path) / "Info.plist").read_bytes()) if (pathlib.Path(path) / "Info.plist").exists() else \
        plistlib.loads((pathlib.Path(path) / "Contents" / "Info.plist").read_bytes())
    own = bundle_id.lower()
    registered = {s.lower() for entry in plist.get("CFBundleURLTypes", []) for s in entry.get("CFBundleURLSchemes", [])}
    queries = {s.lower() for s in plist.get("LSApplicationQueriesSchemes", [])}
    problems = []
    if own not in registered:
        problems.append(f"own scheme {own} missing from CFBundleURLTypes")
    missing = [s for s in catalog_schemes() if s not in queries and s != own and not s.startswith("midgar-")]
    absent_slots = [s for s in catalog_schemes() if s.startswith("midgar-") and s not in queries]
    if absent_slots:
        print(f"WARN {len(absent_slots)} reserved scheme slots are not listed yet (new apps will not read as installed here)")
    if missing:
        problems.append(f"LSApplicationQueriesSchemes missing {len(missing)}: {', '.join(missing)}")
    is_ios = "UIDeviceFamily" in plist or "UIRequiredDeviceCapabilities" in plist or plist.get("DTPlatformName") == "iphoneos"
    if is_ios and plist.get("DTPlatformName", "iphoneos") == "iphoneos" and not plist.get("CADisableMinimumFrameDurationOnPhone"):
        problems.append("CADisableMinimumFrameDurationOnPhone is not true, the portal would be capped at 60 Hz on iPhone")
    return problems


def swift_files(repo):
    for path in repo.rglob("*.swift"):
        if SKIP_DIRS.isdisjoint(path.parts):
            yield path


def requirement_in(path, text):
    """Returns the MidgarKit requirement declared in `text`, or None when it declares none."""
    if path.suffix == ".pbxproj":
        block = re.search(r'XCRemoteSwiftPackageReference "?MidgarKit"? \*/ = \{(.*?)\n\t\t\};', text, re.S)
        if block:
            kind = re.search(r"kind = (\w+)", block.group(1))
            value = re.search(r'(minimumVersion|version|branch|revision) = "?([\w./-]+)', block.group(1))
            return f"{path.name}:{kind.group(1) if kind else '?'} {value.group(2) if value else ''}".strip()
        local = re.search(r'XCLocalSwiftPackageReference "?[\w./-]*MidgarKit"?', text)
        return f"{path.name}:local" if local else None
    anchor = re.search(r"^\s*MidgarKit:|guitaripod/MidgarKit|\.package\(.*MidgarKit", text, re.M)
    if not anchor:
        return None
    window = text[anchor.start():anchor.start() + 400]
    value = re.search(r"(branch|from|exactVersion|minimumVersion|path)\W{1,4}([\w./-]+)", window)
    return f"{path.name}:{value.group(1)}={value.group(2)}" if value else f"{path.name}:declared"


def requirement(repo):
    found = []
    for pattern in ("project.yml", "Package.swift", "*.pbxproj"):
        for path in repo.rglob(pattern):
            if not SKIP_DIRS.isdisjoint(path.parts):
                continue
            text = path.read_text(errors="ignore")
            if "MidgarKit" not in text:
                continue
            result = requirement_in(path, text)
            if result:
                found.append(result)
    return found


def audit_repo(host):
    repo = pathlib.Path(host["repo"]).expanduser()
    if not repo.exists():
        return [f"repo {repo} not found"]
    problems = []
    declared = requirement(repo)
    if not declared:
        problems.append("no MidgarKit dependency declared")
    elif any("local" in item for item in declared):
        problems.append("MidgarKit is a local path dependency")
    entries = legacy = 0
    for path in swift_files(repo):
        text = path.read_text(errors="ignore")
        entries += len(ENTRY_PATTERN.findall(text))
        legacy += len(LEGACY_PATTERN.findall(text))
    if entries == 0:
        problems.append("no MidgarEntryView or MidgarEntryCard in Swift sources")
    return problems


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app")
    parser.add_argument("--bundle-id")
    parser.add_argument("--hosts", default=str(ROOT / "scripts" / "hosts.json"))
    args = parser.parse_args()
    if args.app:
        problems = audit_app(args.app, args.bundle_id or "")
        print("OK" if not problems else "\n".join(f"FAIL {p}" for p in problems))
        sys.exit(1 if problems else 0)
    failed = 0
    for host in json.loads(pathlib.Path(args.hosts).read_text())["hosts"]:
        problems = audit_repo(host)
        status = "OK  " if not problems else "FAIL"
        failed += bool(problems)
        print(f"{status} {host['name']}" + ("" if not problems else ": " + "; ".join(problems)))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
