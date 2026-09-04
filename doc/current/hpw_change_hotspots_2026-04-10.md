# hpw 变更热区地图

日期：2026-04-10

目标：

1. 给双仓开发环境建立一份面向 hpw 提交的导航文档。
2. 让后续排查、重构、技术债清理优先落在真实高频改动区。
3. 降低在官方代码、低价值历史材料和构建副本中跑偏的风险。

## 1. 使用方式

先回答三个问题：

1. 问题属于内核主仓还是 build 集成仓。
2. 问题属于 RT 基线、板级 DTS/overlay、镜像集成，还是运行时编排。
3. 问题是否已经落在 hpw 的高频改动区。

若答案落在本图列出的热区内，优先从对应文件和提交进入，而不是从全仓随机搜索。

## 2. 双仓事实边界

### linux-orangepi-rt

当前角色：RT 内核源码主仓。

优先处理：

1. PREEMPT_RT 基线。
2. CM5-CC DTS。
3. 板级 overlay。
4. dtb 安装链路。

### orangepi-build

当前角色：镜像构建、overlay、userpatches、rootfs 定制、运行时集成验证仓。

优先处理：

1. RT 内核构建接入。
2. 镜像内项目级集成。
3. 运行时模式与 systemd 编排。
4. 开发文档与验证入口。

## 3. hpw 在 orangepi-build 的热区

### 热区 A：RT 内核接入与 defconfig

关键提交：

1. `419d3ad` `feat: add PREEMPT_RT kernel build support for RK3588S (OrangePi CM5)`
2. `06389dd` `fix: patch Wi-Fi credential flow, update RT kernel configs, clean dead code`
3. `c21befc` `chore: commit staged workspace changes`

主要文件：

1. [external/config/kernel/linux-rockchip-rk3588-current-rt.config](../../external/config/kernel/linux-rockchip-rk3588-current-rt.config)
2. [external/config/kernel/linux-rockchip-rk3588-current-rt-opicm5-cc.config](../../external/config/kernel/linux-rockchip-rk3588-current-rt-opicm5-cc.config)
3. [external/config/kernel/linux-rockchip-rk3588-current-rt-opicm5-tablet.config](../../external/config/kernel/linux-rockchip-rk3588-current-rt-opicm5-tablet.config)
4. [external/config/sources/families/rockchip-rk3588.conf](../../external/config/sources/families/rockchip-rk3588.conf)

问题类型：

1. RT defconfig 是否正确进入 build。
2. 板型对应的 RT 配置是否对齐。
3. build 仓如何指向外部 RT 内核仓。

### 热区 B：镜像集成主入口

关键提交：

1. `4065387` `Save current OPiBot image integration state`
2. `693f54c` `refactor: commit unstaged customize-image adjustments`
3. `c21befc` `chore: commit staged workspace changes`

主要文件：

1. [userpatches/customize-image.sh](../../userpatches/customize-image.sh)
2. [userpatches/config-opibot.conf](../../userpatches/config-opibot.conf)

问题类型：

1. overlay 是否进入镜像。
2. RT 相关 service 是否被 enable。
3. ROS2/OpenCV/mDNS/桌面组件是否在构建期正确植入。
4. 用户态依赖、权限与部署文档是否随镜像下发。

### 热区 C：运行时模式与 systemd 编排

关键提交：

1. `4065387` `Save current OPiBot image integration state`

主要文件：

1. [userpatches/overlay/etc/default/opibot-runtime-mode](../../userpatches/overlay/etc/default/opibot-runtime-mode)
2. [userpatches/overlay/etc/default/opibot-boot-profile](../../userpatches/overlay/etc/default/opibot-boot-profile)
3. [userpatches/overlay/etc/default/opibot-irq-layout](../../userpatches/overlay/etc/default/opibot-irq-layout)
4. [userpatches/overlay/etc/default/opibot-service-layout](../../userpatches/overlay/etc/default/opibot-service-layout)
5. [userpatches/overlay/usr/local/sbin/opibot-runtime-mode](../../userpatches/overlay/usr/local/sbin/opibot-runtime-mode)
6. [userpatches/overlay/usr/local/sbin/opibot-performance-mode](../../userpatches/overlay/usr/local/sbin/opibot-performance-mode)
7. [userpatches/overlay/usr/local/sbin/opibot-irq-layout](../../userpatches/overlay/usr/local/sbin/opibot-irq-layout)
8. [userpatches/overlay/usr/local/sbin/opibot-boot-profile-sync](../../userpatches/overlay/usr/local/sbin/opibot-boot-profile-sync)
9. [userpatches/overlay/etc/systemd/system/opibot-runtime-mode.service](../../userpatches/overlay/etc/systemd/system/opibot-runtime-mode.service)
10. [userpatches/overlay/etc/systemd/system/opibot-runtime-autoswitch.service](../../userpatches/overlay/etc/systemd/system/opibot-runtime-autoswitch.service)
11. [userpatches/overlay/etc/systemd/system/opibot-control-prepare.service](../../userpatches/overlay/etc/systemd/system/opibot-control-prepare.service)
12. [userpatches/overlay/etc/systemd/system/opibot-perception-prepare.service](../../userpatches/overlay/etc/systemd/system/opibot-perception-prepare.service)

问题类型：

1. 运行时三态命名是否真的落地。
2. `opibot-runtime-mode` 是否仍只是旧 `opibot-performance-mode` 的兼容壳。
3. `control-active` 与 `perception-active` 是否在 target 启动前切换。
4. autoswitch 是否会误切换或和旧逻辑冲突。

