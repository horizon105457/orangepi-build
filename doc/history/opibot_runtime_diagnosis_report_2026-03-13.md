# Orange Pi CM5 Tablet 运行时系统诊断报告

- 诊断时间：2026-03-13
- 目标机：Orange Pi CM5 Tablet
- 诊断方式：只读检查，未执行升级、重编译、刷机或重启
- 诊断目标：判断当前镜像是否已具备作为机器人通用基座继续使用的条件，并区分问题归因

## 检查范围

1. 系统基础状态
2. 实时化运行时链路
3. 网络与无线能力
4. 系统稳定性与启动异常
5. 硬件关键能力
6. 机器人基座适用性判断

## Findings

### 1. 严重级别：高

**现象**

实时化运行时链路已随镜像安装，但在目标机上没有形成可验证、可依赖的 RT 落地结果。

**证据**

- 当前内核为 `6.1.99-rt36-rockchip-rk3588-rt`，确认是 `PREEMPT_RT` 内核。
- `/proc/cmdline` 已包含：`nohz_full=6,7`、`rcu_nocbs=6,7`、`isolcpus=managed,domain,6,7`、`irqaffinity=0-3`。
- 已安装运行时链路相关组件：`opibot-performance-mode`、`opibot-runtime-mode`、`opibot-boot-profile-sync`、`opibot-irq-layout`、`runtime-rt-tune`、`rt-verify`、`rt-latency-test.sh`。
- 启动日志显示：`opibot-runtime-mode` 和 `opibot-irq-layout` 在执行时均出现 `awk` 语法错误。
- 目标机 `awk` 实现为 `mawk 1.3.4`。
- `rt-verify` 与 `rt-latency-test.sh` 文件存在，但缺少可执行权限。
- `opibot-performance-mode status` 显示：
  - `boot_profile=rt-high-performance`
  - `boot_runtime_mode=rt-high-performance`
  - `active_mode=rt-high-performance`
  - `current_state=low-power`
- 实际 CPU governor 全部仍为 `schedutil`。
- CPU6、CPU7 的 `cpuidle` 未被禁用。

**影响**

RT 内核和 RT 参数虽然已经具备，但无法证明高性能模式切换、RT 核限电源管理、IRQ 布局与运行时验证链路在目标机上可靠生效。这会直接影响机器人控制/调度链路的实时性可信度，属于阻塞性问题。

**归因**

编译侧

**建议动作**

- 回到编译侧修复运行时脚本对 `mawk` 的兼容性，或明确引入并依赖 `gawk`。
- 修正 `rt-verify` 与 `rt-latency-test.sh` 的安装权限。
- 修复后重新冷启动复核：
  - RT 核 governor 是否切到 `performance`
  - RT 核 `cpuidle` 是否被禁用
  - 关键 IRQ 是否按预期绑定
  - `rt-verify` 是否可执行且输出通过

### 2. 严重级别：中

**现象**

当前网络可用，但无线能力来自外置 USB 网卡，不能证明板载无线链路已经正常。

**证据**

- `NetworkManager` 运行正常。
- `ssh` 服务运行正常。
- 当前 Wi-Fi 已连接，获得 IPv4 地址。
- 活跃无线接口为 `wlx94ba0694f2b1`。
- 该接口对应 sysfs 路径位于 USB 总线。
- `lsusb` 可见 `Realtek 802.11ac NIC (0bda:c820)`。
- `/sys/bus/mmc/devices` 仅见 eMMC 与 SD 卡，未见明显板载 SDIO 无线设备。

**影响**

从远程运维角度，当前具备联网与远程登录能力，不构成部署阻塞；但如果产品设计要求板载无线作为默认能力，则当前证据不足，不能据此认定镜像的板级无线支持已闭环。

**归因**

待确认

**建议动作**

- 先确认目标机 BOM 是否原本就依赖板载 Wi-Fi/BT。
- 若设计要求板载无线，则回编译侧继续核查 DTS、总线枚举、驱动与固件链路。

### 3. 严重级别：中

**现象**

RTC 未见可用设备，系统时间当前依赖网络同步。

**证据**

- `timedatectl` 显示 `RTC time: n/a`。
- 系统中未见 `/dev/rtc*` 节点。
- 未见 `hym8563` 或其他 RTC 枚举日志。

**影响**

在离线冷启动场景下，可能影响日志时间、证书校验、定时任务与跨设备时间一致性。对“机器人通用基座”未必是立即阻塞，但属于基础能力缺口。

**归因**

待确认

**建议动作**

