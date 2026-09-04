from __future__ import annotations

import json
import logging
import signal
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Dict, Optional

from .collector import Collector
from .config import parse_args
from .platform import create_platform_adapter
from .platform.base import PlatformAdapter
from .transmitter import HttpTransmitter


class MetricsServer:
    def __init__(self, host: str, port: int) -> None:
        self.host = host
        self.port = port
        self._latest: Dict = {}
        self._server: Optional[ThreadingHTTPServer] = None
        self._thread: Optional[threading.Thread] = None

    def set_latest(self, payload: Dict) -> None:
        self._latest = payload

    def start(self) -> None:
        parent = self

        class Handler(BaseHTTPRequestHandler):
            def _send_json(self, obj: Dict, status: int = 200) -> None:
                body = json.dumps(obj).encode("utf-8")
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_GET(self) -> None:
                if self.path == "/health":
                    self._send_json({"status": "up"})
                    return
                if self.path == "/metrics":
                    self._send_json(parent._latest or {})
                    return
                self._send_json({"error": "not found"}, status=404)

            def log_message(self, format: str, *args) -> None:
                return

        self._server = ThreadingHTTPServer((self.host, self.port), Handler)
        self._thread = threading.Thread(target=self._server.serve_forever, daemon=True)
        self._thread.start()
        logging.info("local metrics server started at http://%s:%d", self.host, self.port)

    def stop(self) -> None:
        if self._server:
            self._server.shutdown()
            self._server.server_close()


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    cfg = parse_args()

    adapter = create_platform_adapter(disable_power_metrics=cfg.disable_power_metrics)
    iface = cfg.iface or PlatformAdapter.default_iface() or "eth0"

    collector = Collector(
        adapter=adapter,
        host=cfg.host_alias,
        iface=iface,
        disable_power_metrics=cfg.disable_power_metrics,
    )

    transmitter = None
    if cfg.hub_url:
        transmitter = HttpTransmitter(cfg.hub_url, insecure_skip_verify=cfg.insecure_skip_verify)

    metrics_server = MetricsServer(cfg.local_bind_host, cfg.local_bind_port)
    metrics_server.start()

    stop = threading.Event()

    def _on_signal(signum, frame) -> None:
        logging.info("received signal %s, shutting down", signum)
        stop.set()

    signal.signal(signal.SIGTERM, _on_signal)
    signal.signal(signal.SIGINT, _on_signal)

    next_push = time.monotonic()

    try:
        while not stop.is_set():
            collector.tick()
            now = time.monotonic()
            if now >= next_push:
                payload = collector.snapshot()
                if transmitter:
                    transmitter.send(payload)
                metrics_server.set_latest(payload)
                next_push = now + cfg.interval
            time.sleep(0.2)
    finally:
        if transmitter:
            transmitter.close()
        metrics_server.stop()


if __name__ == "__main__":
    main()
