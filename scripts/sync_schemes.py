#!/usr/bin/env python3
"""Brings a host's LSApplicationQueriesSchemes under the iOS 27 cap with the canonical Midgar list.

Works on an Info.plist (XML) or an xcodegen project.yml (every list under
`LSApplicationQueriesSchemes:`). The cap counts all entries, so a list is rewritten as the host's
other entries first (unchanged, in order), then the Midgar list from midgar_schemes.py cut from the
end until the total fits: the highest midgar-NN slots go first, a legacy bundle-id scheme never.

    sync_schemes.py                       dry run over every host in hosts.json
    sync_schemes.py --write               apply it to every host in hosts.json
    sync_schemes.py [--write] PATH ...    the same for the given Info.plist or project.yml files
    sync_schemes.py --hosts FILE          use another hosts file
"""
import argparse
import importlib.util
import json
import os
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
SKIP_DIRS = {".build", "build", "DerivedData", "Pods", "node_modules", ".git", ".scratch", "checkouts"}
KEY = "LSApplicationQueriesSchemes"
SLOT_PATTERN = re.compile(r"^midgar-\d\d$")
PLIST_PATTERN = re.compile(r"(<key>LSApplicationQueriesSchemes</key>\s*<array>)(.*?)(</array>)", re.S)
YAML_PATTERN = re.compile(r"^(\s*)LSApplicationQueriesSchemes:\s*\n((?:\1\s+-\s+.*\n?)*)", re.M)


def load_script(name):
    """Imports a sibling script by path, because `python3 -I` does not put its folder on sys.path."""
    spec = importlib.util.spec_from_file_location(name, HERE / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


MIDGAR = load_script("midgar_schemes")


def normalized(entry):
    """The scheme an entry names: unquoted and lowercased."""
    return entry.strip().strip("'\"").lower()


def is_midgar(entry):
    """True for the legacy bundle-id schemes and the reserved midgar-NN slots."""
    scheme = normalized(entry)
    return scheme in MIDGAR.legacy_schemes() or bool(SLOT_PATTERN.match(scheme))


def plan(entries):
    """Splits `entries` and returns (others, midgar) for the rewritten list.

    The Midgar list is the canonical one cut from the end to fit the cap beside the others. It is
    never cut into the legacy schemes, so a host with too many other entries stays over the cap.
    """
    others = [entry for entry in entries if not is_midgar(entry)]
    midgar = list(MIDGAR.schemes())
    legacy = len(MIDGAR.legacy_schemes())
    room = max(MIDGAR.QUERY_SCHEME_CAP - len(others), legacy)
    return others, midgar[:room]


def describe(path, entries):
    """One report line for a rewritten list."""
    others, midgar = plan(entries)
    total = len(others) + len(midgar)
    kept = ", ".join(normalized(entry) for entry in others) or "none"
    over = "  OVER CAP" if total > MIDGAR.QUERY_SCHEME_CAP else ""
    return f"  {path}: kept {len(others)} other ({kept}); wrote {len(midgar)} Midgar; total {total}{over}"


def plist_entries(text):
    """The raw entries of the first LSApplicationQueriesSchemes array in an XML plist, or None."""
    match = PLIST_PATTERN.search(text)
    return re.findall(r"<string>(.*?)</string>", match.group(2)) if match else None


def yaml_lists(text):
    """The raw entries of every LSApplicationQueriesSchemes list in a project.yml."""
    return [[line.split("-", 1)[1].strip() for line in match.group(2).splitlines() if "-" in line]
            for match in YAML_PATTERN.finditer(text)]


def file_lists(path):
    """The entry lists a host file declares, one per LSApplicationQueriesSchemes key."""
    text = path.read_text(errors="ignore")
    if path.suffix in (".yml", ".yaml"):
        return yaml_lists(text)
    entries = plist_entries(text)
    return [] if entries is None else [entries]


def host_files(repo):
    """Every project.yml and Info.plist in `repo` that declares LSApplicationQueriesSchemes."""
    found = []
    for folder, dirs, names in os.walk(repo):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS and not d.startswith(".") and not d.endswith((".xcodeproj", ".xcworkspace")))
        for name in sorted(names):
            path = pathlib.Path(folder) / name
            if name in ("project.yml", "Info.plist") and KEY in path.read_text(errors="ignore"):
                found.append(path)
    return found


def merged(entries):
    """The final list for `entries`: other entries first, then the trimmed Midgar list."""
    others, midgar = plan(entries)
    return others + midgar


def sync_plist(text):
    """Rewrite the LSApplicationQueriesSchemes array of an XML plist, or None when it has none."""
    match = PLIST_PATTERN.search(text)
    if not match:
        return None
    entries = re.findall(r"<string>(.*?)</string>", match.group(2))
    final = merged(entries)
    if final == entries:
        return text
    indent = re.search(r"\n(\s*)<string>", match.group(2))
    pad = indent.group(1) if indent else "\t\t"
    closing = re.search(r"\n(\s*)$", match.group(2))
    tail = "\n" + (closing.group(1) if closing else "\t")
    body = "".join(f"\n{pad}<string>{entry}</string>" for entry in final)
    return text[:match.start(2)] + body + tail + text[match.end(2):]


def sync_yaml(text):
    """Rewrite every LSApplicationQueriesSchemes list of a project.yml, or None when it has none."""
    if not YAML_PATTERN.search(text):
        return None

    def fill(match):
        lines = match.group(2).splitlines()
        entries = [line.split("-", 1)[1].strip() for line in lines if "-" in line]
        final = merged(entries)
        if final == entries:
            return match.group(0)
        first = lines[0] if lines else ""
        item_indent = re.match(r"\s*", first).group(0) if first else match.group(1) + "  "
        body = "".join(f"{item_indent}- {entry}\n" for entry in final)
        return f"{match.group(1)}{KEY}:\n{body}"

    return YAML_PATTERN.sub(fill, text)


def sync_file(path, write):
    """Reports one file and rewrites it when `write` is set. Returns (ok, over_cap)."""
    lists = file_lists(path)
    if not lists:
        print(f"  NO {KEY} in {path}")
        return False, False
    text = path.read_text()
    new = sync_yaml(text) if path.suffix in (".yml", ".yaml") else sync_plist(text)
    over = False
    for entries in lists:
        print(describe(path, entries))
        others, midgar = plan(entries)
        over = over or len(others) + len(midgar) > MIDGAR.QUERY_SCHEME_CAP
    if new != text and write:
        path.write_text(new)
        print(f"  UPDATED {path}")
    elif new != text:
        print(f"  WOULD UPDATE {path}")
    else:
        print(f"  UNCHANGED {path}")
    return True, over


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", help="report only (the default)")
    mode.add_argument("--write", action="store_true", help="rewrite the files")
    parser.add_argument("--hosts", default=str(HERE / "hosts.json"))
    parser.add_argument("paths", nargs="*")
    args = parser.parse_args()
    status = 0
    if args.paths:
        targets = [("files", [pathlib.Path(name) for name in args.paths])]
    else:
        hosts = json.loads(pathlib.Path(args.hosts).read_text())["hosts"]
        targets = [(host["name"], host_files(pathlib.Path(host["repo"]).expanduser())) for host in hosts]
    for name, files in targets:
        print(f"{name}{'' if files else ': no LSApplicationQueriesSchemes declared'}")
        for path in files:
            ok, over = sync_file(path, args.write)
            status |= (not ok) or over
    sys.exit(1 if status else 0)


if __name__ == "__main__":
    main()
