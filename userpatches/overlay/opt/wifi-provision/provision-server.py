#!/usr/bin/env python3
# =============================================================================
# wifi-provision — 轻量 Web 配网服务（运行于 AP 网段 10.42.0.1:80）
#
# 用途：连接 opibot-cm5 配网热点后，浏览器访问 http://10.42.0.1 即可
# 选择/输入 WiFi 完成配网（写入 NM STA profile 并切换）。
# - 网络列表：best-effort 扫描（AP 模式可扫则显示，不可扫则手动输入）
# - profile 命名：opibot-<sanitized-ssid>（可辨识、同 SSID 幂等覆盖、多网络共存）
# 零额外依赖（python3 + nmcli）；AP 同时保留为 SSH 调试通道。
#
# 安全说明：AP 凭据公开（配网热点），本服务无鉴权——仅限配网场景，
# 完成配网后转 STA，热点自动让出射频。
# =============================================================================
import http.server
import socketserver
import subprocess
import uuid
import os
import re
from urllib.parse import parse_qs

HOST = "0.0.0.0"
PORT = 80
NM_DIR = "/etc/NetworkManager/system-connections"
STA_PRIORITY = 200  # 高于 Master(100) 与 AP(10)

SSID_RE = re.compile(r'^[^\x00-\x1f\x7f]{1,32}$')


def sanitize_id(ssid: str) -> str:
    """opibot-<sanitized-ssid> — Unicode 字母数字保留、分隔符转 -、幂等可辨识。"""
    s = re.sub(r"[^\w-]+", "-", ssid, flags=re.UNICODE).strip("-")[:24]
    return s or "sta"


