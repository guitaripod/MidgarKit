"""Generates worker/catalog.json, the bundled fallback catalog and fallback icons.

Reads worker/catalog.meta.json for editorial metadata, looks every app up once on the iTunes lookup API, and merges the live data into the existing worker/catalog.json entries. Run with `python3 -I worker/scripts/gen_catalog.py`; pass `--check` to report whether any output would change (ignoring updatedAt) without writing anything.
"""

import argparse
import collections
import copy
import datetime
import io
import json
import pathlib
import re
import site
import sys
import time
import urllib.request


ROOT = pathlib.Path(__file__).resolve().parents[2]
WORKER_DIR = ROOT / "worker"
CATALOG_PATH = WORKER_DIR / "catalog.json"
META_PATH = WORKER_DIR / "catalog.meta.json"
FALLBACK_PATH = ROOT / "Sources" / "MidgarPortal" / "Resources" / "catalog.fallback.json"
ICON_DIR = ROOT / "Sources" / "MidgarPortal" / "Resources" / "fallback-icons"

LOOKUP_URL = "https://itunes.apple.com/lookup"
LOOKUP_KINDS = ("software", "mac-software")
USER_AGENT = "midgar-catalog-tools/1.0"
REQUEST_TIMEOUT_SECONDS = 20
REQUEST_ATTEMPTS = 2
RETRY_DELAY_SECONDS = 2

SCREENSHOT_LIMIT = 5
FALLBACK_SCREENSHOT_LIMIT = 3
ICON_SIZE = 256
VALID_PLATFORMS = ("ios", "mac", "tvos", "vision")
SLOT_PATTERN = re.compile(r"^midgar-(0[1-9]|[12][0-9]|30)$")
ACCENT_PATTERN = re.compile(r"^#[0-9A-Fa-f]{6}$")
APP_KEY_ORDER = (
    "appId",
    "bundleId",
    "name",
    "tagline",
    "genre",
    "accent",
    "family",
    "platforms",
    "topics",
    "related",
    "value",
    "featured",
    "order",
    "scheme",
    "slot",
    "status",
    "icon",
    "screenshots",
)
DOCUMENT_KEY_ORDER = ("version", "updatedAt", "developer", "apps")
STATUS_LIVE = "live"
STATUS_STAGED = "staged"


class CatalogError(Exception):
    """A fatal problem that stops catalog generation before anything is written."""


def load_pillow():
    """Imports PIL and returns the Image module.

    `python3 -I` removes the user site-packages directory from sys.path, and Pillow is installed there for this interpreter. The user site is appended after the standard library only when the first import fails, so it can supply Pillow but cannot shadow stdlib modules.
    """
    try:
        from PIL import Image
    except ImportError:
        user_site = site.getusersitepackages()
        if user_site not in sys.path:
            sys.path.append(user_site)
        try:
            from PIL import Image
        except ImportError as error:
            raise CatalogError("Pillow is required to build fallback icons: {}".format(error))
    return Image


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
    raise CatalogError("GET {} failed after {} attempts: {}".format(url, REQUEST_ATTEMPTS, last_error))


def fetch_json(url):
    """Downloads a URL and decodes it as JSON."""
    try:
        return json.loads(fetch_bytes(url).decode("utf-8"))
    except ValueError as error:
        raise CatalogError("GET {} returned invalid JSON: {}".format(url, error))


def lookup_url(app_ids):
    """Builds the single iTunes lookup URL covering every app id in the meta file."""
    return "{}?id={}&country=us&limit=200".format(LOOKUP_URL, ",".join(app_ids))


def software_by_track_id(payload):
    """Maps each trackId string to its software result from an iTunes lookup payload."""
    return {
        str(item["trackId"]): item
        for item in payload.get("results", [])
        if item.get("kind") in LOOKUP_KINDS and item.get("trackId")
    }


def load_json(path):
    """Reads and decodes a JSON file from disk."""
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise CatalogError("cannot read {}: {}".format(path, error))


def utc_now():
    """Returns the current UTC time as an ISO-8601 string ending in Z."""
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def merge_app(meta_app, existing, live):
    """Combines meta, the existing catalog entry and live iTunes data for one app.

    Meta fields always win. Name and genre come from live data only when missing, screenshots are taken from the live iPhone screenshots only when the entry has none, icon is always null, and status records whether the app was returned by the lookup.
    """
    merged = dict(existing)
    merged.update(meta_app)
    live = live or {}
    if not merged.get("name"):
        merged["name"] = live.get("trackName")
    if not merged.get("genre"):
        merged["genre"] = live.get("primaryGenreName")
    if not merged.get("screenshots"):
        merged["screenshots"] = list(live.get("screenshotUrls") or [])[:SCREENSHOT_LIMIT]
    merged["icon"] = None
    merged["status"] = STATUS_LIVE if live else STATUS_STAGED
    return merged


