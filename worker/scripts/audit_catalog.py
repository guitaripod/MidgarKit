"""Audits worker/catalog.json, or a deployed catalog, against the developer's live App Store apps.

Prints MISSING for live apps absent from the catalog, STALE for catalog entries that are neither live nor marked staged, and OK when neither happens. Exits 1 on any MISSING or STALE line. Run with `python3 -I worker/scripts/audit_catalog.py`, or pass `--url` to audit the deployed catalog instead of the file.
"""

import argparse
import json
import pathlib
import sys
import time
import urllib.request


ROOT = pathlib.Path(__file__).resolve().parents[2]
CATALOG_PATH = ROOT / "worker" / "catalog.json"
LIVE_LOOKUP_URL = "https://itunes.apple.com/lookup?id=1484270247&entity=software&country=us&limit=200"
LOOKUP_KINDS = ("software", "mac-software")
USER_AGENT = "midgar-catalog-tools/1.0"
REQUEST_TIMEOUT_SECONDS = 20
REQUEST_ATTEMPTS = 2
RETRY_DELAY_SECONDS = 2
STATUS_STAGED = "staged"


class AuditError(Exception):
    """A fatal problem that prevents the audit from running."""


def fetch_bytes(url):
    """Downloads a URL and returns the body, retrying once after a failure."""
    last_error = None
    for attempt in range(REQUEST_ATTEMPTS):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
                return response.read()
        except (OSError, ValueError) as error:
            last_error = error
            if attempt + 1 < REQUEST_ATTEMPTS:
                time.sleep(RETRY_DELAY_SECONDS)
    raise AuditError("GET {} failed after {} attempts: {}".format(url, REQUEST_ATTEMPTS, last_error))


def fetch_json(url):
    """Downloads a URL and decodes it as JSON."""
    try:
        return json.loads(fetch_bytes(url).decode("utf-8"))
    except ValueError as error:
        raise AuditError("GET {} returned invalid JSON: {}".format(url, error))


def live_apps():
    """Returns (trackId, trackName) for every software app the developer account publishes."""
    payload = fetch_json(LIVE_LOOKUP_URL)
    apps = [
        (str(item["trackId"]), item.get("trackName", ""))
        for item in payload.get("results", [])
        if item.get("kind") in LOOKUP_KINDS and item.get("trackId")
    ]
    if not apps:
        raise AuditError("the iTunes lookup returned no software apps for the developer")
    return apps


def catalog_apps(url):
    """Returns the app entries from the deployed catalog at url, or from worker/catalog.json when url is None."""
    if url is None:
        try:
            document = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
        except (OSError, ValueError) as error:
            raise AuditError("cannot read {}: {}".format(CATALOG_PATH, error))
    else:
        document = fetch_json(url)
    return document.get("apps", [])


def audit_lines(live, catalog):
    """Returns the MISSING and STALE report lines comparing live apps with catalog entries."""
    live_ids = {track_id for track_id, _ in live}
    catalog_ids = {str(app.get("appId")) for app in catalog}
    lines = []
    for track_id, track_name in live:
        if track_id not in catalog_ids:
            lines.append("MISSING {} {}".format(track_id, track_name))
    for app in catalog:
        app_id = str(app.get("appId"))
        if app_id not in live_ids and app.get("status") != STATUS_STAGED:
            lines.append("STALE {} {}".format(app_id, app.get("name") or ""))
    return lines


def parse_arguments(argv):
    """Parses the command line flags."""
    parser = argparse.ArgumentParser(description="Audit the Midgar catalog against the developer's live apps.")
    parser.add_argument(
        "--url",
        help="audit the deployed catalog at this URL instead of worker/catalog.json",
    )
    return parser.parse_args(argv)


def run(url):
    """Runs the audit, prints its report and returns the exit code."""
    catalog = catalog_apps(url)
    lines = audit_lines(live_apps(), catalog)
    if lines:
        for line in lines:
            print(line)
        return 1
    print("OK {} apps".format(len(catalog)))
    return 0


def main(argv=None):
    """Runs the audit and returns the process exit code."""
    arguments = parse_arguments(argv)
    try:
        return run(arguments.url)
    except AuditError as error:
        print("ERROR: {}".format(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
