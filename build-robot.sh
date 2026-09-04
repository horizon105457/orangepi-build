#!/usr/bin/env bash
# =============================================================================
# build-robot.sh — 61-rt 机器人镜像构建入口（自动日志重定向）
#
# 用法:
#   ./build-robot.sh            # 全量镜像 (BUILD_OPT=image)
#   ./build-robot.sh kernel     # 仅内核包 (BUILD_OPT=kernel, 快速验证)
#   ./build-robot.sh image      # 全量镜像（同上）
#
# 日志: <本仓库>/log/61-rt-<opt>-<时间戳>.log （仓库级，gitignored）
# 配置: userpatches/config-61-rt-local.conf （本地配置，含 OPI_PWD）
# =============================================================================
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPT="${1:-image}"
CONFIG="${2:-61-rt-local}"

case "${OPT}" in
	kernel|image) ;;
	*) echo "用法: $0 [kernel|image] [config-name]"; exit 1 ;;
esac

LOG_DIR="${SELF_DIR}/log"
mkdir -p "${LOG_DIR}"
LOG="${LOG_DIR}/61-rt-${OPT}-$(date +%Y%m%d-%H%M%S).log"

echo "=============================================="
echo "  61-rt 构建  config=${CONFIG}  opt=${OPT}"
echo "  日志: ${LOG}"
echo "=============================================="

cd "${SELF_DIR}"
# tee 以调用用户运行（日志归用户），sudo 仅作用于 build.sh
exec sudo ./build.sh "${CONFIG}" "BUILD_OPT=${OPT}" 2>&1 | tee "${LOG}"