def check_live_app(meta_app, live, problems):
    """Records a problem when the live app disagrees with the meta bundleId or platforms."""
    label = describe(meta_app)
    if live.get("bundleId") != meta_app.get("bundleId"):
        problems.append(
            "{} bundleId mismatch: meta says {}, live says {}".format(
                label, meta_app.get("bundleId"), live.get("bundleId")
            )
        )
    if live.get("kind") == "mac-software" and "mac" not in meta_app.get("platforms", []):
        problems.append("{} is a live mac-software app but its platforms lack mac".format(label))


def describe(app):
    """Returns a short label for an app that is safe to print in error messages."""
    return "{} ({})".format(app.get("name") or app.get("appId"), app.get("bundleId"))


def ordered_app(app):
    """Returns the app dict with known keys in the canonical order, unknown keys sorted after them."""
    keys = [key for key in APP_KEY_ORDER if key in app]
    keys += sorted(key for key in app if key not in APP_KEY_ORDER)
    return {key: app[key] for key in keys}


def build_document(meta, existing_by_id, live_by_id, problems):
    """Builds the full catalog document from meta, the existing catalog and live lookup data."""
    apps = []
    for meta_app in meta["apps"]:
        app_id = str(meta_app["appId"])
        live = live_by_id.get(app_id)
        if live is None:
            print("WARNING: {} was not returned by the lookup, marking it staged".format(describe(meta_app)), file=sys.stderr)
        else:
            check_live_app(meta_app, live, problems)
        apps.append(merge_app(meta_app, existing_by_id.get(app_id, {}), live))
    apps.sort(key=lambda app: app.get("order", 0))
    document = {
        "version": meta["version"],
        "updatedAt": utc_now(),
        "developer": meta["developer"],
        "apps": [ordered_app(app) for app in apps],
    }
    if meta.get("hide"):
        document["hide"] = list(meta["hide"])
    return document


def find_duplicates(label, values):
    """Returns one problem per value that occurs more than once."""
    counts = collections.Counter(values)
    return ["duplicate {} {}".format(label, value) for value, count in counts.items() if count > 1]


def validate_schemes(apps):
    """Returns problems with the URL schemes hosts must list: slots well formed, schemes unique.

    `slot` is the reserved scheme an existing app registers beside its bundle-id scheme. `scheme`
    is for apps whose only scheme is a reserved slot, so an entry never carries both.
    """
    problems = []
    for app in apps:
        for key in ("scheme", "slot"):
            value = app.get(key)
            if value is not None and not SLOT_PATTERN.match(value):
                problems.append("{} has {} {!r}, which is not a reserved slot midgar-01 to midgar-30".format(describe(app), key, value))
        if app.get("scheme") and app.get("slot"):
            problems.append("{} has both scheme and slot; use scheme only when the slot is the app's only scheme".format(describe(app)))
    effective = [(app.get("scheme") or app.get("bundleId", "")).lower() for app in apps]
    problems += find_duplicates("URL scheme", effective)
    claimed = [app["slot"].lower() for app in apps if app.get("slot")] + [app["scheme"].lower() for app in apps if app.get("scheme")]
    problems += find_duplicates("reserved slot", claimed)
    return problems


def validate_document(document):
    """Returns every validation problem in the document, or an empty list when it is valid."""
    apps = document["apps"]
    problems = []
    problems += find_duplicates("appId", [app.get("appId") for app in apps])
    problems += find_duplicates("bundleId", [app.get("bundleId") for app in apps])
    problems += validate_schemes(apps)
    bundle_ids = {app.get("bundleId") for app in apps}
    for app in apps:
        label = describe(app)
        for related in app.get("related", []):
            if related not in bundle_ids:
                problems.append("{} lists related bundleId {} which is not in the catalog".format(label, related))
        for platform in app.get("platforms", []):
            if platform not in VALID_PLATFORMS:
                problems.append("{} has platform {} which is not one of {}".format(label, platform, ", ".join(VALID_PLATFORMS)))
        accent = app.get("accent")
        if not isinstance(accent, str) or not ACCENT_PATTERN.match(accent):
            problems.append("{} has no valid accent (found {!r})".format(label, accent))
    return problems


def fallback_document(document):
    """Returns a copy of the document with each app's screenshots trimmed for the bundled file."""
    fallback = copy.deepcopy(document)
    for app in fallback["apps"]:
        app["screenshots"] = app.get("screenshots", [])[:FALLBACK_SCREENSHOT_LIMIT]
    return fallback


