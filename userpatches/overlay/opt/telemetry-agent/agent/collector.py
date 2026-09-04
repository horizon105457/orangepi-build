from __future__ import annotations

import logging
import time
from typing import Dict, List, Optional, Set

from .platform.base import PlatformAdapter


class Collector:
    def __init__(self, adapter: PlatformAdapter, host: str, iface: str, disable_power_metrics: bool = False) -> None:
        self.adapter = adapter
        self.host = host
        self.iface = iface
        self.disable_power_metrics = disable_power_metrics

        self._metrics: Dict = {}
        self._missing: Set[str] = set()
        self._platform = adapter.__class__.__name__.replace("Adapter", "").lower()
        self._device_info = self._load_device_info()

        now = time.monotonic()
        self._next = {
            "cpu": now,
            "mem": now,
            "disk": now,
            "net": now,
            "temp": now,
            "power": now,
        }

    def tick(self) -> None:
        now = time.monotonic()
        if now >= self._next["cpu"]:
            self._collect_cpu()
            self._next["cpu"] = now + 5

        if now >= self._next["net"]:
            self._collect_net()
            self._next["net"] = now + 5

        if now >= self._next["mem"]:
            self._collect_mem()
            self._next["mem"] = now + 10

        if now >= self._next["temp"]:
            self._collect_temp()
            self._next["temp"] = now + 10

        if now >= self._next["disk"]:
            self._collect_disk()
            self._next["disk"] = now + 30

        if not self.disable_power_metrics and now >= self._next["power"]:
            self._collect_power()
            self._next["power"] = now + 30

    def snapshot(self) -> Dict:
        status = "ok"
        if self._missing:
            status = "degraded"

        payload = {
            "schema_version": "1.5",
            "host": self.host,
            "timestamp": self.adapter.get_timestamp(),
            "platform": self._platform,
            "cpu_cores": self._metrics.get("cpu_cores", 0),
            "cpu_slots": self._metrics.get("cpu_slots", 0),
            "device_info": self._device_info,
            "metrics": self._metrics,
            "status": status,
            "missing_metrics": sorted(self._missing),
        }
        return payload

    def _load_device_info(self) -> Dict:
        try:
            info = self.adapter.get_device_info()
            if not isinstance(info, dict):
                return {}
            return dict(info)
        except Exception as exc:
            logging.warning("collect device_info failed at startup: %s", exc)
            return {}

    def _collect_cpu(self) -> None:
        try:
            cpu = self.adapter.get_cpu_usage()
            self._metrics.update(cpu)
            self._missing.discard("cpu")
        except Exception as exc:
            logging.warning("collect cpu failed: %s", exc)
            self._missing.add("cpu")

    def _collect_mem(self) -> None:
        try:
            mem = self.adapter.get_memory_info()
            self._metrics.update(mem)
            self._missing.discard("memory")
        except Exception as exc:
            logging.warning("collect memory failed: %s", exc)
            self._missing.add("memory")

    def _collect_disk(self) -> None:
        try:
            disk = self.adapter.get_disk_info()
            io_state = disk.pop("disk_io_state", "ok")
            self._metrics.update(disk)
            if io_state == "unavailable":
                self._missing.add("disk_io")
            else:
                self._missing.discard("disk_io")
            self._missing.discard("disk")
        except Exception as exc:
            logging.warning("collect disk failed: %s", exc)
            self._missing.add("disk")

    def _collect_net(self) -> None:
        try:
            net = self.adapter.get_network_info(self.iface)
            self._metrics.update(net)
            self._missing.discard("network")
        except Exception as exc:
            logging.warning("collect network failed: %s", exc)
            self._missing.add("network")

    def _collect_temp(self) -> None:
        try:
            temp = self.adapter.get_temperature()
            if temp is None:
                self._metrics.pop("temp_c", None)
            else:
                self._metrics["temp_c"] = temp
        except Exception:
            self._metrics.pop("temp_c", None)

    def _collect_power(self) -> None:
        try:
            power = self.adapter.get_power_info()
            if not power:
                self._metrics.pop("core_voltage_v", None)
                self._metrics.pop("throttled_hex", None)
                self._metrics.pop("arm_freq_hz", None)
                return
            self._metrics.update(power)
        except Exception:
            self._metrics.pop("core_voltage_v", None)
            self._metrics.pop("throttled_hex", None)
            self._metrics.pop("arm_freq_hz", None)
