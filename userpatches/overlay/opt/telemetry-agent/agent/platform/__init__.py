from __future__ import annotations

import os
from pathlib import Path

from .base import PlatformAdapter
from .generic_linux import GenericLinuxAdapter
from .rpi import RaspberryPiAdapter
from .rk3588 import RockchipAdapter


def _is_raspberry_pi() -> bool:
    if os.path.exists("/usr/bin/vcgencmd"):
        return True
    model_path = Path("/proc/device-tree/model")
    if model_path.exists():
        try:
            model = model_path.read_text(errors="ignore").lower()
            return "raspberry" in model
        except OSError:
            return False
    return False


def _is_rockchip_rk3588() -> bool:
    model_path = Path("/proc/device-tree/model")
    if model_path.exists():
        try:
            model = model_path.read_text(errors="ignore").lower()
            return "rk3588" in model or "orangepi" in model
        except OSError:
            return False
    return False


def create_platform_adapter(disable_power_metrics: bool = False) -> PlatformAdapter:
    if _is_raspberry_pi():
        return RaspberryPiAdapter(disable_power_metrics=disable_power_metrics)
    if _is_rockchip_rk3588():
        return RockchipAdapter(disable_power_metrics=disable_power_metrics)
    return GenericLinuxAdapter(disable_power_metrics=disable_power_metrics)
