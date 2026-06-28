"""APNs token-auth sender.

Builds a short-lived ES256 JWT from the developer-portal APNs Auth Key, then
POSTs an alert payload over HTTP/2 to api.push.apple.com (production) or
api.sandbox.push.apple.com (TestFlight/Xcode dev builds).

Env vars (set on Cloud Run):
    APNS_TEAM_ID       — 10-char Apple Team ID (from developer portal)
    APNS_KEY_ID        — 10-char key id matching the .p8 file
    APNS_KEY_P8        — full contents of the .p8 file, BEGIN/END lines included
    APNS_BUNDLE_ID     — iOS bundle id, e.g. com.matchmondo.app
    APNS_USE_SANDBOX   — "true" to use sandbox host (TestFlight/dev), default false

The JWT is cached for ~50 minutes (Apple invalidates after ~1 hour). Each
`send()` call is one HTTP/2 request; for fan-out callers should loop and
reuse a single Sender instance to keep the HTTP/2 connection warm.
"""

from __future__ import annotations

import base64
import json
import os
import time
from typing import Any, Optional

import httpx
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature


class APNsError(Exception):
    def __init__(self, status: int, reason: str, token: str = ""):
        super().__init__(f"APNs {status} {reason} (token={token[:8]}…)")
        self.status = status
        self.reason = reason
        self.token = token


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _es256_sign(key_pem: bytes, message: bytes) -> bytes:
    """Sign with ES256 and return JOSE-format (r||s) bytes."""
    key = serialization.load_pem_private_key(key_pem, password=None)
    if not isinstance(key, ec.EllipticCurvePrivateKey):
        raise ValueError("APNs key must be ECDSA P-256")
    der_sig = key.sign(message, ec.ECDSA(hashes.SHA256()))
    r, s = decode_dss_signature(der_sig)
    return r.to_bytes(32, "big") + s.to_bytes(32, "big")


class APNsSender:
    def __init__(self) -> None:
        self.team_id = os.environ.get("APNS_TEAM_ID", "")
        self.key_id = os.environ.get("APNS_KEY_ID", "")
        self.key_p8 = os.environ.get("APNS_KEY_P8", "").encode("utf-8")
        self.bundle_id = os.environ.get("APNS_BUNDLE_ID", "com.matchmondo.app")
        sandbox = os.environ.get("APNS_USE_SANDBOX", "").lower() in ("1", "true", "yes")
        host = "api.sandbox.push.apple.com" if sandbox else "api.push.apple.com"
        self.base_url = f"https://{host}"
        self._jwt: Optional[str] = None
        self._jwt_ts: float = 0.0
        # http2=True is required — APNs rejects HTTP/1.1.
        self._client = httpx.Client(http2=True, timeout=10.0)

    @property
    def configured(self) -> bool:
        return all([self.team_id, self.key_id, self.key_p8, self.bundle_id])

    def _token(self) -> str:
        # Apple says tokens stay valid up to an hour; refresh every 50 min.
        if self._jwt and time.time() - self._jwt_ts < 50 * 60:
            return self._jwt
        header = {"alg": "ES256", "kid": self.key_id}
        payload = {"iss": self.team_id, "iat": int(time.time())}
        h = _b64url(json.dumps(header, separators=(",", ":")).encode())
        p = _b64url(json.dumps(payload, separators=(",", ":")).encode())
        signing_input = f"{h}.{p}".encode()
        sig = _b64url(_es256_sign(self.key_p8, signing_input))
        self._jwt = f"{h}.{p}.{sig}"
        self._jwt_ts = time.time()
        return self._jwt

    def send(self, *, token: str, title: str, body: str, category: str,
             user_info: dict[str, Any], collapse_id: Optional[str] = None) -> None:
        """One push to one device. Raises APNsError on non-200 responses."""
        if not self.configured:
            raise RuntimeError("APNs sender not configured — env vars missing")
        if not token:
            raise APNsError(0, "empty token")
        url = f"{self.base_url}/3/device/{token}"
        headers = {
            "authorization": f"bearer {self._token()}",
            "apns-topic": self.bundle_id,
            "apns-push-type": "alert",
            "apns-priority": "10",
        }
        if collapse_id:
            headers["apns-collapse-id"] = collapse_id[:64]
        payload = {
            "aps": {
                "alert": {"title": title, "body": body},
                "sound": "default",
                "category": category,
            },
        }
        payload.update(user_info)
        resp = self._client.post(url, headers=headers, json=payload)
        if resp.status_code != 200:
            try:
                reason = resp.json().get("reason", resp.text)
            except Exception:
                reason = resp.text
            raise APNsError(resp.status_code, reason, token)

    def close(self) -> None:
        self._client.close()
