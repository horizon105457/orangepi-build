from __future__ import annotations

import os
import platform
import re
import socket
import subprocess
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from .base import PlatformAdapter

CPU_LINE = re.compile(r"^cpu(\d+)\s+")


class GenericLinuxAdapter(PlatformAdapter):
    def __init__(self, disable_power_metrics: bool = False) -> None:
        self.disable_power_metrics = disable_power_metrics

        self._cpu_prev_total: Optional[Tuple[int, int]] = None
        self._cpu_prev_cores: Dict[str, Tuple[int, int]] = {}
        self._core_index_map: Dict[str, int] = {}

        self._disk_prev: Optional[Tuple[int, int, float]] = None
        self._disk_dev_name: Optional[str] = None
        self._disk_io_unavailable = False

        self._net_prev: Dict[str, Tuple[int, int, float]] = {}

    def get_cpu_usage(self) -> Dict:
        lines = self._read_proc_stat()
        total_fields = None
        current_cores: Dict[str, List[int]] = {}

        for line in lines:
            if line.startswith("cpu "):
                total_fields = self._parse_cpu_fields(line)
                continue
            if CPU_LINE.match(line):
                name = line.split()[0]
                current_cores[name] = self._parse_cpu_fields(line)

        for core_name in sorted(current_cores.keys(), key=lambda x: int(x[3:])):
            if core_name not in self._core_index_map:
                self._core_index_map[core_name] = len(self._core_index_map)

        cpu_slots = len(self._core_index_map)
        cpu_cores = len(current_cores)

        cores_pct: List[Optional[float]] = [None] * cpu_slots

        for core_name, idx in self._core_index_map.items():
            fields = current_cores.get(core_name)
            if fields is None:
                cores_pct[idx] = None
                continue

            curr_total, curr_idle = self._cpu_totals(fields)
            prev = self._cpu_prev_cores.get(core_name)
            if prev is None:
                cores_pct[idx] = None
            else:
                total_diff = curr_total - prev[0]
                idle_diff = curr_idle - prev[1]
                cores_pct[idx] = self._pct(total_diff, idle_diff)
            self._cpu_prev_cores[core_name] = (curr_total, curr_idle)

        total_pct: Optional[float] = None
        if total_fields is not None:
            curr_total_all, curr_idle_all = self._cpu_totals(total_fields)
            if self._cpu_prev_total is not None:
                total_diff = curr_total_all - self._cpu_prev_total[0]
                idle_diff = curr_idle_all - self._cpu_prev_total[1]
                total_pct = self._pct(total_diff, idle_diff)
            self._cpu_prev_total = (curr_total_all, curr_idle_all)

        return {
            "cpu_total_pct": total_pct,
            "cpu_cores_pct": cores_pct,
            "cpu_cores": cpu_cores,
            "cpu_slots": cpu_slots,
        }

    def get_memory_info(self) -> Dict:
        data: Dict[str, int] = {}
        with open("/proc/meminfo", "r", encoding="utf-8") as f:
            for line in f:
                if ":" not in line:
                    continue
                key, rest = line.split(":", 1)
                val = rest.strip().split()[0]
                try:
                    data[key] = int(val)
                except ValueError:
                    continue

        total_kb = data.get("MemTotal")
        avail_kb = data.get("MemAvailable")
        return {
            "mem_total_kb": total_kb,
            "mem_avail_kb": avail_kb,
            "mem_total_mb": round(total_kb / 1024, 1) if total_kb else None,
            "mem_avail_mb": round(avail_kb / 1024, 1) if avail_kb else None,
        }

    def get_disk_info(self) -> Dict:
        st = os.statvfs("/")
        total_kb = int((st.f_blocks * st.f_frsize) / 1024)
        free_kb = int((st.f_bavail * st.f_frsize) / 1024)
        used_kb = max(total_kb - free_kb, 0)
        used_pct = round((used_kb / total_kb * 100.0), 1) if total_kb > 0 else 0.0

        if self._disk_dev_name is None and not self._disk_io_unavailable:
            self._disk_dev_name = self._resolve_root_disk_device()
            if self._disk_dev_name is None:
                self._disk_io_unavailable = True

        read_kbs: Optional[float] = None
        write_kbs: Optional[float] = None
        io_state = "baseline"

        if self._disk_io_unavailable:
            io_state = "unavailable"
        else:
            sectors = self._read_diskstats_sectors(self._disk_dev_name)
            if sectors is None:
                self._disk_io_unavailable = True
                io_state = "unavailable"
            else:
                now = time.monotonic()
                if self._disk_prev is not None:
                    prev_read, prev_write, prev_t = self._disk_prev
                    dt = now - prev_t
                    if dt > 0:
                        read_kbs = round(((sectors[0] - prev_read) * 512.0 / 1024.0) / dt, 2)
                        write_kbs = round(((sectors[1] - prev_write) * 512.0 / 1024.0) / dt, 2)
                        io_state = "ok"
                self._disk_prev = (sectors[0], sectors[1], now)

        return {
            "disk_total_kb": total_kb,
            "disk_used_kb": used_kb,
            "disk_used_pct": used_pct,
            "disk_read_kbs": read_kbs,
            "disk_write_kbs": write_kbs,
            "disk_io_state": io_state,
        }

    def get_network_info(self, iface: str) -> Dict:
        rx_bytes, tx_bytes, rx_packets, tx_packets = self._read_netdev(iface)

        rx_kbps: Optional[float] = None
        tx_kbps: Optional[float] = None
        if iface in self._net_prev:
            prev_rx, prev_tx, prev_t = self._net_prev[iface]
            dt = time.monotonic() - prev_t
            if dt > 0:
                rx_kbps = round(((rx_bytes - prev_rx) * 8.0 / 1024.0) / dt, 2)
                tx_kbps = round(((tx_bytes - prev_tx) * 8.0 / 1024.0) / dt, 2)

        self._net_prev[iface] = (rx_bytes, tx_bytes, time.monotonic())

        return {
            "net_iface": iface,
            "net_rx_bytes": rx_bytes,
            "net_tx_bytes": tx_bytes,
            "net_rx_kbps": rx_kbps,
            "net_tx_kbps": tx_kbps,
            "net_rx_packets": rx_packets,
            "net_tx_packets": tx_packets,
        }

    def get_temperature(self) -> Optional[float]:
        thermal_root = Path("/sys/class/thermal")
        if not thermal_root.exists():
            return None

        candidates = sorted(thermal_root.glob("thermal_zone*/temp"))
        if not candidates:
            return None

        best_temp = None
        for temp_path in candidates:
            try:
                val = int(temp_path.read_text(encoding="utf-8").strip())
            except (OSError, ValueError):
                continue
            c = val / 1000.0 if val > 1000 else float(val)
            if best_temp is None or c > best_temp:
                best_temp = c

        return round(best_temp, 1) if best_temp is not None else None

    def get_power_info(self) -> Dict:
        if self.disable_power_metrics:
            return {}

        freq = self._read_first_int(
            [
                "/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq",
                "/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_cur_freq",
            ]
        )
        arm_freq_hz = int(freq * 1000) if freq is not None and freq < 10_000_000 else freq

        return {"arm_freq_hz": arm_freq_hz} if arm_freq_hz is not None else {}

    def get_device_info(self) -> Dict:
        hostname = self.get_hostname()
        distro = self._read_distro_pretty_name()
        arch = platform.machine() or "Unknown"
        kernel = platform.release() or "Unknown"
        machine = platform.uname().machine or arch
        model = self._read_device_model()

        return {
            "hostname": hostname or "Unknown",
            "distro": distro or "Unknown",
            "arch": arch,
            "kernel": kernel,
            "machine": machine,
            "model": model or "Unknown",
        }

    def get_hostname(self) -> str:
        return socket.gethostname()

    def get_timestamp(self) -> int:
        return int(time.time())

    @staticmethod
    def _read_proc_stat() -> List[str]:
        with open("/proc/stat", "r", encoding="utf-8") as f:
            return f.readlines()

    @staticmethod
    def _parse_cpu_fields(line: str) -> List[int]:
        parts = line.split()
        nums = [int(x) for x in parts[1:11]]
        while len(nums) < 8:
            nums.append(0)
        return nums

    @staticmethod
    def _cpu_totals(fields: List[int]) -> Tuple[int, int]:
        user = fields[0]
        nice = fields[1]
        system = fields[2]
        idle = fields[3]
        iowait = fields[4] if len(fields) > 4 else 0
        irq = fields[5] if len(fields) > 5 else 0
        softirq = fields[6] if len(fields) > 6 else 0
        steal = fields[7] if len(fields) > 7 else 0
        total = user + nice + system + idle + iowait + irq + softirq + steal
        idle_all = idle + iowait
        return total, idle_all

    @staticmethod
    def _pct(total_diff: int, idle_diff: int) -> float:
        if total_diff <= 0:
            return 0.0
        busy = total_diff - idle_diff
        if busy < 0:
            busy = 0
        return round((busy / total_diff) * 100.0, 1)

    @staticmethod
    def _read_first_int(paths: List[str]) -> Optional[int]:
        for p in paths:
            try:
                val = int(Path(p).read_text(encoding="utf-8").strip())
                return val
            except (OSError, ValueError):
                continue
        return None

    @staticmethod
    def _read_netdev(iface: str) -> Tuple[int, int, int, int]:
        with open("/proc/net/dev", "r", encoding="utf-8") as f:
            for line in f:
                if ":" not in line:
                    continue
                name, rest = [x.strip() for x in line.split(":", 1)]
                if name != iface:
                    continue
                cols = rest.split()
                if len(cols) < 16:
                    break
                rx_bytes = int(cols[0])
                rx_packets = int(cols[1])
                tx_bytes = int(cols[8])
                tx_packets = int(cols[9])
                return rx_bytes, tx_bytes, rx_packets, tx_packets
        raise RuntimeError(f"interface not found: {iface}")

    def _resolve_root_disk_device(self) -> Optional[str]:
        try:
            with open("/proc/self/mountinfo", "r", encoding="utf-8") as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) < 10:
                        continue
                    if parts[4] != "/":
                        continue
                    if "-" not in parts:
                        continue
                    dash = parts.index("-")
                    if dash + 2 >= len(parts):
                        continue
                    source = parts[dash + 2]
                    dev_name = self._normalize_block_dev(source)
                    if dev_name is None:
                        return None
                    if self._read_diskstats_sectors(dev_name) is not None:
                        return dev_name
                    parent = self._parent_block_dev(dev_name)
                    if parent and self._read_diskstats_sectors(parent) is not None:
                        return parent
                    if self._read_diskstats_sectors(dev_name) is not None:
                        return dev_name
                    return None
        except OSError:
            return None
        return None

    @staticmethod
    def _read_distro_pretty_name() -> str:
        os_release = Path("/etc/os-release")
        if os_release.exists():
            try:
                for line in os_release.read_text(encoding="utf-8", errors="ignore").splitlines():
                    if line.startswith("PRETTY_NAME="):
                        return line.split("=", 1)[1].strip().strip('"')
            except OSError:
                pass

        try:
            proc = subprocess.run(
                ["lsb_release", "-d", "-s"],
                capture_output=True,
                text=True,
                timeout=2,
                check=False,
            )
            if proc.returncode == 0:
                out = proc.stdout.strip()
                if out:
                    return out
        except (OSError, subprocess.SubprocessError):
            pass

        return "Unknown"

    @staticmethod
    def _read_device_model() -> str:
        candidates = [
            "/proc/device-tree/model",
            "/sys/firmware/devicetree/base/model",
            "/sys/devices/virtual/dmi/id/product_name",
        ]
        for p in candidates:
            path = Path(p)
            if not path.exists():
                continue
            try:
                raw = path.read_bytes()
                text = raw.decode("utf-8", errors="ignore").replace("\x00", "").strip()
                if text:
                    return text
            except OSError:
                continue
        return "Unknown"

    @staticmethod
    def _normalize_block_dev(source: str) -> Optional[str]:
        if source.startswith("/dev/"):
            return source[5:]
        if source in {"overlay", "tmpfs", "rootfs"}:
            return None
        if source.startswith("/"):
            return None
        return source

    @staticmethod
    def _parent_block_dev(name: str) -> Optional[str]:
        if re.match(r"^mmcblk\d+p\d+$", name):
            return re.sub(r"p\d+$", "", name)
        if re.match(r"^nvme\d+n\d+p\d+$", name):
            return re.sub(r"p\d+$", "", name)
        if re.match(r"^[a-z]+\d+$", name):
            return re.sub(r"\d+$", "", name)
        return None

    @staticmethod
    def _read_diskstats_sectors(dev_name: Optional[str]) -> Optional[Tuple[int, int]]:
        if not dev_name:
            return None
        try:
            with open("/proc/diskstats", "r", encoding="utf-8") as f:
                for line in f:
                    cols = line.split()
                    if len(cols) < 14:
                        continue
                    if cols[2] != dev_name:
                        continue
                    sectors_read = int(cols[5])
                    sectors_written = int(cols[9])
                    return sectors_read, sectors_written
        except OSError:
            return None
        return None
