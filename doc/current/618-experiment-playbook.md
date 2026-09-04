# 6.18 + PREEMPT_RT 移植执行计划 — RK3588S CM5-CC

日期：2026-06-14
状态：Phase 0-1 已完成，Phase 2 推进中

## 版本选择说明

选择 6.18 而非 6.12：
- 比 6.12 多约 1 年的 RK3588 修复积累
- PREEMPT_RT 补丁更小（~9K vs ~20K）
- CSI ISP 管线在两条主线版本上均无 RK3588 驱动支持，不影响选择

## 当前进度

Phase 0（基础搭建）✅ | Phase 1（系列口）✅ | Phase 2-3（外设覆盖）✅ | 总体 ~85%

| 指标 | 6.1 vendor | 6.18 当前 |
|------|:---------:|:---------:|
| DTS 行数 | 1215 行 | 1034 行 (85%) |
| `status = "okay"` | ~90 | 42 (47%) |
| `status = "disabled"` | 30 | 20 (67%) |

**外设覆盖：全部已到位，等待硬件验证**

### 已就绪的外设清单（42 okay / 20 disabled）

| 类别 | 外设 | 状态 |
|------|------|:----:|
| **启动基础** | UART2 串口, eMMC, SD 卡, HDMI, USB 2.0/3.0, 以太网, PCIe | ✅ **Phase 1** |
| **PMIC** | RK806 (SPI2), CPU/GPU 调压器, RTC (HYM8563) | ✅ **Phase 1** |
| **CSI 摄像头** | CSI D-PHY0, OV5647/IMX219 sensor 节点, cam1 overlay | ✅ **待 ISP 驱动** |
| **音频** | ES8388 codec (I2C3), es8388_sound, I2S2, SPDIF | ✅ **Phase 2a** |
| **USB-C** | FUSB302 PD, sc89890 充电器, USBD PHY0, OTG | ✅ **Phase 2a** |
| **LED/风扇** | GPIO 状态灯 (heartbeat), PWM 温控风扇 | ✅ **Phase 2a** |
| **无线** | SDIO Wi-Fi (AP6256), BT (UART9) | ✅ **Phase 2b** |
| **GPIO 引脚** | UART1/4/6/7/9, PWM0/1/3/13/15, SPI0/1 | ✅ **Phase 3a** |
| **显示** | DSI1 接口 | ✅ **Phase 3a** |
| **DSI 触控屏** | 跳过 — 不需要 | ⏭️ |

**注意：CSI ISP 管线 (rkcif/rkisp1 for RK3588) 在 6.18 主线不存在。**
sensor DTS 节点已就绪，待主线合入驱动后直接可用。

## 下一步：Phase 4 — 构建镜像 + 硬件启动验证

每个任务 = 1 次提交 = 1 类独立外设
- 提交后 DTC 编译必须通过 ✅
- 不需要等待硬件验证就能合并到分支
- 可在硬件就绪后逐项勾选验证

## CSI ISP 状态

CSI 摄像头驱动（rkcif/rkisp1 for RK3588）在 6.18 主线中不存在，
也不存在于 Any 6.18 厂商分支（Radxa 等）。
**不在本计划范围内。** sensor DTS 节点已就绪，
待主线未来合入 ISP 驱动后直接可用。
| HDMI | CM5 Base 基本一致 | ✅ 小调整 |
| USB 2.0/3.0 主机 | CM5 Base + CM5-CC 额外 `u2phy3` | 小改 |
| 以太网 (gmac1) | CM5 Base — 确认 PHY 型号 | 待确认 PHY |
| SD 卡 (sdmmc) | CM5 Base + CM5-CC 一致 | ✅ |

**DTS 适配策略：**
1. `#include "rk3588s-orangepi-cm5.dtsi"`（主线 SoM dtsi 不含载板内容）
2. 以主线 `rk3588s-orangepi-cm5-base.dts` 为蓝本，创建新文件
3. 替换/新增 CM5-CC 特有的节点（USB-C PD、ES8388、CSI 等）
4. **Phase 1 不启用 overlay**，必要外设硬编码入 DTS
5. 验证 `dtbs` 编译 + `dtc -I dtb -O dts` 反编译确认正确

### Phase 2: 外设深度适配（预计 3-5 天）

| 子项 | 工作内容 | 风险 |
|------|---------|------|
| **CSI 摄像头 (cam1)** | 移植 camera1 dtsi → 作为 overlay 或 DTS include。主线 `rkisp1` 接口与 vendor 不同 | ⚠️ 中 |
| **ES8388 音频** | 主线 ASoC `es8388` 已支持。移植 `es8388_sound` + `i2c3` 节点 | ✅ 低 |
| **MIPI DSI 触控屏** | 移植 LCD dtsi + `gt9xx` 触控节点 | ⚠️ 中 |
| **USB-C PD 充电** | `fusb302` + `sc89890` 均主线支持，移植 DTS 节点 | ✅ 低 |
| **SDIO Wi-Fi/BT** | `ap6256` + `uart9` + sdio 节点 | ✅ 低 |
| **7 个 CM5-CC overlay** | 按主线规范重写 `.dtso` | ✅ 低 |
| **`rk3588-linux.dtsi` 内容移植** | 提取 vendor 2 行内容到 DTS | ⚠️ 需检查 |

### Phase 3: PREEMPT_RT 验证（预计 2 天）

