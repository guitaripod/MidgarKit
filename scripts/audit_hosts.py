#!/usr/bin/env python3
"""Checks that Midgar host apps carry the portal entry the same way everywhere.

Two modes:

  audit_hosts.py --app /path/Some.app --bundle-id com.example.app
      Reads the built Info.plist and checks the host registers its own URL scheme, lists every
      scheme from midgar_schemes.py in LSApplicationQueriesSchemes, and stays within the 25-entry
      cap iOS 27 enforces on that key.

  audit_hosts.py [--hosts scripts/hosts.json]
      Static pass over each host repo: which MidgarKit requirement it declares and whether Swift
      sources use MidgarEntryView or MidgarEntryCard. Exits 1 when a host is missing the entry.
"""
import argparse
import importlib.util
import json
import os
import pathlib
import plistlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SKIP_DIRS = {".build", "build", "DerivedData", "Pods", "node_modules", ".git", ".scratch", "checkouts"}
ENTRY_PATTERN = re.compile(r"MidgarEntry(View|Card)")
LEGACY_PATTERN = re.compile(r"Midgar\.present|MoreAppsService|MoreAppsView")


def load_script(name):
    """Imports a sibling script by path, because `python3 -I` does not put its folder on sys.path."""
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SYNC = load_script("sync_schemes")


def query_scheme_cap():
    """The LSApplicationQueriesSchemes cap, read from midgar_schemes.py so there is one definition."""
    return SYNC.MIDGAR.QUERY_SCHEME_CAP


def query_list_summary(repo):
    """Describes the host's LSApplicationQueriesSchemes lists: non-Midgar entry count and total size."""
    lists = [entries for path in SYNC.host_files(repo) for entries in SYNC.file_lists(path)]
    if not lists:
        return "no LSApplicationQueriesSchemes declared"
    others = max(sum(not SYNC.is_midgar(entry) for entry in entries) for entries in lists)
    total = max(len(entries) for entries in lists)
    over = f", OVER the cap of {query_scheme_cap()}" if total > query_scheme_cap() else ""
    return f"{others} non-Midgar scheme entries, {total} in total{over}"


def catalog_schemes():
    """Every scheme a host should list: the legacy bundle-id schemes plus the reserved slots."""
    output = subprocess.run([sys.executable, str(ROOT / "scripts" / "midgar_schemes.py")], capture_output=True, text=True)
    return output.stdout.split()


def audit_app(path, bundle_id):
    plist = plistlib.loads((pathlib.Path(path) / "Info.plist").read_bytes()) if (pathlib.Path(path) / "Info.plist").exists() else \
        plistlib.loads((pathlib.Path(path) / "Contents" / "Info.plist").read_bytes())
    own = bundle_id.lower()
    registered = {s.lower() for entry in plist.get("CFBundleURLTypes", []) for s in entry.get("CFBundleURLSchemes", [])}
    declared = plist.get("LSApplicationQueriesSchemes", [])
    queries = {s.lower() for s in declared}
    problems = []
    cap = query_scheme_cap()
    if len(declared) > cap:
        problems.append(
            f"LSApplicationQueriesSchemes lists {len(declared)} entries; apps linked on or after iOS 27 "
            f"are limited to {cap}, so canOpenURL fails for the rest. Replace the list with the output "
            f"of scripts/midgar_schemes.py"
        )
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
    for folder, dirs, names in os.walk(repo):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in names:
            if name.endswith(".swift"):
                yield pathlib.Path(folder) / name


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


def manifest_files(repo):
    """The project.yml, Package.swift and project.pbxproj files of `repo`, skipping build folders."""
    for folder, dirs, names in os.walk(repo):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.startswith(".")]
        for name in names:
            if name in ("project.yml", "Package.swift") or name.endswith(".pbxproj"):
                yield pathlib.Path(folder) / name


def requirement(repo):
    found = []
    for path in manifest_files(repo):
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
        summary = query_list_summary(pathlib.Path(host["repo"]).expanduser())
        print(f"{status} {host['name']} [{summary}]" + ("" if not problems else ": " + "; ".join(problems)))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
