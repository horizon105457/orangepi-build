from __future__ import annotations

import re
import shutil
import subprocess
from typing import Dict, Optional

from .generic_linux import GenericLinuxAdapter


class RaspberryPiAdapter(GenericLinuxAdapter):
    def __init__(self, disable_power_metrics: bool = False) -> None:
        super().__init__(disable_power_metrics=disable_power_metrics)
        self._vcgencmd_path = shutil.which("vcgencmd")
        self._vcgencmd_unavailable = self._vcgencmd_path is None

    def get_temperature(self) -> Optional[float]:
        out = self._run_vcgencmd(["measure_temp"])
        if out is None:
            return super().get_temperature()
        m = re.search(r"temp=([0-9.]+)", out)
        if not m:
            return super().get_temperature()
        return round(float(m.group(1)), 1)

    def get_power_info(self) -> Dict:
        if self.disable_power_metrics:
            return {}

        data: Dict = {}

        volts = self._run_vcgencmd(["measure_volts", "core"])
        if volts:
            m = re.search(r"volts=([0-9.]+)V", volts)
            if m:
                data["core_voltage_v"] = round(float(m.group(1)), 2)

        throttled = self._run_vcgencmd(["get_throttled"])
        if throttled:
            m = re.search(r"throttled=([^\s]+)", throttled)
            if m:
                data["throttled_hex"] = m.group(1)

        freq = self._run_vcgencmd(["measure_clock", "arm"])
        if freq:
            m = re.search(r"frequency\(\d+\)=([0-9]+)", freq)
            if m:
                data["arm_freq_hz"] = int(m.group(1))

        if not data:
            return super().get_power_info()
        return data

    def _run_vcgencmd(self, args: list[str]) -> Optional[str]:
        if self._vcgencmd_unavailable or not self._vcgencmd_path:
            return None
        try:
            proc = subprocess.run(
                [self._vcgencmd_path, *args],
                capture_output=True,
                text=True,
                timeout=2,
                check=False,
            )
        except (OSError, subprocess.SubprocessError):
            self._vcgencmd_unavailable = True
            return None

        if proc.returncode != 0:
            return None
        return proc.stdout.strip()