- 确认硬件设计是否包含 RTC。
- 若硬件应具备 RTC，则回编译侧检查 DTS 和驱动。
- 若本机型本就无 RTC，则可在运行时部署阶段使用 NTP 兜底，但需接受离线启动时间风险。

### 4. 严重级别：中

**现象**

板载音频链路与桌面默认配置存在明显不一致，疑似音频设备树或驱动残留。

**证据**

- 启动日志中 `aw87xxx` 在 `0x59` 和 `0x5a` 地址反复探测失败。
- `pulseaudio` 报告 `es8388` 的 source/sink 不存在。
- `alsactl restore` 失败。
- 实际 `aplay -l` 仅看到 DP 和 HDMI 声卡，未见板载采集设备。

**影响**

如果后续业务涉及板载喇叭、功放、麦克风或语音链路，则可能构成功能阻塞；如果机器人基座阶段暂不依赖音频，则不是当前最优先阻塞项。

**归因**

编译侧

**建议动作**

- 回编译侧核查音频 DTS、codec、功放和用户态默认音频配置。
- 至少应消除错误探测与错误默认配置，避免误导运行时判断。

### 5. 严重级别：低

**现象**

系统存在一批桌面、显示和多媒体层噪声，但大多不构成机器人基座主链路阻塞。

**证据**

- 本次启动 `systemctl --failed` 为空。
- 启动日志中存在大量 HDMI DDC 读超时与 `failed to get edid`。
- `xfce4-panel.xml` 解析错误。
- `pulseaudio` 存在旧模块提示。
- `udisksd` 缺少 `crypto` 和 `mdraid` 插件。

**影响**

这些问题更偏向桌面体验、热插拔存储或多媒体体验噪声。对于无头机器人基座、SSH 运维与后续业务服务部署影响有限。

**归因**

运行时 / 待确认

**建议动作**

- 如果目标定位是无头机器人基座，可暂时降级处理。
- 如果仍需保留桌面体验，再单独清理桌面镜像与多媒体默认配置。

## Open Questions

1. 目标机设计上是否要求板载 Wi-Fi 和蓝牙必须可用？当前可用无线来自外置 USB 设备，不能直接代表板载链路已通过。
2. 目标机设计上是否要求 RTC、板载音频、触摸和摄像头属于基座默认能力？当前未见 RTC、触摸和摄像头的明确可用证据。
3. 当前业务是否要求进入特定 systemd target 后自动切换到 `rt-high-performance`？现有证据说明切换链路存在，但未被成功验证。

## Final Verdict

### 结论

暂不能停止编译侧迭代。

### 理由

- 当前镜像已经具备进入运行时部署的多个前提条件：RT 内核、基础系统、NetworkManager、SSH、以及 OPiBot 运行时服务框架都已存在。
- 业务软件尚未部署所导致的部分服务未启用，属于正常空缺，不构成镜像问题本身。
- 但实时化运行时链路当前在目标机上存在明确缺陷：脚本与 `mawk` 不兼容、验证脚本权限错误、模式状态与实际 CPU/电源管理状态不一致。这属于镜像交付问题，且直接影响机器人基座最关键的 RT 可用性，因此仍是阻塞项。
- 此外，板载无线、RTC、板载音频等板级能力仍存在未闭环项，其中哪些必须回编译侧，还取决于该机型的硬件目标定义；但在 RT 主链路未修复前，不宜宣布编译侧冻结。

### 下一步

1. 回编译侧修复 RT 运行时脚本兼容性和验证脚本权限，并重新冷启动复核 RT 落地结果。
2. 明确目标机 BOM 与基座能力边界，确认板载无线、RTC、音频、触摸、摄像头哪些必须在镜像层闭环。
3. 若目标定位为无头机器人基座，可在 RT 链路修复后优先转入业务软件部署与服务绑定阶段，桌面与多媒体噪声可后置处理。

## 附：本次诊断的关键事实摘要

- 内核：`6.1.99-rt36-rockchip-rk3588-rt`
- 系统：Orange Pi Jammy / Ubuntu 22.04.5 LTS
- 运行时长：约 12 分钟时开始检查
- 启动参数已包含 RT 相关 CPU 隔离与 IRQ 参数
- `irqbalance` 当前不活跃
- `opibot-runtime-mode.service` 与 `opibot-irq-layout.service` 已启用
- 当前性能状态文件：`low-power`
- 当前远程运维能力：可用，SSH 正常，NetworkManager 正常
- 当前可用 Wi-Fi：外置 USB Realtek 网卡
- failed units：未发现
