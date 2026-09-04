#!/usr/bin/env bash
# ------------------------------------------------------------------
# Generate a .config for 6.18 experimental RT kernel build
#
# Usage from repo root:
#   sudo ./build.sh 618-experiment KERNEL_CONFIGURE=yes BUILD_OPT=kernel
#
# The build system will copy the existing linux-rockchip-rk3588-experimental.config
# into the kernel tree and open menuconfig. This script can also be run directly
# inside the kernel source tree for offline configuration:
#
#   make defconfig
#   ./scripts/config -e CONFIG_PREEMPT_RT
#   ./scripts/config -e CONFIG_PREEMPT_RT_FULL   # if available on this kernel
#   ./scripts/config -d CONFIG_PREEMPT
#   ./scripts/config -d CONFIG_PREEMPT_VOLUNTARY
#   ./scripts/config -e CONFIG_HIGH_RES_TIMERS
#   ./scripts/config -e CONFIG_NO_HZ_FULL
#   ./scripts/config -e CONFIG_RCU_NOCB_CPU
#   ./scripts/config --set-val CONFIG_HZ 1000
#   make savedefconfig
#   cp defconfig arch/arm64/configs/rk3588_experimental_defconfig
#
# Then copy the resulting .config or defconfig back to:
#   external/config/kernel/linux-rockchip-rk3588-experimental.config
# ------------------------------------------------------------------

set -euo pipefail

echo "[612-gen] This script documents the manual config generation steps."
echo "[612-gen] See the comments in the script body for details."
echo
echo "Phase 1 steps inside kernel source tree:"
echo "  1. make defconfig"
echo "  2. make menuconfig  → select PREEMPT_RT"
echo "  3. Copy .config back to external/config/kernel/"
echo
echo "Quick automation (run inside kernel source):"
cat <<'SHELL'
  make defconfig
  ./scripts/config \
    -e CONFIG_PREEMPT_RT \
    -d CONFIG_PREEMPT \
    -d CONFIG_PREEMPT_VOLUNTARY \
    -e CONFIG_NO_HZ_FULL \
    -e CONFIG_RCU_NOCB_CPU \
    -e CONFIG_HIGH_RES_TIMERS \
    --set-val CONFIG_HZ 1000
  make olddefconfig
SHELL
