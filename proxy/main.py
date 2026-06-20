import os
import json
import base64
import time
import random
import datetime
import threading
import urllib.request
import urllib.parse
import urllib.error
from http.server import HTTPServer, BaseHTTPRequestHandler

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
GITHUB_PAT = os.environ.get("GITHUB_PAT", "")
REPO = "freecodecollective/matchmondo"
IOS_REPO = "freecodecollective/matchmondo-ios"
FILE_PATH = "data/trivia.json"
GH_API = f"https://api.github.com/repos/{REPO}/contents/{FILE_PATH}"
WORKFLOW_API = f"https://api.github.com/repos/{IOS_REPO}/actions/workflows/process-trivia.yml/dispatches"
RESULTS_URL = f"https://raw.githubusercontent.com/{REPO}/main/data/matches.json"
ALLOWED_ORIGINS = [
    "https://freecodecollective.github.io",
    "http://localhost:8011",
    "http://127.0.0.1:8011",
]

# Two-word join codes (Jackbox style): adjective-animal.
ADJ = ["brave", "lucky", "swift", "golden", "clever", "happy", "bold", "sunny",
       "mighty", "cosmic", "royal", "rapid", "grand", "noble", "wild", "epic",
       "calm", "fierce", "jolly", "spry", "keen", "lush", "mellow", "witty",
       "zesty", "plucky", "snappy", "dapper", "breezy", "feisty"]
ANIM = ["falcon", "panda", "otter", "tiger", "fox", "puffin", "heron", "marlin",
        "lynx", "cobra", "bison", "gecko", "badger", "osprey", "jaguar", "walrus",
        "stork", "raven", "moose", "koala", "viper", "wombat", "manta", "ferret",
        "beaver", "hawk", "seal", "ibis", "crane", "shark"]


# ---------------------------------------------------------------------------
# Trivia helpers (existing behaviour)
# ---------------------------------------------------------------------------
def has_pending_tasks(put_body):
    try:
        content_b64 = json.loads(put_body).get("content", "")
        trivia = json.loads(base64.b64decode(content_b64))
        if any(t.get("status") == "pending" for t in trivia.get("pendingTasks", [])):
            return True
        if any(q.get("claudeTask") for q in trivia.get("questions", [])):
            return True
    except Exception:
        pass
    return False


def trigger_workflow():
    try:
        req = urllib.request.Request(WORKFLOW_API, method="POST", headers={
            "Accept": "application/vnd.github.v3+json",
            "Authorization": f"token {GITHUB_PAT}",
            "Content-Type": "application/json",
            "User-Agent": "trivia-proxy",
        }, data=json.dumps({"ref": "main"}).encode())
        urllib.request.urlopen(req, timeout=10)
        print("Triggered trivia processor workflow")
    except Exception as e:
        print(f"Failed to trigger workflow: {e}")


# ---------------------------------------------------------------------------
# GCP metadata: project id + access token (cached)
# ---------------------------------------------------------------------------
_meta = {}


def project_id():
    if _meta.get("pid"):
        return _meta["pid"]
    pid = os.environ.get("GOOGLE_CLOUD_PROJECT") or os.environ.get("PROJECT_ID")
    if not pid:
        req = urllib.request.Request(
            "http://metadata.google.internal/computeMetadata/v1/project/project-id",
            headers={"Metadata-Flavor": "Google"})
        with urllib.request.urlopen(req, timeout=10) as r:
            pid = r.read().decode()
    _meta["pid"] = pid
    return pid


_tok = {}


def gcp_token():
    now = time.time()
    if _tok.get("exp", 0) > now + 30:
        return _tok["tok"]
    req = urllib.request.Request(
        "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token",
        headers={"Metadata-Flavor": "Google"})
    with urllib.request.urlopen(req, timeout=10) as r:
        d = json.loads(r.read())
    _tok["tok"] = d["access_token"]
    _tok["exp"] = now + int(d.get("expires_in", 3600))
    return _tok["tok"]


# ---------------------------------------------------------------------------
# Firestore REST helpers (no external dependencies)
# ---------------------------------------------------------------------------
def fs_base():
    return f"https://firestore.googleapis.com/v1/projects/{project_id()}/databases/(default)/documents"


def fs(method, rel, body=None, params=None):
    url = fs_base() + rel
    if params:
        url += "?" + urllib.parse.urlencode(params)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": f"Bearer {gcp_token()}",
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, (json.loads(raw) if raw else {})
        except Exception:
            return e.code, {}


def enc(v):
    if isinstance(v, bool):
        return {"booleanValue": v}
    if isinstance(v, int):
        return {"integerValue": str(v)}
    if isinstance(v, str):
        return {"stringValue": v}
    if isinstance(v, dict):
        return {"mapValue": {"fields": {k: enc(x) for k, x in v.items()}}}
    if v is None:
        return {"nullValue": None}
    return {"stringValue": str(v)}