def render_json(document):
    """Serialises a document as 2-space indented JSON with a trailing newline."""
    return json.dumps(document, indent=2, ensure_ascii=False) + "\n"


def without_timestamp(document):
    """Returns the document without its updatedAt key, so only content changes count."""
    return {key: value for key, value in document.items() if key != "updatedAt"}


def render_icon(Image, data):
    """Resizes downloaded artwork to a square RGBA PNG and returns the encoded bytes."""
    with Image.open(io.BytesIO(data)) as source:
        resized = source.convert("RGBA").resize((ICON_SIZE, ICON_SIZE), Image.Resampling.LANCZOS)
    buffer = io.BytesIO()
    resized.save(buffer, format="PNG")
    return buffer.getvalue()


def build_icons(Image, meta, live_by_id):
    """Downloads and renders the icon of every live app, keyed by its destination path."""
    icons = {}
    for meta_app in meta["apps"]:
        app_id = str(meta_app["appId"])
        live = live_by_id.get(app_id)
        if live is None:
            continue
        artwork_url = live.get("artworkUrl512")
        if not artwork_url:
            raise CatalogError("{} has no artworkUrl512 in the lookup".format(describe(meta_app)))
        icons[ICON_DIR / "{}.png".format(app_id)] = render_icon(Image, fetch_bytes(artwork_url))
    return icons


def json_changed(path, document):
    """Reports whether the file on disk differs from the document, ignoring updatedAt."""
    if not path.exists():
        return True
    try:
        previous = json.loads(path.read_text(encoding="utf-8"))
    except ValueError:
        return True
    return render_json(without_timestamp(previous)) != render_json(without_timestamp(document))


def icon_changed(path, data):
    """Reports whether the icon file on disk differs from the rendered bytes."""
    return not path.exists() or path.read_bytes() != data


def check_outputs(json_outputs, icons):
    """Prints CHANGED or UNCHANGED for every output and returns the number of changed files."""
    changed = 0
    for path, document in json_outputs:
        is_changed = json_changed(path, document)
        changed += is_changed
        print("{} {}".format("CHANGED" if is_changed else "UNCHANGED", path))
    for path, data in icons.items():
        is_changed = icon_changed(path, data)
        changed += is_changed
        print("{} {}".format("CHANGED" if is_changed else "UNCHANGED", path))
    return changed


def write_outputs(json_outputs, icons):
    """Writes the JSON documents and the fallback icons to disk."""
    for path, document in json_outputs:
        path.write_text(render_json(document), encoding="utf-8")
        print("WROTE {}".format(path))
    ICON_DIR.mkdir(parents=True, exist_ok=True)
    for path, data in icons.items():
        path.write_bytes(data)
        print("WROTE {}".format(path))


def parse_arguments(argv):
    """Parses the command line flags."""
    parser = argparse.ArgumentParser(description="Generate worker/catalog.json, the fallback catalog and fallback icons.")
    parser.add_argument(
        "--check",
        action="store_true",
        help="write nothing; exit 1 if any output would change other than updatedAt",
    )
    return parser.parse_args(argv)


def run(check):
    """Generates every output and writes them, or only reports changes when check is set."""
    Image = load_pillow()
    meta = load_json(META_PATH)
    existing = load_json(CATALOG_PATH) if CATALOG_PATH.exists() else {"apps": []}
    existing_by_id = {str(app.get("appId")): app for app in existing.get("apps", [])}
    app_ids = [str(app["appId"]) for app in meta["apps"]]
    live_by_id = software_by_track_id(fetch_json(lookup_url(app_ids)))

    problems = []
    document = build_document(meta, existing_by_id, live_by_id, problems)
    problems += validate_document(document)
    if problems:
        for problem in problems:
            print("ERROR: {}".format(problem), file=sys.stderr)
        return 1

    json_outputs = [(CATALOG_PATH, document), (FALLBACK_PATH, fallback_document(document))]
    icons = build_icons(Image, meta, live_by_id)

    if check:
        changed = check_outputs(json_outputs, icons)
        print("CHECK {} file(s) would change".format(changed))
        return 1 if changed else 0

    write_outputs(json_outputs, icons)
    for app in document["apps"]:
        print("{} {} {}".format(app["status"], app["appId"], app["bundleId"]))
    print("OK {} apps".format(len(document["apps"])))
    return 0


def main(argv=None):
    """Runs the generator and returns the process exit code."""
    arguments = parse_arguments(argv)
    try:
        return run(arguments.check)
    except CatalogError as error:
        print("ERROR: {}".format(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
