#!/usr/bin/env bash
# =============================================================================
# can0-setup.sh — RK3588s CAN 接口启动脚本 (默认 can1, 预置 can1-m1 overlay)
#
# RK3588 内置 CAN 2.0B/CANFD 控制器 (rockchip_canfd 驱动), 非 SPI 外挂。
#   - 修改 bitrate/restart-ms/等待时间 → 改本脚本 (或环境变量), 无需改 unit
#   - 附加步骤 → 放入 /etc/can0-setup.d/*.sh (可执行), 无需改本脚本
# 由 RK3588s 机器人镜像打包阶段安装到 /usr/local/sbin/can0-setup.sh
# =============================================================================
set -uo pipefail

CAN_IFACE="${CAN_IFACE:-can1}"
CAN0_BITRATE="${CAN0_BITRATE:-1000000}"
CAN0_RESTART_MS="${CAN0_RESTART_MS:-100}"

# ── 等待驱动枚举 (CAN 控制器 probe 可能需数秒) ──────────────────────────────
for i in $(seq 1 30); do
    [[ -e "/sys/class/net/${CAN_IFACE}" ]] && break
    sleep 1
done
if [[ ! -e "/sys/class/net/${CAN_IFACE}" ]]; then
    # 无外设接入时不报错（像 USB 一样）：接口未使能/未接硬件时优雅跳过
    echo "NOTE: CAN interface ${CAN_IFACE} not present — skipped (attach hardware or enable can1-m1 overlay)"
    exit 0
fi

# ── 配置并启用 (restart-ms: bus-off 内核自动恢复) ───────────────────────────
/usr/sbin/ip link set "${CAN_IFACE}" down 2>/dev/null || true
sleep 0.5

configure_can() {
    /usr/sbin/ip link set "${CAN_IFACE}" up type can \
        bitrate "${CAN0_BITRATE}" restart-ms "${CAN0_RESTART_MS}"
}
configured=0
for attempt in 1 2 3; do
    if configure_can 2>&1; then
        configured=1
        break
    fi
    echo "WARN: ip link set ${CAN_IFACE} up failed (attempt ${attempt}/3), retrying..." >&2
    sleep 1
done
if [[ "${configured}" -ne 1 ]]; then
    echo "ERROR: ip link set ${CAN_IFACE} up failed after 3 attempts" >&2
    exit 1
fi
echo "${CAN_IFACE} configured: bitrate=${CAN0_BITRATE} restart-ms=${CAN0_RESTART_MS}"
/usr/sbin/ip -details link show "${CAN_IFACE}"

# ── 扩展钩子目录 (可选, 加步骤=加文件, 无需改本脚本) ───────────────────────
if [[ -d /etc/can0-setup.d ]]; then
    for hook in /etc/can0-setup.d/*.sh; do
        [[ -x "${hook}" ]] && "${hook}" "${CAN_IFACE}"
    done
fi

exit 0