def dec(f):
    if "stringValue" in f:
        return f["stringValue"]
    if "integerValue" in f:
        return int(f["integerValue"])
    if "booleanValue" in f:
        return f["booleanValue"]
    if "timestampValue" in f:
        return f["timestampValue"]
    if "mapValue" in f:
        return {k: dec(x) for k, x in f.get("mapValue", {}).get("fields", {}).items()}
    return None


def docbody(d):
    return {"fields": {k: enc(v) for k, v in d.items()}}


def parse(doc):
    return {k: dec(v) for k, v in (doc or {}).get("fields", {}).items()}


def now_iso():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ---------------------------------------------------------------------------
# Match results (final scores) — fetched from the public repo, cached 60s
# ---------------------------------------------------------------------------
_res = {}


def results():
    now = time.time()
    if "data" in _res and _res.get("ts", 0) > now - 60:
        return _res["data"]
    try:
        with urllib.request.urlopen(RESULTS_URL, timeout=15) as r:
            arr = json.loads(r.read())
        m = {}
        for x in arr:
            if x.get("scoreH") is not None and x.get("scoreA") is not None:
                m[str(x["n"])] = (int(x["scoreH"]), int(x["scoreA"]))
        _res["data"] = m
        _res["ts"] = now
        return m
    except Exception:
        return _res.get("data", {})


def score_pick(pick, actual):
    """Returns (points, exact_hit, result_hit). Exact score +3, correct result +1."""
    aH, aA = actual
    actual_res = "H" if aH > aA else ("A" if aA > aH else "D")
    sh = pick.get("scoreH")
    sa = pick.get("scoreA")
    if sh is not None and sa is not None and int(sh) == aH and int(sa) == aA:
        return 3, 1, 1
    pr = pick.get("result")
    if pr is None and sh is not None and sa is not None:
        pr = "H" if sh > sa else ("A" if sa > sh else "D")
    if pr == actual_res:
        return 1, 0, 1
    return 0, 0, 0


def leaderboard(code):
    st, _grp = fs("GET", f"/groups/{code}")
    if st != 200:
        return None
    st, ml = fs("GET", f"/groups/{code}/members", params={"pageSize": "300"})
    members = ml.get("documents", []) if st == 200 else []
    res = results()
    rows = []
    for mdoc in members:
        did = mdoc["name"].split("/")[-1]
        info = parse(mdoc)
        st, pl = fs("GET", f"/picks/{did}/matches", params={"pageSize": "300"})
        picks = pl.get("documents", []) if st == 200 else []
        pts = ex = rc = graded = 0
        for pdoc in picks:
            mn = pdoc["name"].split("/")[-1]
            if mn not in res:
                continue
            sp, se, sr = score_pick(parse(pdoc), res[mn])
            pts += sp
            ex += se
            rc += sr
            graded += 1
        rows.append({
            "displayName": info.get("displayName", "?"),
            "points": pts, "exact": ex, "results": rc, "graded": graded,
        })
    rows.sort(key=lambda r: (-r["points"], -r["exact"], r["displayName"].lower()))
    for i, r in enumerate(rows):
        r["rank"] = i + 1
    return rows


