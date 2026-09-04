#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# userscripts/config-rt-patch.bash
#
# RT patch utility for RK3588S (OrangePi CM5).
#
# For normal builds, the RT-patched kernel is already at:
#   https://github.com/horizon105457/linux-orangepi (branch: orange-pi-6.1-rk35xx-rt)
# The build system fetches it automatically when build_rt_image=yes.
#
# This script is for local re-application of the RT patch if needed
# (e.g., rebasing onto newer upstream, verifying patch integrity).
###############################################################################

RT_PATCH_VERSION="6.1.99-rt36"
RT_PATCH_URL="https://cdn.kernel.org/pub/linux/kernel/projects/rt/6.1/older/patch-${RT_PATCH_VERSION}.patch.xz"
UPSTREAM_BRANCH="orange-pi-6.1-rk35xx"
RT_BRANCH="orange-pi-6.1-rk35xx-rt"
FORK_REMOTE="https://github.com/horizon105457/linux-orangepi.git"

SCRIPT_SOURCE="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
WORK_DIR="$(dirname "$SCRIPT_DIR")"

KERNEL_DIR="$WORK_DIR/kernel/orange-pi-6.1-rk35xx"
PATCH_DIR="/tmp/rt-patch"
PATCH_FILE="$PATCH_DIR/patch-${RT_PATCH_VERSION}.patch"

printf "[info] RT patch version: %s\n" "$RT_PATCH_VERSION"
printf "[info] Workspace root: %s\n" "$WORK_DIR"

case "${1:-info}" in
  info)
    printf "\nUsage: %s <command>\n\n" "$0"
    printf "Commands:\n"
    printf "  info       Show this help (default)\n"
    printf "  download   Download the RT patch to %s\n" "$PATCH_DIR"
    printf "  apply      Download + apply patch to local kernel tree at %s\n" "$KERNEL_DIR"
    printf "\nFor normal builds, just set build_rt_image=yes in your config.\n"
    printf "The build system will fetch the pre-patched kernel from GitHub automatically.\n"
    ;;

  download)
    mkdir -p "$PATCH_DIR"
    if [[ -f "$PATCH_FILE" ]]; then
      printf "[info] Patch already exists: %s\n" "$PATCH_FILE"
    else
      printf "[info] Downloading %s ...\n" "$RT_PATCH_URL"
      wget -q -O "${PATCH_FILE}.xz" "$RT_PATCH_URL"
      xz -d "${PATCH_FILE}.xz"
      printf "[info] Downloaded and extracted: %s (%s bytes)\n" "$PATCH_FILE" "$(stat -c%s "$PATCH_FILE")"
    fi
    ;;

  apply)
    "$0" download

    if [[ ! -d "$KERNEL_DIR" ]]; then
      printf "[error] Kernel source not found at %s\n" "$KERNEL_DIR"
      printf "[info]  Run: sudo ./build.sh BOARD=orangepicm5 BRANCH=current BUILD_OPT=kernel KERNEL_CONFIGURE=no\n"
      exit 1
    fi

    printf "[info] Dry-run patch test...\n"
    if patch --dry-run -p1 -d "$KERNEL_DIR" < "$PATCH_FILE" > /dev/null 2>&1; then
      printf "[info] Dry-run passed. Applying patch...\n"
      patch -p1 -d "$KERNEL_DIR" < "$PATCH_FILE"
      printf "[info] RT patch applied successfully to %s\n" "$KERNEL_DIR"
    else
      printf "[warn] Dry-run had issues. Attempting with --force...\n"
      patch -p1 --force -d "$KERNEL_DIR" < "$PATCH_FILE" || {
        printf "[error] Patch application failed. Check .rej files in %s\n" "$KERNEL_DIR"
        exit 2
      }
    fi

    printf "\n[info] Known conflict files that may need manual resolution:\n"
    printf "  - drivers/tty/serial/8250/8250.h\n"
    printf "  - drivers/tty/serial/8250/8250_port.c\n"
    printf "  - kernel/watchdog.c\n"
    ;;

  *)
    printf "[error] Unknown command: %s\n" "${1}"
    "$0" info
    exit 1
    ;;
esac
