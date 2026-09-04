# AGENTS.md — orangepi-build

## Project Overview

Secondary fork of the official Orange Pi build system (itself derived from Armbian). Most of the codebase matches the upstream Orange Pi repository. Key additions in this fork:

- **PREEMPT_RT kernel support** — adds RT kernel branch options and corresponding defconfigs (e.g., `linux-rockchip-rk3588-current-rt.config` in `userpatches/`)
- **Custom package installation** — additional packages and configurations layered on top of the stock image build

Produces bootable Debian/Ubuntu images targeting Rockchip (RK3588/RK3566/RK3399), Allwinner (H6/H616), Starfive (JH7110), and Ky (X1) SoCs.

**Language**: Bash (100%). No Makefile, no CI/CD, no formal test suite.

## Directory Layout

```
orangepi-build/
├── build.sh                        # Entry point (sources scripts/general.sh → scripts/main.sh)
├── scripts/                        # Core build scripts
│   ├── main.sh                     # Build orchestration — sources all other scripts
│   ├── general.sh                  # Utility functions (display_alert, exit_with_error, fetch_from_repo, prepare_host)
│   ├── compilation.sh              # compile_kernel(), compile_uboot(), compile_atf(), advanced_patch()
│   ├── configuration.sh            # Build defaults (VENDOR, compilers, mirrors, DEB paths)
│   ├── debootstrap.sh              # Debian/Ubuntu rootfs bootstrap
│   ├── distributions.sh            # Distribution-specific config
│   ├── desktop.sh                  # Desktop environment setup
│   ├── image-helpers.sh            # Image file manipulation
│   ├── makeboarddeb.sh             # Board support package creation
│   ├── chroot-buildpackages.sh     # Chroot package building
│   ├── build-all-ng.sh             # Multi-board batch builds
│   ├── extensions.sh               # Extension/hook system
│   └── pack-uboot.sh              # U-Boot packaging
├── external/
│   ├── config/
│   │   ├── boards/                 # Board configs (57+ .conf files: orangepicm5.conf, etc.)
│   │   ├── sources/                # Arch configs (arm64.conf) and families/ (rockchip-rk3588.conf)
│   │   ├── kernel/                 # Kernel defconfigs
│   │   ├── distributions/          # OS release configs (jammy, bookworm, focal, bullseye)
│   │   └── templates/              # Dockerfile, Vagrantfile, config templates
│   ├── packages/                   # BSP packages, blobs, extras
│   ├── patch/                      # Kernel/ATF/U-Boot patches
│   └── extensions/                 # Build extensions (grub.sh, flash-kernel.sh)
├── userpatches/                    # User overrides (gitignored)
│   ├── config-default.conf         # Active config (symlink → config-example.conf)
│   ├── config-example.conf         # Template: BOARD, BRANCH, RELEASE, BUILD_OPT
│   ├── customize-image.sh          # Runs in chroot after rootfs install
│   ├── overlay/                    # Files copied onto rootfs
│   ├── atf/                        # User ATF patches
│   └── misc/                       # User misc patches
├── kernel/                         # Kernel source (gitignored, populated at build time)
├── u-boot/                         # U-Boot source (gitignored, populated at build time)
├── toolchains/                     # Cross-compilers (gitignored, downloaded at build time)
└── output/                         # Build artifacts (gitignored)
    ├── images/                     # Final .img files
    ├── debs/                       # Debian packages
    └── debug/                      # Build logs
```

## Build Commands

All builds require root. Run from the repo root.

```bash
# Interactive (whiptail menus select board/branch/release/target)
sudo ./build.sh

# Non-interactive full image build
sudo ./build.sh BOARD=orangepicm5 BRANCH=current RELEASE=jammy BUILD_OPT=image

# Build only kernel
sudo ./build.sh BOARD=orangepicm5 BRANCH=current BUILD_OPT=kernel

# Build only U-Boot
sudo ./build.sh BOARD=orangepicm5 BRANCH=legacy BUILD_OPT=u-boot

# Docker-based build (installs Docker if missing)
sudo ./build.sh docker

# Use a named config file (loads userpatches/config-<name>.conf)
sudo ./build.sh myconfig
# Or: CONFIG=userpatches/config-myconfig.conf sudo ./build.sh
```

