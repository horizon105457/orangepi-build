from __future__ import annotations

import argparse
import os
import socket
from dataclasses import dataclass
from typing import Optional


@dataclass
class AgentConfig:
    hub_url: Optional[str]
    iface: Optional[str]
    host_alias: str
    interval: int
    disable_power_metrics: bool
    insecure_skip_verify: bool
    local_bind_host: str
    local_bind_port: int


def parse_args() -> AgentConfig:
    env_hub_url = os.getenv("TELEMETRY_HUB_URL", "").strip() or None

    parser = argparse.ArgumentParser(description="Lightweight telemetry agent")
    parser.add_argument(
        "--hub-url",
        default=None,
        help="Hub endpoint URL (overrides TELEMETRY_HUB_URL)",
    )
    parser.add_argument("--iface", default=None, help="Network interface name")
    parser.add_argument("--host-alias", default=socket.gethostname(), help="Host alias")
    parser.add_argument("--interval", type=int, default=5, help="Push interval in seconds")
    parser.add_argument(
        "--disable-power-metrics",
        action="store_true",
        help="Disable power metrics",
    )
    parser.add_argument(
        "--insecure-skip-verify",
        action="store_true",
        help="Disable TLS verification for HTTPS",
    )
    parser.add_argument("--local-bind-host", default="127.0.0.1", help="Local HTTP bind host")
    parser.add_argument("--local-bind-port", type=int, default=9101, help="Local HTTP bind port")
    args = parser.parse_args()
    hub_url = args.hub_url or env_hub_url

    return AgentConfig(
        hub_url=hub_url,
        iface=args.iface,
        host_alias=args.host_alias,
        interval=max(1, int(args.interval)),
        disable_power_metrics=args.disable_power_metrics,
        insecure_skip_verify=bool(args.insecure_skip_verify),
        local_bind_host=args.local_bind_host,
        local_bind_port=args.local_bind_port,
    )
