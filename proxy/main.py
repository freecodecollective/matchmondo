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
WORKFLOW_API = f"https://api.github.com/repos/{REPO}/actions/workflows/process-trivia.yml/dispatches"
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

# Friend codes (NYT-style): two short football words/players, dash-joined, e.g.
# "saka-volley". Short and easy to read aloud or text.
FRIEND_WORDS = [
    "goal", "pitch", "volley", "header", "cross", "keeper", "striker", "net",
    "chip", "derby", "corner", "flick", "pace", "boot", "post", "save", "wing",
    "pass", "tackle", "kit", "offside", "pitch", "free", "kick", "bicycle",
    "messi", "kane", "saka", "vini", "son", "rice", "foden", "yamal", "pedri",
    "rodri", "modric", "musiala", "haaland", "mbappe", "neymar", "kroos",
    "gavi", "salah", "kante", "mount", "pulisic", "bellingham",
]


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


def trigger_workflow(delay=8):
    if delay:
        time.sleep(delay)
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


def predict_points(did):
    """A device's prediction tally, graded against final scores."""
    res = results()
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
    return {"points": pts, "exact": ex, "results": rc, "graded": graded}


def predict_points_pool(did, start_iso, pred_exact=3, pred_result=1):
    """Like predict_points but only counts matches with kickoff >= start_iso
    and uses custom point values."""
    res = results()
    st, pl = fs("GET", f"/picks/{did}/matches", params={"pageSize": "300"})
    picks = pl.get("documents", []) if st == 200 else []
    all_matches = _all_matches()
    pts = ex = rc = graded = 0
    for pdoc in picks:
        mn = pdoc["name"].split("/")[-1]
        if mn not in res:
            continue
        m = all_matches.get(int(mn)) if mn.isdigit() else None
        if m and start_iso and m.get("utc", "") < start_iso:
            continue
        sp, se, sr = score_pick(parse(pdoc), res[mn])
        if se:
            pts += pred_exact
        elif sr:
            pts += pred_result
        ex += se
        rc += sr
        graded += 1
    return {"points": pts, "exact": ex, "results": rc, "graded": graded}


_matches_cache = {}


def _all_matches():
    """Cached dict of match n → match object from matches.json."""
    now = time.time()
    if "data" in _matches_cache and _matches_cache.get("ts", 0) > now - 60:
        return _matches_cache["data"]
    try:
        with urllib.request.urlopen(RESULTS_URL, timeout=15) as r:
            arr = json.loads(r.read())
        m = {int(x["n"]): x for x in arr if "n" in x}
        _matches_cache["data"] = m
        _matches_cache["ts"] = now
        return m
    except Exception:
        return _matches_cache.get("data", {})


def leaderboard(code):
    st, grp_doc = fs("GET", f"/groups/{code}")
    if st != 200:
        return None
    grp = parse(grp_doc)
    pool_type = grp.get("type", "both")
    pred_exact = int(grp.get("predExact", 3))
    pred_result = int(grp.get("predResult", 1))
    trivia_pts = int(grp.get("triviaCorrect", 1))
    pool_start = grp.get("startDate")

    st, ml = fs("GET", f"/groups/{code}/members", params={"pageSize": "300"})
    members = ml.get("documents", []) if st == 200 else []
    rows = []
    for mdoc in members:
        did = mdoc["name"].split("/")[-1]
        info = parse(mdoc)
        member_joined = info.get("joinedAt", "")
        effective_start = max(pool_start or "", member_joined) or None

        st_u, udoc = fs("GET", f"/users/{did}")
        user_info = parse(udoc) if st_u == 200 else {}
        live_name = user_info.get("displayName") or info.get("displayName", "?")

        predict = 0
        trivia = 0
        exact = 0
        pred_results = 0
        graded = 0

        if pool_type in ("predictions", "both"):
            pp = predict_points_pool(did, effective_start, pred_exact, pred_result)
            predict = pp["points"]
            exact = pp["exact"]
            pred_results = pp["results"]
            graded = pp["graded"]

        if pool_type in ("trivia", "both"):
            user_trivia = int(user_info.get("triviaCorrect", 0))
            baseline = int(info.get("triviaBaseline", 0))
            trivia = max(0, user_trivia - baseline) * trivia_pts

        rows.append({
            "displayName": live_name,
            "predict": predict, "trivia": trivia,
            "points": predict + trivia,
            "exact": exact, "results": pred_results, "graded": graded,
        })
    rows.sort(key=lambda r: (-r["points"], -r["exact"], r["displayName"].lower()))
    for i, r in enumerate(rows):
        r["rank"] = i + 1
    return rows


