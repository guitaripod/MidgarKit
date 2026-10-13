#!/usr/bin/env python3
"""Adds every scheme from midgar_schemes.py that a host's LSApplicationQueriesSchemes is missing.

Works on an Info.plist (XML) or an xcodegen project.yml (the list under
`LSApplicationQueriesSchemes:`). Existing entries are never removed.

    sync_schemes.py path/to/Info.plist [more paths ...]
"""
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent


def wanted():
    """The schemes every host must list."""
    return subprocess.run([sys.executable, str(HERE / "midgar_schemes.py")], capture_output=True, text=True,
                          check=True).stdout.split()


def sync_plist(text, schemes):
    """Insert missing schemes into the LSApplicationQueriesSchemes array of an XML plist."""
    match = re.search(r"(<key>LSApplicationQueriesSchemes</key>\s*<array>)(.*?)(</array>)", text, re.S)
    if not match:
        return None
    present = {s.lower() for s in re.findall(r"<string>(.*?)</string>", match.group(2))}
    missing = [s for s in schemes if s not in present]
    if not missing:
        return text
    indent = re.search(r"\n(\s*)<string>", match.group(2))
    pad = indent.group(1) if indent else "\t\t"
    insert = "".join(f"\n{pad}<string>{s}</string>" for s in missing)
    body = match.group(2).rstrip()
    closing = re.search(r"\n(\s*)$", match.group(2))
    tail = "\n" + (closing.group(1) if closing else "\t")
    return text[:match.start(2)] + body + insert + tail + text[match.end(2):]


def sync_yaml(text, schemes):
    """Insert missing schemes into every LSApplicationQueriesSchemes list of a project.yml."""
    pattern = re.compile(r"^(\s*)LSApplicationQueriesSchemes:\s*\n((?:\1\s+-\s+.*\n?)*)", re.M)
    if not pattern.search(text):
        return None

    def fill(match):
        present = {line.split("-", 1)[1].strip().lower() for line in match.group(2).splitlines() if "-" in line}
        missing = [s for s in schemes if s not in present]
        if not missing:
            return match.group(0)
        first = match.group(2).splitlines()[0] if match.group(2) else ""
        item_indent = re.match(r"\s*", first).group(0) if first else match.group(1) + "  "
        body = match.group(2) if match.group(2).endswith("\n") or not match.group(2) else match.group(2) + "\n"
        body += "".join(f"{item_indent}- {s}\n" for s in missing)
        return f"{match.group(1)}LSApplicationQueriesSchemes:\n{body}"

    return pattern.sub(fill, text)


def main():
    schemes = wanted()
    status = 0
    for name in sys.argv[1:]:
        path = pathlib.Path(name)
        text = path.read_text()
        new = sync_yaml(text, schemes) if path.suffix in (".yml", ".yaml") else sync_plist(text, schemes)
        if new is None:
            print(f"NO LSApplicationQueriesSchemes in {path}")
            status = 1
        elif new != text:
            path.write_text(new)
            print(f"UPDATED {path}")
        else:
            print(f"OK {path}")
    sys.exit(status)


if __name__ == "__main__":
    main()