当前最小运行链路：

1. 镜像启动后先进入 `multi-user.target`。
2. [opibot-runtime-mode.service](../../userpatches/overlay/etc/systemd/system/opibot-runtime-mode.service) 调用 `opibot-runtime-mode apply-config`。
3. [opibot-runtime-autoswitch.service](../../userpatches/overlay/etc/systemd/system/opibot-runtime-autoswitch.service) 长驻监控并执行自动切换。
4. [opibot-control-prepare.service](../../userpatches/overlay/etc/systemd/system/opibot-control-prepare.service) 在 `opibot-control.target` 之前执行 `apply control-active`。
5. [opibot-perception-prepare.service](../../userpatches/overlay/etc/systemd/system/opibot-perception-prepare.service) 在 `opibot-perception.target` 之前执行 `apply perception-active`。

### 热区 D：官方 build 接缝上的少量改动

关键提交：

1. `419d3ad`
2. `06389dd`
3. `4065387`
4. `c21befc`

主要文件：

1. [scripts/main.sh](../../scripts/main.sh)
2. [scripts/compilation.sh](../../scripts/compilation.sh)
3. [scripts/image-helpers.sh](../../scripts/image-helpers.sh)

处理原则：

1. 这里只作为接缝区看待。
2. 非阻断问题不要优先进入这里。
3. 若要进入，先证明无法在 `userpatches/`、overlay 或外部 RT 仓解决。

## 4. hpw 在 linux-orangepi-rt 的热区

### 热区 E：PREEMPT_RT 基线

关键提交：

1. `eeaf443e4` `rt: apply PREEMPT_RT patch 6.1.99-rt36`

主要对象：

1. 全局 PREEMPT_RT patch 基线
2. [patch-6.1.99-rt36.patch](../../../linux-orangepi-rt/patch-6.1.99-rt36.patch)

问题类型：

1. RT 行为问题是否源于 patch 基线。
2. 与 Orange Pi 上游 6.1 分支的冲突是否来自 RT patch。

### 热区 F：CM5-CC DTS 与板级 overlay

关键提交：

1. `b03e5140c` `arm64: dts: add rk3588s orangepi cm5-cc and overlay presets`
2. `a91ae6388` `arm64: dts: rockchip: fix cm5-cc camera2/3 endpoint graph links`
3. `dcb75246f` `arm64: dts: overlay: drop cm5-cc uart2-m1 recommendation and build entry`

主要文件：

1. [linux-orangepi-rt/arch/arm64/boot/dts/rockchip/rk3588s-orangepi-cm5-cc.dts](../../../linux-orangepi-rt/arch/arm64/boot/dts/rockchip/rk3588s-orangepi-cm5-cc.dts)
2. [linux-orangepi-rt/arch/arm64/boot/dts/rockchip/rk3588s-orangepi-cm5-cc-camera1.dtsi](../../../linux-orangepi-rt/arch/arm64/boot/dts/rockchip/rk3588s-orangepi-cm5-cc-camera1.dtsi)
3. [linux-orangepi-rt/arch/arm64/boot/dts/rockchip/rk3588s-orangepi-cm5-cc-camera2.dtsi](../../../linux-orangepi-rt/arch/arm64/boot/dts/rockchip/rk3588s-orangepi-cm5-cc-camera2.dtsi)
4. [linux-orangepi-rt/arch/arm64/boot/dts/rockchip/rk3588s-orangepi-cm5-cc-camera3.dtsi](../../../linux-orangepi-rt/arch/arm64/boot/dts/rockchip/rk3588s-orangepi-cm5-cc-camera3.dtsi)
5. [linux-orangepi-rt/arch/arm64/boot/dts/rockchip/overlay/rk3588-opicm5-cc-default-overlays.txt](../../../linux-orangepi-rt/arch/arm64/boot/dts/rockchip/overlay/rk3588-opicm5-cc-default-overlays.txt)

问题类型：

1. 板级外设默认启用关系。
2. camera graph、LCD、无线、USB 网卡等 overlay 预设。
3. 默认 overlay 推荐项是否合理。

### 热区 G：dtb 安装接缝

关键提交：

1. `80c266675` `scripts: dtbinst support default overlay txt install`

主要文件：

1. [linux-orangepi-rt/scripts/Makefile.dtbinst](../../../linux-orangepi-rt/scripts/Makefile.dtbinst)

问题类型：

1. 默认 overlay txt 是否被正确安装到镜像可消费位置。
2. build 仓的板级默认 overlay 是否和内核仓安装逻辑对齐。

## 5. 当前最值得优先清债的地方

### 优先级 1

1. `opibot-runtime-mode` 与 `opibot-performance-mode` 的兼容壳关系
2. `customize-image.sh` 的持续膨胀与职责混杂

### 优先级 2

1. RT defconfig 在 build 仓中的多板型扩散
2. build 仓少量官方脚本接缝缺少更清晰边界

### 优先级 3

1. 历史诊断文档与当前规则文档的事实边界维护
2. 开发任务与工作区设置的持续整理

## 6. 后续工作建议顺序

1. 先从 [userpatches/customize-image.sh](../../userpatches/customize-image.sh) 和运行时脚本层做只读职责审计。
2. 再审计 `opibot-runtime-mode` 到旧 `opibot-performance-mode` 的兼容链是否可以逐步收敛。
3. 内核相关问题直接回到 linux-orangepi-rt 对应 DTS/overlay 或 RT 基线提交面处理。
4. 避免优先进入 build 仓官方脚本接缝，除非已证明是构建阻断点。