### Key Environment Variables

| Variable | Values | Description |
|----------|--------|-------------|
| `BOARD` | `orangepicm5`, `orangepi5`, ... | Target board (see `external/config/boards/`) |
| `BRANCH` | `legacy`, `current` | Kernel branch (legacy=5.10, current=6.1 for RK3588) |
| `RELEASE` | `jammy`, `bookworm`, `focal`, `bullseye`, `noble` | Debian/Ubuntu release |
| `BUILD_OPT` | `u-boot`, `kernel`, `rootfs`, `image` | Build target |
| `KERNEL_CONFIGURE` | `yes`, `no` | Open `menuconfig` during kernel build |
| `CLEAN_LEVEL` | `debs,oldcache,images,cache,sources` | Comma-separated clean targets |
| `DOWNLOAD_MIRROR` | mirror URL | Override default download mirror |
| `OFFLINE_WORK` | `yes` | Skip source downloads |

## Testing & CI

**None.** No CI/CD pipelines, no automated tests, no linter configs. Validation is manual: build an image, flash it, boot it on hardware.

The codebase uses `# shellcheck source=...` directives but has no `.shellcheckrc` or enforced linting.

## Code Conventions

### Shell Style
- **Shebang**: `#!/bin/bash` (scripts), `#!/usr/bin/env bash` (build.sh)
- **Indentation**: Tabs
- **Variables**: `UPPER_SNAKE_CASE` everywhere. Locals declared with `local`. Expand with `"${VAR}"` (curly braces, double quotes).
- **Functions**: `lowercase_with_underscores`. Opening brace on same line or next line (inconsistent).
- **Conditionals**: `[[ ]]` exclusively (never `[ ]`). Patterns: `[[ $VAR == value ]]`, `[[ $VAR =~ regex ]]`.
- **Defaults**: `[[ -z $VAR ]] && VAR="default"`
- **Error handling**: No `set -e`. Uses `exit_with_error "message" "highlight"`. Pipeline checks via `[[ ${PIPESTATUS[0]} -ne 0 ]]`. `|| exit` after `cd`.
- **Logging**: `display_alert "message" "detail" "level"` where level ∈ {`info`, `wrn`, `err`, `ext`}.
- **Source**: `source "${SRC}"/scripts/filename.sh` with preceding `# shellcheck source=scripts/filename.sh`.
- **Comments**: GPLv2 license header at top. Function list in comment block. `#` inline. Separator lines `#----...----`.

### Board Config Pattern

Board configs in `external/config/boards/*.conf`:
```bash
BOARD_NAME="Orange Pi CM5"
BOARDFAMILY="rockchip-rk3588"
BOOTCONFIG="orangepi_cm5_defconfig"
KERNEL_TARGET="legacy,current"
BOOT_FDT_FILE="rockchip/rk3588s-orangepi-cm5.dtb"
BOOT_SCENARIO="spl-blobs"
```

Family configs in `external/config/sources/families/*.conf` define kernel repos, branches, and include common configs via `source "${SRC}/external/config/sources/include/*.inc"`.

### Extension System

Hook-based extension system in `scripts/extensions.sh`:
- Hooks named `hookpoint__extensionname()`
- Invoked via `call_extension_method "hookpoint" "description"`
- Registered via `enable_extension "name"`
- CLI: `ENABLE_EXTENSIONS="ext1,ext2" ./build.sh`

## Key Files for Common Tasks

| Task | Files to Edit |
|------|---------------|
| Add/modify a board | `external/config/boards/<board>.conf` |
| Change kernel config | `external/config/kernel/linux-<family>-<branch>.config` or `userpatches/` override |
| Add kernel patches | `external/patch/kernel/<family>-<branch>/` or `userpatches/kernel/` |
| Customize rootfs | `userpatches/customize-image.sh` (runs in chroot) |
| Overlay files onto image | `userpatches/overlay/` |
| Change compilation flow | `scripts/compilation.sh` |
| Modify build defaults | `scripts/configuration.sh` |
| Add build extension | `external/extensions/<name>.sh` |
| Change SoC family config | `external/config/sources/families/<family>.conf` |