# ---------------------------------------------------------------------------
# Friends (NYT-style): each device registers a profile with a unique friend
# code; adding a friend by code creates a mutual link; the leaderboard compares
# you + your friends on prediction points (graded server-side) and trivia score
# (synced from the app, since trivia is otherwise device-local).
# ---------------------------------------------------------------------------
def fs_merge(rel, fields):
    """PATCH that updates only the given fields (Firestore merge), instead of
    replacing the whole document."""
    mask = [("updateMask.fieldPaths", k) for k in fields.keys()]
    return fs("PATCH", rel, body=docbody(fields), params=mask)


def gen_unique_code(did):
    """Allocate an unused friend code and claim it for this device."""
    for _ in range(14):
        a = random.choice(FRIEND_WORDS)
        b = random.choice(FRIEND_WORDS)
        if a == b:
            continue
        cand = f"{a}-{b}"
        st, _ = fs("PATCH", f"/codes/{cand}",
                   body=docbody({"deviceId": did, "createdAt": now_iso()}),
                   params={"currentDocument.exists": "false"})
        if st == 200:
            return cand
    return None


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
        if path == "/api/me":
            q = urllib.parse.parse_qs(u.query)
            return self.me_get((q.get("deviceId") or [""])[0])
        if path == "/api/friends/leaderboard":
            q = urllib.parse.parse_qs(u.query)
            return self.friends_leaderboard_get((q.get("deviceId") or [""])[0])
        if path == "/api/global-leaderboard":
            q = urllib.parse.parse_qs(u.query)
            return self.global_leaderboard_get((q.get("deviceId") or [""])[0])
        if parts == ["api", "groups", "mine"]:
            q = urllib.parse.parse_qs(u.query)
            return self.groups_mine((q.get("deviceId") or [""])[0])
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
        if len(parts) == 4 and parts[:2] == ["api", "groups"] and parts[3] == "leave":
            return self.group_leave(parts[2], body)
        if parts == ["api", "trivia", "process"]:
            return self.trivia_process()
        if parts == ["api", "me"]:
            return self.me_post(body)
        if parts == ["api", "friends", "add"]:
            return self.friend_add(body)
        if parts == ["api", "devices"]:
            return self.devices_register(body)
        if parts == ["api", "internal", "notify-ft"]:
            return self.notify_ft(body)
        self.send_json(404, {"error": "not found"})

    def do_PATCH(self):
        path = urllib.parse.urlparse(self.path).path
        parts = [p for p in path.split("/") if p]
        body = self.read_json()
        if len(parts) == 3 and parts[:2] == ["api", "groups"]:
            return self.group_update(parts[2], body)
        self.send_json(404, {"error": "not found"})

    def do_DELETE(self):
        u = urllib.parse.urlparse(self.path)
        path = u.path
        parts = [p for p in path.split("/") if p]
        q = urllib.parse.parse_qs(u.query)
        if len(parts) == 3 and parts[:2] == ["api", "groups"]:
            return self.group_delete(parts[2], (q.get("deviceId") or [""])[0])
        self.send_json(404, {"error": "not found"})

    def do_PUT(self):
        path = urllib.parse.urlparse(self.path).path
        if path == "/api/trivia":
            return self.trivia_put()
        if path == "/api/picks":
            return self.picks_put()
        if path == "/api/trivia-score":
            return self.trivia_score_put()
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

    def trivia_process(self):
        threading.Thread(target=trigger_workflow, kwargs={"delay": 0}, daemon=True).start()
        self.send_json(200, {"ok": True, "message": "Workflow triggered"})

    # ---- groups (pools) -----------------------------------------------------
    def group_create(self, body):
        name = (body.get("name") or "My Pool").strip()[:60]
        did = body.get("deviceId")
        dn = (body.get("displayName") or "Host").strip()[:40]
        if not did:
            return self.send_json(400, {"error": "deviceId required"})
        pool_type = body.get("type", "both")
        if pool_type not in ("predictions", "trivia", "both"):
            pool_type = "both"
        pred_exact = max(0, min(10, int(body.get("predExact", 3))))
        pred_result = max(0, min(10, int(body.get("predResult", 1))))
        trivia_correct = max(0, min(10, int(body.get("triviaCorrect", 1))))
        start_date = (body.get("startDate") or "").strip()[:24]

        code = None
        for _ in range(10):
            cand = f"{random.choice(ADJ)}-{random.choice(ANIM)}"
            icon = (body.get("icon") or "⚽").strip()[:8]
        doc = {
                "name": name, "createdAt": now_iso(), "createdBy": did,
                "type": pool_type, "icon": icon,
                "predExact": pred_exact, "predResult": pred_result,
                "triviaCorrect": trivia_correct,
            }
            if start_date:
                doc["startDate"] = start_date
            st, _r = fs("PATCH", f"/groups/{cand}",
                        body=docbody(doc),
                        params={"currentDocument.exists": "false"})
            if st == 200:
                code = cand
                break
        if not code:
            return self.send_json(500, {"error": "could not allocate a code, try again"})
        # Snapshot trivia baseline for the creator
        trivia_baseline = 0
        st2, udoc = fs("GET", f"/users/{did}")
        if st2 == 200:
            trivia_baseline = int(parse(udoc).get("triviaCorrect", 0))
        fs("PATCH", f"/groups/{code}/members/{did}",
           body=docbody({"displayName": dn, "joinedAt": now_iso(),
                         "triviaBaseline": trivia_baseline}))
        self.send_json(200, {"code": code, "name": name})

    def group_get(self, code):
        st, doc = fs("GET", f"/groups/{code}")
        if st != 200:
            return self.send_json(404, {"error": "group not found"})
        d = parse(doc)
        st, ml = fs("GET", f"/groups/{code}/members", params={"pageSize": "300"})
        n = len(ml.get("documents", [])) if st == 200 else 0
        self.send_json(200, {
            "code": code, "name": d.get("name"), "members": n,
            "type": d.get("type", "both"),
            "icon": d.get("icon", "⚽"),
            "predExact": int(d.get("predExact", 3)),
            "predResult": int(d.get("predResult", 1)),
            "triviaCorrect": int(d.get("triviaCorrect", 1)),
            "startDate": d.get("startDate", ""),
            "createdBy": d.get("createdBy", ""),
        })

    def group_join(self, code, body):
        did = body.get("deviceId")
        dn = (body.get("displayName") or "Player").strip()[:40]
        if not did:
            return self.send_json(400, {"error": "deviceId required"})
        st, _ = fs("GET", f"/groups/{code}")
        if st != 200:
            return self.send_json(404, {"error": "group not found"})
        trivia_baseline = 0
        st2, udoc = fs("GET", f"/users/{did}")
        if st2 == 200:
            trivia_baseline = int(parse(udoc).get("triviaCorrect", 0))
        fs("PATCH", f"/groups/{code}/members/{did}",
           body=docbody({"displayName": dn, "joinedAt": now_iso(),
                         "triviaBaseline": trivia_baseline}))
        self.send_json(200, {"ok": True, "code": code})

    def group_delete(self, code, did):
        if not did:
            return self.send_json(400, {"error": "deviceId required"})
        st, doc = fs("GET", f"/groups/{code}")
        if st != 200:
            return self.send_json(404, {"error": "group not found"})
        d = parse(doc)
        if d.get("createdBy") != did:
            return self.send_json(403, {"error": "only the pool creator can delete it"})
        st, ml = fs("GET", f"/groups/{code}/members", params={"pageSize": "300"})
        if st == 200:
            for mdoc in ml.get("documents", []):
                mid = mdoc["name"].split("/")[-1]
                fs("DELETE", f"/groups/{code}/members/{mid}")
        fs("DELETE", f"/groups/{code}")
        self.send_json(200, {"ok": True})

    def group_update(self, code, body):
        did = body.get("deviceId")
        if not did:
            return self.send_json(400, {"error": "deviceId required"})
        st, doc = fs("GET", f"/groups/{code}")
        if st != 200:
            return self.send_json(404, {"error": "group not found"})
        d = parse(doc)
        if d.get("createdBy") != did:
            return self.send_json(403, {"error": "only the pool creator can edit it"})
        if "name" in body:
            d["name"] = (body["name"] or "My Pool").strip()[:60]
        if "type" in body and body["type"] in ("predictions", "trivia", "both"):
            d["type"] = body["type"]
        if "predExact" in body:
            d["predExact"] = max(0, min(10, int(body["predExact"])))
        if "predResult" in body:
            d["predResult"] = max(0, min(10, int(body["predResult"])))
        if "triviaCorrect" in body:
            d["triviaCorrect"] = max(0, min(10, int(body["triviaCorrect"])))
        if "startDate" in body:
            d["startDate"] = (body["startDate"] or "").strip()[:24]
        if "icon" in body:
            d["icon"] = (body["icon"] or "⚽").strip()[:8]
        fs("PATCH", f"/groups/{code}", body=docbody(d))
        self.send_json(200, {"ok": True})

    def group_leave(self, code, body):
        did = body.get("deviceId")
        if not did:
            return self.send_json(400, {"error": "deviceId required"})
        st, doc = fs("GET", f"/groups/{code}")
        if st != 200:
            return self.send_json(404, {"error": "group not found"})
        d = parse(doc)
        if d.get("createdBy") == did:
            return self.send_json(403, {"error": "creator cannot leave — delete the pool instead"})
        fs("DELETE", f"/groups/{code}/members/{did}")
        self.send_json(200, {"ok": True})

    def groups_mine(self, did):
        if not did:
            return self.send_json(400, {"error": "deviceId required"})
        query = {
            "structuredQuery": {
                "from": [{"collectionId": "members", "allDescendants": True}],
                "where": {
                    "fieldFilter": {
                        "field": {"fieldPath": "__name__"},
                        "op": "EQUAL",
                        "value": {"referenceValue":
                            f"{fs_base()}/groups/__PLACEHOLDER__/members/{did}"},
                    }
                },
            }
        }
        # Firestore doesn't support a cross-collection member lookup in a single
        # structured query the way we need. Instead, we use a collection-group
        # query approach: list all groups and check membership. For the expected
        # scale (< 1000 groups total) this is fine.
        # Alternative: maintain a /users/{did}/pools sub-collection as an index.
        # For now, scan the user's known pools from a lightweight index.
        #
        # Simpler approach: keep a pools list in the user doc.
        # But since we don't have that yet, scan all groups for this device.
        # This won't scale but works fine for the tournament's lifespan.
        st, gl = fs("GET", "/groups", params={"pageSize": "500"})
        if st != 200:
            return self.send_json(200, {"pools": []})
        pools = []
        for gdoc in gl.get("documents", []):
            gcode = gdoc["name"].split("/")[-1]
            st2, mdoc = fs("GET", f"/groups/{gcode}/members/{did}")
            if st2 == 200:
                g = parse(gdoc)
                st3, ml = fs("GET", f"/groups/{gcode}/members", params={"pageSize": "300"})
                n = len(ml.get("documents", [])) if st3 == 200 else 0
                pools.append({
                    "code": gcode, "name": g.get("name", ""),
                    "members": n,
                    "type": g.get("type", "both"),
                    "icon": g.get("icon", "⚽"),
                    "predExact": int(g.get("predExact", 3)),
                    "predResult": int(g.get("predResult", 1)),
                    "triviaCorrect": int(g.get("triviaCorrect", 1)),
                    "startDate": g.get("startDate", ""),
                    "createdBy": g.get("createdBy", ""),
                })
        self.send_json(200, {"pools": pools})

    def leaderboard_get(self, code):
        rows = leaderboard(code)
        if rows is None:
            return self.send_json(404, {"error": "group not found"})
        st, doc = fs("GET", f"/groups/{code}")
        d = parse(doc)
        self.send_json(200, {
            "code": code, "name": d.get("name"),
            "type": d.get("type", "both"),
            "leaderboard": rows,
        })

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
        if b.get("pkWinner") in ("H", "A"):
            doc["pkWinner"] = b["pkWinner"]
        elif "pkWinner" in b and b["pkWinner"] is None:
            doc["pkWinner"] = None
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

    # ---- friends -----------------------------------------------------------
    def me_get(self, did):
        if not did:
            return self.send_json(400, {"error": "deviceId required"})
        st, doc = fs("GET", f"/users/{did}")
        if st != 200:
            return self.send_json(404, {"error": "not registered"})
        d = parse(doc)
        st, fl = fs("GET", f"/users/{did}/friends", params={"pageSize": "300"})
        n = len(fl.get("documents", [])) if st == 200 else 0
        self.send_json(200, {"code": d.get("code", ""), "displayName": d.get("displayName", ""), "friends": n})

    def me_post(self, body):
        """Register or update my profile; allocate a friend code on first call.
        Accepts the profile fields the iOS app's onboarding flow collects:
        displayName, favoriteTeam, location, and showOnGlobal (the
        opt-in flag for the global leaderboard)."""
        did = body.get("deviceId")
        if not did:
            return self.send_json(400, {"error": "deviceId required"})
        dn = (body.get("displayName") or "").strip()[:40]
        team = (body.get("favoriteTeam") or "").strip()[:60]
        loc = (body.get("location") or "").strip()[:80]
        show = body.get("showOnGlobal")
        st, doc = fs("GET", f"/users/{did}")
        if st == 200:
            d = parse(doc)
            code = d.get("code") or gen_unique_code(did)
            if not code:
                return self.send_json(500, {"error": "could not allocate a code"})
            fields = {"updatedAt": now_iso(), "code": code}
            if dn:
                fields["displayName"] = dn
            # Only patch a field if the client actually sent it; missing key
            # means "no change", whereas an empty-string value is a valid
            # clear (e.g. user erased their location).
            if "favoriteTeam" in body:
                fields["favoriteTeam"] = team
            if "location" in body:
                fields["location"] = loc
            if isinstance(show, bool):
                fields["showOnGlobal"] = show
            fs_merge(f"/users/{did}", fields)
            return self.send_json(200, {"code": code, "displayName": dn or d.get("displayName", "")})
        code = gen_unique_code(did)
        if not code:
            return self.send_json(500, {"error": "could not allocate a code"})
        fs("PATCH", f"/users/{did}",
           body=docbody({
               "displayName": dn,
               "favoriteTeam": team,
               "location": loc,
               # Cold-start default mirrors the iOS app: opt-IN happens only
               # via the onboarding sheet (which sends showOnGlobal=true).
               "showOnGlobal": bool(show) if isinstance(show, bool) else False,
               "code": code,
               "createdAt": now_iso(),
               "updatedAt": now_iso(),
           }))
        self.send_json(200, {"code": code, "displayName": dn})

    def trivia_score_put(self):
        b = self.read_json()
        did = b.get("deviceId")
        if not did:
            return self.send_json(400, {"error": "deviceId required"})
        fields = {"updatedAt": now_iso()}
        for src, dst in [("correct", "triviaCorrect"), ("answered", "triviaAnswered"),
                         ("streak", "triviaStreak"), ("best", "triviaBest")]:
            if isinstance(b.get(src), int):
                fields[dst] = b[src]
        fs_merge(f"/users/{did}", fields)
        self.send_json(200, {"ok": True})

    def friend_add(self, body):
        did = body.get("deviceId")
        code = (body.get("code") or "").strip().lower().replace(" ", "-")
        if not did or not code:
            return self.send_json(400, {"error": "deviceId and code required"})
        st, cdoc = fs("GET", f"/codes/{code}")
        if st != 200:
            return self.send_json(404, {"error": "code not found"})
        friend = parse(cdoc).get("deviceId")
        if not friend:
            return self.send_json(404, {"error": "code not found"})
        if friend == did:
            return self.send_json(400, {"error": "that's your own code"})
        ts = now_iso()
        fs("PATCH", f"/users/{did}/friends/{friend}", body=docbody({"addedAt": ts}))
        fs("PATCH", f"/users/{friend}/friends/{did}", body=docbody({"addedAt": ts}))
        st, fdoc = fs("GET", f"/users/{friend}")
        fn = parse(fdoc).get("displayName", "") if st == 200 else ""
        self.send_json(200, {"ok": True, "friend": fn})

    def friends_leaderboard_get(self, did):
        if not did:
            return self.send_json(400, {"error": "deviceId required"})
        st, mydoc = fs("GET", f"/users/{did}")
        if st != 200:
            return self.send_json(404, {"error": "not registered"})
        ids = [did]
        st, fl = fs("GET", f"/users/{did}/friends", params={"pageSize": "300"})
        if st == 200:
            ids += [f["name"].split("/")[-1] for f in fl.get("documents", [])]
        rows = []
        for uid in ids:
            st, udoc = fs("GET", f"/users/{uid}")
            info = parse(udoc) if st == 200 else {}
            rows.append({
                # Empty when unset — the client localizes the "Player" fallback.
                "deviceId": uid,
                "displayName": info.get("displayName") or "",
                # Friends already know each other so we don't strictly need
                # the public-profile fields here, but include them so the
                # iOS-side row renderer (which shows team + location in
                # Everyone scope) has a consistent payload either way.
                "favoriteTeam": info.get("favoriteTeam") or "",
                "location": info.get("location") or "",
                "predict": predict_points(uid)["points"],
                "trivia": int(info.get("triviaCorrect") or 0),
            })
        self.send_json(200, {"me": did, "rows": rows})

    def global_leaderboard_get(self, did):
        """Top globally opted-in users (showOnGlobal=true) by combined score.
        Returns up to GLOBAL_LIMIT rows sorted high-to-low; the client
        re-sorts by whichever scoring mode is active. Anyone who opted out
        — and anyone who never finished onboarding (default off) — is
        excluded by the Firestore filter."""
        if not did:
            return self.send_json(400, {"error": "deviceId required"})
        # Firestore structured query — server-side filter so we don't
        # have to fetch every user doc and triage in Python.
        query = {
            "from": [{"collectionId": "users"}],
            "where": {
                "fieldFilter": {
                    "field": {"fieldPath": "showOnGlobal"},
                    "op": "EQUAL",
                    "value": {"booleanValue": True},
                }
            },
            "limit": 400,
        }
        st, results = fs("POST", ":runQuery", body={"structuredQuery": query})
        if st != 200:
            return self.send_json(200, {"me": did, "rows": []})
        rows = []
        for r in results or []:
            doc = r.get("document")
            if not doc:
                continue
            uid = doc["name"].split("/")[-1]
            info = parse(doc)
            rows.append({
                "deviceId": uid,
                "displayName": info.get("displayName") or "",
                "favoriteTeam": info.get("favoriteTeam") or "",
                "location": info.get("location") or "",
                "predict": predict_points(uid)["points"],
                "trivia": int(info.get("triviaCorrect") or 0),
            })
        # Sort by combined score; cap to the top 200 so the response stays
        # small even as global signups grow.
        rows.sort(key=lambda r: -(r["predict"] + r["trivia"]))
        rows = rows[:200]
        self.send_json(200, {"me": did, "rows": rows})

    # ---- push-notification device registry --------------------------------
    def devices_register(self, body):
        """iOS reports its APNs token and which kinds of pushes it wants.

        Body: {"deviceId": "...", "token": "<hex>", "ftEnabled": true,
               "useSandbox": false}.
        Stored at /devices/{deviceId}. We upsert: replacing the token if the
        user reinstalled (token rotates), updating the FT subscription, and
        stamping a lastSeen so we can prune dead tokens later.
        """
        did = (body.get("deviceId") or "").strip()
        token = (body.get("token") or "").strip()
        if not did or not token:
            return self.send_json(400, {"error": "deviceId and token required"})
        ft_enabled = bool(body.get("ftEnabled", False))
        # `useSandbox` is hinted by the client (TestFlight/Xcode builds use the
        # sandbox APNs host). For now we trust the server-side env var; this
        # field is stored for future per-device routing if we need it.
        sandbox = bool(body.get("useSandbox", False))
        doc = {
            "token": token,
            "ftEnabled": ft_enabled,
            "useSandbox": sandbox,
            "updatedAt": now_iso(),
        }
        # fs_merge sends `updateMask.fieldPaths=<k>` per field so Firestore
        # upserts these and leaves other fields untouched.
        st, _ = fs_merge(f"/devices/{did}", doc)
        if st >= 400:
            return self.send_json(500, {"error": "store failed"})
        self.send_json(200, {"ok": True})

    def notify_ft(self, body):
        """Internal webhook from update-espn-scores.py: push FT to subscribers.

        Body: {"secret": "...", "matchN": 7}  — sends for one match. The
        proxy uses the /pushed-ft/{matchN} doc as an idempotency lock so a
        re-run of the GitHub Action (every 15 min) won't double-fire.
        """
        if body.get("secret") != os.environ.get("INTERNAL_PUSH_SECRET", ""):
            return self.send_json(403, {"error": "forbidden"})
        try:
            match_n = int(body.get("matchN"))
        except (TypeError, ValueError):
            return self.send_json(400, {"error": "matchN required"})
        # Idempotency: once we've pushed for this matchN we never push again,
        # even on a re-run or a corrected score.
        st, _ = fs("GET", f"/pushed-ft/{match_n}")
        if st == 200:
            return self.send_json(200, {"ok": True, "skipped": "already-pushed"})
        # Look up the match (home + away names) from cached results to build
        # the notification body. We refresh once if absent.
        match = _match_by_n(match_n)
        if not match:
            return self.send_json(404, {"error": "match not found"})
        # Find every device that has FT pushes enabled.
        tokens = _ft_subscribers()
        if not tokens:
            # Nothing to do, but still mark pushed so re-runs are no-ops.
            fs_merge(f"/pushed-ft/{match_n}", {"pushedAt": now_iso(), "count": 0})
            return self.send_json(200, {"ok": True, "sent": 0})
        # Build payload once, reuse across devices.
        matchup = f"{match['home']} vs {match['away']}"
        title = "Full time"
        text = f"Tap to see how {matchup} ended."
        sender = _apns()
        if sender is None:
            return self.send_json(503, {"error": "APNs not configured"})
        sent = 0
        failed = 0
        for did, token in tokens:
            try:
                sender.send(token=token, title=title, body=text,
                            category="GAME_RESULT",
                            user_info={"type": "result", "matchN": match_n},
                            collapse_id=f"result-{match_n}")
                sent += 1
            except Exception as e:
                failed += 1
                # Apple returns 410 / "Unregistered" for stale tokens — drop
                # those so future runs don't keep retrying.
                if "410" in str(e) or "Unregistered" in str(e) or "BadDeviceToken" in str(e):
                    fs("DELETE", f"/devices/{did}")
                print(f"  APNs send failed for {did[:8]}…: {e}")
        fs_merge(f"/pushed-ft/{match_n}", {"pushedAt": now_iso(), "count": sent})
        self.send_json(200, {"ok": True, "sent": sent, "failed": failed})

    def log_message(self, fmt, *args):
        print(f"{self.client_address[0]} - {fmt % args}")


