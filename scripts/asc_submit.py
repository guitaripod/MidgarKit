import time, json, os, sys, argparse, urllib.request, urllib.error
import jwt

KEY_ID = "DSS2FFU68G"
ISSUER = "a5ebdab5-0ceb-463c-8151-195b902f117b"
P8 = os.path.expanduser("~/.appstoreconnect/private_keys/AuthKey_DSS2FFU68G.p8")
BASE = "https://api.appstoreconnect.apple.com"

EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}
IN_REVIEW = {"WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE"}
ACTIVE_SUBMISSION = {"READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES"}


def token():
    return jwt.encode({"iss": ISSUER, "iat": int(time.time()), "exp": int(time.time()) + 1100, "aud": "appstoreconnect-v1"},
                      open(P8).read(), algorithm="ES256", headers={"kid": KEY_ID})


TOK = token()


def req(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(BASE + path, data=data, method=method,
                               headers={"Authorization": "Bearer " + TOK, "Content-Type": "application/json"})
    try:
        resp = urllib.request.urlopen(r, timeout=60)
        raw = resp.read()
        return resp.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"_raw": raw[:300]}


def log(msg):
    print(msg, flush=True)


def errstr(body):
    if isinstance(body, dict) and body.get("errors"):
        return "; ".join(f"{e.get('title')}: {e.get('detail')}" for e in body["errors"])[:300]
    return str(body)[:300]


def get_build(app_id, cfbundle, platform):
    _, b = req("GET", f"/v1/builds?filter[app]={app_id}&filter[version]={cfbundle}&include=preReleaseVersion&limit=20")
    included = {i["id"]: i for i in b.get("included", [])}
    for build in b.get("data", []):
        ref = build.get("relationships", {}).get("preReleaseVersion", {}).get("data")
        if ref and included.get(ref["id"], {}).get("attributes", {}).get("platform") == platform:
            return build
    data = b.get("data", [])
    return data[0] if len(data) == 1 else None


def find_version(app_id, version_string, platform):
    _, v = req("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]={platform}&limit=10")
    for ver in v.get("data", []):
        if ver["attributes"].get("versionString") == version_string:
            return ver
    return None


def create_version(app_id, version_string, platform):
    status, v = req("POST", "/v1/appStoreVersions", {
        "data": {"type": "appStoreVersions",
                 "attributes": {"platform": platform, "versionString": version_string, "releaseType": "AFTER_APPROVAL"},
                 "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
    if status >= 300:
        log(f"  create_version FAILED {status}: {errstr(v)}")
        return None
    return v["data"]


def cancel_active_submission(app_id, platform):
    _, subs = req("GET", f"/v1/reviewSubmissions?filter[app]={app_id}&limit=20")
    for s in subs.get("data", []):
        state = s["attributes"].get("state")
        if state in ACTIVE_SUBMISSION and s["attributes"].get("platform") == platform:
            sid = s["id"]
            status, body = req("PATCH", f"/v1/reviewSubmissions/{sid}",
                               {"data": {"type": "reviewSubmissions", "id": sid, "attributes": {"canceled": True}}})
            log(f"  cancel submission {sid} ({state}) -> {status}")
            return True
    return False


def set_export_compliance(build_id):
    status, body = req("PATCH", f"/v1/builds/{build_id}",
                       {"data": {"type": "builds", "id": build_id, "attributes": {"usesNonExemptEncryption": False}}})
    log(f"  export-compliance usesNonExemptEncryption=false -> {status}")


def attach_build(version_id, build_id):
    status, body = req("PATCH", f"/v1/appStoreVersions/{version_id}/relationships/build",
                       {"data": {"type": "builds", "id": build_id}})
    log(f"  attach build -> {status}" + ("" if status < 300 else f" {errstr(body)}"))
    return status < 300


def set_whats_new(version_id, text):
    _, locs = req("GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations?limit=50")
    for loc in locs.get("data", []):
        lid = loc["id"]
        req("PATCH", f"/v1/appStoreVersionLocalizations/{lid}",
            {"data": {"type": "appStoreVersionLocalizations", "id": lid, "attributes": {"whatsNew": text}}})
    log(f"  set whatsNew on {len(locs.get('data', []))} localizations")


def submit(app_id, version_id, platform):
    for attempt in range(4):
        status, rs = req("POST", "/v1/reviewSubmissions",
                         {"data": {"type": "reviewSubmissions", "attributes": {"platform": platform},
                                   "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
        if status < 300:
            break
        log(f"  create reviewSubmission attempt {attempt+1} -> {status}: {errstr(rs)}")
        if status == 409:
            time.sleep(45); continue
        return False
    rsid = rs["data"]["id"]
    for attempt in range(4):
        status, item = req("POST", "/v1/reviewSubmissionItems",
                           {"data": {"type": "reviewSubmissionItems",
                                     "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": rsid}},
                                                       "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}}}})
        if status < 300:
            break
        log(f"  add item attempt {attempt+1} -> {status}: {errstr(item)}")
        if status == 409:
            time.sleep(45); continue
        return False
    status, done = req("PATCH", f"/v1/reviewSubmissions/{rsid}",
                       {"data": {"type": "reviewSubmissions", "id": rsid, "attributes": {"submitted": True}}})
    log(f"  SUBMIT -> {status}" + ("" if status < 300 else f": {errstr(done)}"))
    return status < 300


def run(app_id, cfbundle, version_string, whats_new, platform):
    log(f"== app {app_id}  build {cfbundle}  version {version_string}  platform {platform} ==")
    build = get_build(app_id, cfbundle, platform)
    if not build:
        log("  build not found in ASC yet"); return False
    if build["attributes"].get("processingState") != "VALID":
        log(f"  build state {build['attributes'].get('processingState')} (not VALID)"); return False
    build_id = build["id"]

    ver = find_version(app_id, version_string, platform)
    if ver and ver["attributes"]["appStoreState"] in IN_REVIEW:
        cancel_active_submission(app_id, platform)
        time.sleep(8)
    elif ver is None:
        ver = create_version(app_id, version_string, platform)
        if not ver:
            return False

    version_id = ver["id"]
    set_export_compliance(build_id)
    if not attach_build(version_id, build_id):
        time.sleep(10)
        attach_build(version_id, build_id)
    if whats_new:
        set_whats_new(version_id, whats_new)
    return submit(app_id, version_id, platform)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("app_id")
    ap.add_argument("cfbundle")
    ap.add_argument("version")
    ap.add_argument("--whatsnew", default="")
    ap.add_argument("--platform", default="IOS", choices=["IOS", "MAC_OS", "VISION_OS"])
    a = ap.parse_args()
    ok = run(a.app_id, a.cfbundle, a.version, a.whatsnew, a.platform)
    sys.exit(0 if ok else 1)