# ---------------------------------------------------------------------------
# HTTP handler
# ---------------------------------------------------------------------------
class Handler(BaseHTTPRequestHandler):
    def _cors(self):
        origin = self.headers.get("Origin", "")
        if origin in ALLOWED_ORIGINS:
            self.send_header("Access-Control-Allow-Origin", origin)
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Max-Age", "86400")

    def send_json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self._cors()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def read_json(self):
        length = int(self.headers.get("Content-Length", 0))
        if not length:
            return {}
        try:
            return json.loads(self.rfile.read(length) or b"{}")
        except Exception:
            return {}

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    # ---- routing -----------------------------------------------------------
    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        path = u.path
        parts = [p for p in path.split("/") if p]
        if path in ("/", "/healthz"):
            return self.send_json(200, {"ok": True})
        if path == "/api/trivia":
            return self.trivia_get()
        if path == "/api/picks":
            q = urllib.parse.parse_qs(u.query)
            return self.picks_get((q.get("deviceId") or [""])[0])
        if len(parts) == 3 and parts[:2] == ["api", "groups"]:
            return self.group_get(parts[2])
        if len(parts) == 4 and parts[:2] == ["api", "groups"] and parts[3] == "leaderboard":
            return self.leaderboard_get(parts[2])
        self.send_json(404, {"error": "not found"})

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path
        parts = [p for p in path.split("/") if p]
        body = self.read_json()
        if parts == ["api", "groups"]:
            return self.group_create(body)
        if len(parts) == 4 and parts[:2] == ["api", "groups"] and parts[3] == "join":
            return self.group_join(parts[2], body)
        self.send_json(404, {"error": "not found"})

    def do_PUT(self):
        path = urllib.parse.urlparse(self.path).path
        if path == "/api/trivia":
            return self.trivia_put()
        if path == "/api/picks":
            return self.picks_put()
        self.send_json(404, {"error": "not found"})

    # ---- trivia (existing behaviour) --------------------------------------
    def trivia_get(self):
        try:
            req = urllib.request.Request(GH_API, headers={
                "Accept": "application/vnd.github.v3+json",
                "Authorization": f"token {GITHUB_PAT}",
                "User-Agent": "trivia-proxy",
            })
            with urllib.request.urlopen(req, timeout=15) as resp:
                data = resp.read()
            self.send_response(200)
            self._cors()
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(data)
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            self._cors()
            self.end_headers()
            self.wfile.write(e.read())

    def trivia_put(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        pending = has_pending_tasks(body)
        try:
            req = urllib.request.Request(GH_API, data=body, method="PUT", headers={
                "Accept": "application/vnd.github.v3+json",
                "Authorization": f"token {GITHUB_PAT}",
                "Content-Type": "application/json",
                "User-Agent": "trivia-proxy",
            })
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = resp.read()
            self.send_response(200)
            self._cors()
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(data)
            if pending:
                threading.Thread(target=trigger_workflow, daemon=True).start()
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            self._cors()
            self.end_headers()
            self.wfile.write(e.read())

    # ---- groups ------------------------------------------------------------
    def group_create(self, body):
        name = (body.get("name") or "My group").strip()[:60]
        did = body.get("deviceId")
        dn = (body.get("displayName") or "Host").strip()[:40]
        if not did:
            return self.send_json(400, {"error": "deviceId required"})
        code = None
        for _ in range(10):
            cand = f"{random.choice(ADJ)}-{random.choice(ANIM)}"
            st, _r = fs("PATCH", f"/groups/{cand}",
                        body=docbody({"name": name, "createdAt": now_iso(), "createdBy": did}),
                        params={"currentDocument.exists": "false"})
            if st == 200:
                code = cand
                break
        if not code:
            return self.send_json(500, {"error": "could not allocate a code, try again"})
        fs("PATCH", f"/groups/{code}/members/{did}",
           body=docbody({"displayName": dn, "joinedAt": now_iso()}))
        self.send_json(200, {"code": code, "name": name})

    def group_get(self, code):
        st, doc = fs("GET", f"/groups/{code}")
        if st != 200:
            return self.send_json(404, {"error": "group not found"})
        d = parse(doc)
        st, ml = fs("GET", f"/groups/{code}/members", params={"pageSize": "300"})
        n = len(ml.get("documents", [])) if st == 200 else 0
        self.send_json(200, {"code": code, "name": d.get("name"), "members": n})

    def group_join(self, code, body):
        did = body.get("deviceId")
        dn = (body.get("displayName") or "Player").strip()[:40]
        if not did:
            return self.send_json(400, {"error": "deviceId required"})
        st, _ = fs("GET", f"/groups/{code}")
        if st != 200:
            return self.send_json(404, {"error": "group not found"})
        fs("PATCH", f"/groups/{code}/members/{did}",
           body=docbody({"displayName": dn, "joinedAt": now_iso()}))
        self.send_json(200, {"ok": True, "code": code})

    def leaderboard_get(self, code):
        rows = leaderboard(code)
        if rows is None:
            return self.send_json(404, {"error": "group not found"})
        st, doc = fs("GET", f"/groups/{code}")
        self.send_json(200, {"code": code, "name": parse(doc).get("name"), "leaderboard": rows})

    # ---- picks -------------------------------------------------------------
    def picks_put(self):
        b = self.read_json()
        did = b.get("deviceId")
        mn = b.get("matchN")
        if not did or mn is None:
            return self.send_json(400, {"error": "deviceId and matchN required"})
        doc = {"updatedAt": now_iso()}
        if b.get("result") in ("H", "D", "A"):
            doc["result"] = b["result"]
        if isinstance(b.get("scoreH"), int):
            doc["scoreH"] = b["scoreH"]
        if isinstance(b.get("scoreA"), int):
            doc["scoreA"] = b["scoreA"]
        st, r = fs("PATCH", f"/picks/{did}/matches/{str(mn)}", body=docbody(doc))
        if st != 200:
            return self.send_json(st, {"error": "save failed", "detail": r})
        self.send_json(200, {"ok": True})

    def picks_get(self, did):
        if not did:
            return self.send_json(400, {"error": "deviceId required"})
        st, pl = fs("GET", f"/picks/{did}/matches", params={"pageSize": "300"})
        out = {}
        for pdoc in pl.get("documents", []):
            out[pdoc["name"].split("/")[-1]] = parse(pdoc)
        self.send_json(200, {"deviceId": did, "picks": out})

    def log_message(self, fmt, *args):
        print(f"{self.client_address[0]} - {fmt % args}")


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    server = HTTPServer(("0.0.0.0", port), Handler)
    print(f"Proxy listening on :{port}")
    server.serve_forever()