# ---------------------------------------------------------------------------
# Push-notification helpers (lazy-loaded so the proxy still boots even if
# APNs deps are unavailable / env vars are unset)
# ---------------------------------------------------------------------------
_apns_instance = []  # one-element holder: lets us cache + None-sentinel


def _apns():
    """Return a cached APNsSender or None if APNs isn't configured."""
    if _apns_instance:
        return _apns_instance[0]
    try:
        from apns import APNsSender  # local module
        s = APNsSender()
        if not s.configured:
            print("APNs env vars missing — push disabled")
            _apns_instance.append(None)
            return None
        _apns_instance.append(s)
        return s
    except Exception as e:
        print(f"APNs init failed: {e}")
        _apns_instance.append(None)
        return None


def _match_by_n(n):
    """Find a match record by `n` from the cached results URL feed."""
    try:
        with urllib.request.urlopen(RESULTS_URL, timeout=10) as r:
            arr = json.loads(r.read())
        for x in arr:
            if int(x.get("n", -1)) == n:
                return x
    except Exception as e:
        print(f"match lookup failed for n={n}: {e}")
    return None


def _ft_subscribers():
    """Yield (deviceId, token) for every device with ftEnabled=true."""
    st, pl = fs("GET", "/devices", params={"pageSize": "1000"})
    if st != 200:
        return []
    out = []
    for doc in pl.get("documents", []):
        info = parse(doc)
        if info.get("ftEnabled") and info.get("token"):
            did = doc["name"].split("/")[-1]
            out.append((did, info["token"]))
    return out


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    server = HTTPServer(("0.0.0.0", port), Handler)
    print(f"Proxy listening on :{port}")
    server.serve_forever()
