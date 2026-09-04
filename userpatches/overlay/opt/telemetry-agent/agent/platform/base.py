from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Dict, Optional


def _default_iface() -> Optional[str]:
    try:
        with open("/proc/net/route", "r") as f:
            next(f, None)
            for line in f:
                cols = line.split()
                if len(cols) >= 2 and cols[1] == "00000000":
                    return cols[0]
    except OSError:
        return None
    return None


class PlatformAdapter(ABC):
    @abstractmethod
    def get_cpu_usage(self) -> Dict:
        raise NotImplementedError

    @abstractmethod
    def get_memory_info(self) -> Dict:
        raise NotImplementedError

    @abstractmethod
    def get_disk_info(self) -> Dict:
        raise NotImplementedError

    @abstractmethod
    def get_network_info(self, iface: str) -> Dict:
        raise NotImplementedError

    @abstractmethod
    def get_temperature(self) -> Optional[float]:
        raise NotImplementedError

    @abstractmethod
    def get_power_info(self) -> Dict:
        raise NotImplementedError

    @abstractmethod
    def get_device_info(self) -> Dict:
        raise NotImplementedError

    @abstractmethod
    def get_hostname(self) -> str:
        raise NotImplementedError

    @abstractmethod
    def get_timestamp(self) -> int:
        raise NotImplementedError

    @staticmethod
    def default_iface() -> Optional[str]:
        return _default_iface()
