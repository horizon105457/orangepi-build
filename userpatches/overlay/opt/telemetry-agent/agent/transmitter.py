from __future__ import annotations

import base64
import json
import logging
import os
import ssl
import time
import urllib.request
from typing import Dict, Optional


class HttpTransmitter:
    def __init__(self, hub_url: str, insecure_skip_verify: bool = False) -> None:
        self.hub_url = hub_url
        self._consecutive_failures = 0
        self._last_warn_ts = 0.0
        self._warn_interval_sec = 60.0
        self._timeout_sec = 3.0

        self.headers = {"Content-Type": "application/json"}
        auth_env = os.getenv("TELEMETRY_AUTH", "")
        if auth_env and ":" in auth_env:
            token = base64.b64encode(auth_env.encode("utf-8")).decode("ascii")
            self.headers["Authorization"] = f"Basic {token}"

        if insecure_skip_verify:
            self._ssl_context = ssl._create_unverified_context()
        else:
            self._ssl_context = ssl.create_default_context()

        if insecure_skip_verify:
            logging.error(
                "TLS certificate verification is disabled. This is insecure and should only be used in trusted development environments."
            )

    def send(self, payload: Dict) -> bool:
        try:
            body = json.dumps(payload).encode("utf-8")
            req = urllib.request.Request(self.hub_url, data=body, headers=self.headers, method="POST")
            with urllib.request.urlopen(req, timeout=self._timeout_sec, context=self._ssl_context) as resp:
                status_code = getattr(resp, "status", 200)
                if status_code >= 400:
                    raise RuntimeError(f"hub returned HTTP {status_code}")
            self._consecutive_failures = 0
            return True
        except Exception as exc:
            self._consecutive_failures += 1
            now = time.monotonic()
            should_log = self._consecutive_failures < 10 or (now - self._last_warn_ts) >= self._warn_interval_sec
            if should_log:
                logging.warning("send telemetry failed: %s", exc)
                self._last_warn_ts = now
            return False

    def close(self) -> None:
        return None