def scan_networks(timeout: int = 8):
    """best-effort: nmcli 扫描（AP 模式可能失败 → 空列表，前端降级手动输入）。"""
    try:
        out = subprocess.run(
            ["nmcli", "-t", "-f", "SSID,SIGNAL,SECURITY", "dev", "wifi", "list"],
            capture_output=True, text=True, timeout=timeout, check=False,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    nets = []
    for line in out.splitlines():
        # -t 分号分隔；SSID 内冒号被 nmcli 转义为 \:（处理时还原）
        parts = line.replace("\\:", "\u0000").split(";")
        if len(parts) < 3:
            continue
        ssid = parts[0].replace("\u0000", ":").strip()
        if not ssid or ssid == "--":
            continue
        try:
            signal = int(parts[1])
        except ValueError:
            signal = 0
        nets.append({"ssid": ssid, "signal": signal, "security": parts[2]})
    # 按信号降序去重（同 SSID 保留最强）
    seen, result = set(), []
    for n in sorted(nets, key=lambda x: -x["signal"]):
        if n["ssid"] in seen:
            continue
        seen.add(n["ssid"])
        result.append(n)
    return result[:20]


def render_page(nets, msg=None, msg_ok=False):
    rows = "".join(
        f'<tr onclick="pick(\'{_html(n["ssid"])}\')">'
        f'<td>{_html(n["ssid"])}</td><td>{n["signal"]}%</td>'
        f'<td>{_html(n["security"])}</td></tr>'
        for n in nets
    )
    list_html = (
        f'<table id="nets"><thead><tr><th>网络</th><th>信号</th><th>安全</th></tr></thead>'
        f'<tbody>{rows}</tbody></table>'
        f'<p class="sub">点击网络自动填入下方 SSID</p>'
        if nets else
        '<p class="sub">未能扫描到网络（热点占用射频）——请手动输入 SSID。</p>'
    )
    msg_html = (
        f'<div class="msg {"ok" if msg_ok else "err"}">{_html(msg)}</div>' if msg else ""
    )
    return f"""<!DOCTYPE html>
<html lang="zh">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>OPiBot 配网</title>
<style>
body{{font-family:system-ui,sans-serif;max-width:440px;margin:40px auto;padding:0 16px;background:#111;color:#eee}}
.card{{background:#1c1c1e;border-radius:12px;padding:24px;box-shadow:0 8px 24px rgba(0,0,0,.4)}}
h1{{font-size:20px;margin:0 0 4px}} p.sub{{color:#999;font-size:13px;margin:4px 0 12px}}
table{{width:100%;border-collapse:collapse;margin:12px 0;font-size:13px}}
th{{text-align:left;color:#888;padding:4px;border-bottom:1px solid #333}}
td{{padding:6px 4px;border-bottom:1px solid #262626;cursor:pointer}}
tr:hover td{{background:#26262a}}
label{{display:block;font-size:13px;color:#bbb;margin:12px 0 4px}}
input{{width:100%;box-sizing:border-box;padding:10px;border-radius:8px;border:1px solid #333;background:#2a2a2c;color:#eee;font-size:15px}}
button{{width:100%;margin-top:16px;padding:12px;border:0;border-radius:8px;background:#0a84ff;color:#fff;font-size:15px;font-weight:600;cursor:pointer}}
button:hover{{background:#0a74df}}
.msg{{margin-top:16px;font-size:13px;word-break:break-all}}
.ok{{color:#30d158}}.err{{color:#ff453a}}
</style></head>
<body><div class="card">
<h1>OPiBot 配网</h1>
<p class="sub">选择网络或手动输入，提交后设备切换连接。</p>
{list_html}
<form method="post" action="/connect">
<label>WiFi 名称 (SSID)</label><input name="ssid" id="ssid" required autocomplete="off">
<label>密码</label><input name="psk" type="password" required>
<button type="submit">连接</button>
</form>
{msg_html}
</div>
<script>
function pick(s){{document.getElementById('ssid').value=s;}}
</script>
</body></html>"""


def _html(v: str) -> str:
    return (v.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
             .replace('"', "&quot;"))


def write_sta_profile(ssid: str, psk: str) -> str:
    def esc(v: str) -> str:
        return v.replace("\\", "\\\\").replace('"', '\\"')

    prof_id = f"opibot-{sanitize_id(ssid)}"
    body = (
        "[connection]\n"
        f"id={prof_id}\n"
        f"uuid={uuid.uuid4()}\n"
        "type=wifi\n"
        "autoconnect=true\n"
        f"autoconnect-priority={STA_PRIORITY}\n"
        "\n"
        "[wifi]\n"
        f"ssid={esc(ssid)}\n"
        "mode=infrastructure\n"
        "\n"
        "[wifi-security]\n"
        "key-mgmt=wpa-psk\n"
        f"psk={esc(psk)}\n"
        "\n"
        "[ipv4]\n"
        "method=auto\n"
        "\n"
        "[ipv6]\n"
        "method=auto\n"
    )
    path = os.path.join(NM_DIR, f"{prof_id}.nmconnection")
    with open(path, "w", encoding="utf-8") as f:
        f.write(body)
    os.chmod(path, 0o600)
    subprocess.run(["nmcli", "connection", "reload"], check=False)
    subprocess.run(["nmcli", "connection", "up", prof_id], check=False)
    return prof_id


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):  # quiet
        pass

    def _send(self, code: int, body: bytes):
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        nets = scan_networks()
        self._send(200, render_page(nets).encode("utf-8"))

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        data = parse_qs(self.rfile.read(length).decode("utf-8", "ignore"))
        ssid = (data.get("ssid") or [""])[0].strip()
        psk = (data.get("psk") or [""])[0].strip()
        if not SSID_RE.match(ssid) or not psk:
            self._send(200, render_page(scan_networks(), "参数无效", False).encode("utf-8"))
            return
        try:
            prof_id = write_sta_profile(ssid, psk)
        except Exception as e:  # noqa: BLE001
            self._send(200, render_page(scan_networks(), f"写入失败: {e}", False).encode("utf-8"))
            return
        self._send(200, render_page(scan_networks(), f"已写入 {prof_id}，设备正在切换网络（30 秒后连接新网络）。", True).encode("utf-8"))


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    with Server((HOST, PORT), Handler) as srv:
        srv.serve_forever()