```
[ ] uname -a → SMP PREEMPT_RT
[ ] cyclictest: 最大延迟 < 100μs
[ ] nohz_full=6,7 rcu_nocbs=6,7 isolcpus=...,domain...,6,7 irqaffinity=0-5
[ ] CAN/以太网 IRQ 绑定到 control 域
[ ] ROS2 Jazzy 发布/订阅延迟
```

### Phase 4: 接通 build 系统（0.5 天）

1. `KERNEL_CONFIGURE=no` + 已生成的 config
2. `OVERLAY_MERGE="partial"`（overlay 就绪后）
3. `sudo ./build.sh 618-experiment BUILD_OPT=image`

## Phase 4 — 首次镜像构建验证

构建系统已就绪。只需以下两步即可触发首次构建：

### 步骤 1：创建本地配置文件

```bash
cd /home/hpw/Developments/WorkSpaces/LinuxCross_ws/RK3588s-CM5/orangepi-build
cp userpatches/config-opibot.conf userpatches/config-618-experiment.conf
```

编辑 `userpatches/config-618-experiment.conf`，确保：
- `BRANCH="experimental"`（已从 config 模板继承）
- `KERNELSOURCE="https://github.com/horizon105457/linux-orangepi.git"`（已设置）
- `OVERLAY_MERGE="none"`（首次构建不需要 overlay 合并）
- `RELEASE="noble"`（Ubuntu 24.04）

### 步骤 2：触发构建

```bash
# 方式 A: 命令行
sudo ./build.sh 618-experiment BUILD_OPT=image

# 方式 B: VS Code 任务
# Ctrl+P → Tasks: Run Task → 6.18-Exp: build image (timeout)
```

### 首次启动验证清单

```
[ ] 串口日志正常输出, 登录提示
[ ] uname -a 显示 PREEMPT_RT
[ ] dmesg 无关键错误
[ ] eMMC 正确挂载 rootfs
[ ] HDMI 输出图形界面
[ ] 以太网连接 (dhcpcd)
[ ] USB 端口识别 (lsusb)
[ ] PCIe 设备检测 (lspci)
```

### 外设逐项验证

镜像启动后按以下顺序验证外设：

```bash
# 音频测试
sudo modprobe snd-soc-es8388
speaker-test -t sine -f 440 -l 1   # 需先通过 overlay 启用 es8388

# USB-C 检测
i2cdetect -y 6                     # FUSB302 @ 0x22, sc89890 @ 0x6a

# LED 状态
cat /sys/class/leds/status_led/trigger

# SDIO Wi-Fi（加载覆盖层后）
nmcli dev status

# UART 环路测试（接线后）
stty -F /dev/ttyS1 115200 && echo hello > /dev/ttyS1

# SPI 测试
spidev_test -D /dev/spidev0.0

# CAN 总线（需加载覆盖层）
ip link set can0 type can bitrate 500000
ip link set can0 up
```

### 注意

- `OVERLAY_MERGE=none` 意味着 `customize-image.sh` 中的 `InjectCm5CcOverlayHints` 和 `ConfigureRTKernel` 会执行但 overlay 不会合并到 rootfs
- `KERNEL_CONFIGURE=yes` 会在构建时打开 menuconfig，首次构建可以保留该选项用于微调
- `build_rt_image=yes` 配合 `BRANCH=experimental` 会使用 `KERNELBRANCH=branch:6.18-rk35xx-rt`

## 工作量估算

| 阶段 | 内容 | 预估 | 交付物 |
|------|------|------|--------|
| Phase 0 | 基础搭建 + 首次编译 | 1 天 | `6.18-rk35xx-rt` 分支 |
| Phase 1 | 载板 DTS + 6 项基础外设 | 2-3 天 | CM5-CC DTS, 基础启动 |
| Phase 2 | 全部外设 + overlay | 4-5 天 | 完整的 DTS/overlay 体系 |
| Phase 3 | RT 验证 + 调优 | 2 天 | 验证报告 |
| Phase 4 | Build 系统接通 | 0.5 天 | 完整镜像构建 |

## 已知风险

| 风险 | 级别 | 说明 |
|------|------|------|
| **`rk3588-linux.dtsi`** | ⚠️ | 若包含主线缺失的 clock/pinctrl 修补，需额外 cherry-pick |
| **CSI ISP 接口差异** | ⚠️ | 主线 `rkisp1` media controller API 与 vendor 不同 |
| **以太网 PHY** | ⚠️ | CM5-CC 可能用不同 PHY (非 YT8531)，需确认并找对应驱动 |
| **NPU 用户态** | ⚠️ | 主线 `rocket` 与 RKNN SDK 兼容性未验证。非 Phase 1/2 阻塞 |
| **GPU Panfrost** | ✅ 低 | 若不稳定可回退 fbdev |

## 关键参考文件

| 文件 | 位置 |
|------|------|
| 主线 CM5 SoM DTSI | mainline `rk3588s-orangepi-cm5.dtsi` |
| 主线 CM5 Base 载板 DTS | mainline `rk3588s-orangepi-cm5-base.dts` |
| 主线 SoC DTSI | mainline `rk3588s.dtsi` |
| 主线 PMIC 绑定 | mainline `include/dt-bindings/regulator/rockchip,rk806.h` |
| Vendor CM5-CC DTS (参考) | 本分支 `85fef99a3` — `rk3588s-orangepi-cm5-cc.dts` |
| Vendor camera/LCD dtsi (参考) | 本分支 — `rk3588s-orangepi-cm5-cc-camera{1,2,3}.dtsi`, `lcd.dtsi` |
| Vendor overlay (参考) | 本分支 — `overlay/rk3588-opicm5-cc-*.dts` |
