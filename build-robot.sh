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
# 默认输出: 纯文本（去除 ANSI 控制码，将进度回车转换为换行）
# 原始终端进度: BUILD_ROBOT_RAW_OUTPUT=yes ./build-robot.sh ...
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

# build.sh/pv 使用回车和 ANSI 控制码刷新进度。直接 tee 会把这些控制码
# 同时写入日志，终端复制或日志查看器会出现阶梯式缩进和乱码。
plain_output() {
	sed -u -e $'s/\033\\[[0-?]*[ -/]*[@-~]//g' -e 's/\r/\n/g'
}

if [[ ${BUILD_ROBOT_RAW_OUTPUT:-no} == yes ]]; then
	sudo ./build.sh "${CONFIG}" "BUILD_OPT=${OPT}" 2>&1 | tee "${LOG}"
else
	sudo ./build.sh "${CONFIG}" "BUILD_OPT=${OPT}" 2>&1 | plain_output | tee "${LOG}"
fi
