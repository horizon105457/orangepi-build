from __future__ import annotations

from pathlib import Path
from typing import Dict, Optional

from .generic_linux import GenericLinuxAdapter


class RockchipAdapter(GenericLinuxAdapter):
    """RK3588 (Orange Pi CM5) platform adapter.

    The generic Linux adapter already covers SoC temperature
    (/sys/class/thermal/thermal_zone* — RK3588 tsadc) and ARM frequency
    (cpufreq). This adapter adds PMIC power-supply readings when available
    and prefers the tsadc hwmon node for the SoC temperature.
    """

    def get_temperature(self) -> Optional[float]:
        # Prefer the RK3588 tsadc hwmon node (temp1_input = SoC temperature)
        hwmon_candidates = sorted(Path("/sys/class/hwmon").glob("hwmon*/temp1_input"))
        for path in hwmon_candidates:
            try:
                val = int(path.read_text(encoding="utf-8").strip())
                # millidegrees C -> C (Rockchip tsadc reports in millidegrees)
                if val > 1000:
                    return round(val / 1000.0, 1)
                return float(val)
            except (OSError, ValueError):
                continue
        return super().get_temperature()

    def get_power_info(self) -> Dict:
        if self.disable_power_metrics:
            return {}

        data: Dict = {}
        supply_root = Path("/sys/class/power_supply")
        if supply_root.exists():
            for supply in sorted(supply_root.iterdir()):
                try:
                    volt_path = supply / "voltage_now"
                    if volt_path.exists():
                        uv = int(volt_path.read_text(encoding="utf-8").strip())
                        data["supply_voltage_v"] = round(uv / 1_000_000.0, 3)
                    amp_path = supply / "current_now"
                    if amp_path.exists():
                        ua = int(amp_path.read_text(encoding="utf-8").strip())
                        data["supply_current_a"] = round(ua / 1_000_000.0, 3)
                except (OSError, ValueError):
                    continue

        # Merge in generic cpufreq reading (arm_freq_hz)
        generic = super().get_power_info()
        data.update(generic)
        return data
