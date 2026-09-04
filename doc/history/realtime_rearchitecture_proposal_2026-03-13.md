# 实时化配置重建方案

日期：2026-03-13

目标：提出一套推翻当前局部修补式 RT 配置、面向单层 SBC 直控机器人系统的新实时化架构方案。该方案需要同时覆盖以下场景：

1. 无额外底层 MCU 的单层硬件架构，SBC 直接输出伺服控制信号，对实时性要求极高。
2. 常见机器人感知-决策-控制任务的实机部署，包括视觉、VIO、规划、控制、总线通信、ROS2 中间件。
3. 在高实时性、高性能和动态功耗管理之间进行协调优化，在待机和非实时工作阶段降低功耗与发热。
4. 具备一定通用性，不绑定某一个单独应用，但允许通过配置收敛到具体项目。

本文档是新的架构方案，不是对当前 runtime-rt-tune、isolcpus、IRQ 绑核脚本的局部修补说明。

## 1. 设计结论

结论先行：

建议采用分层实时化架构，而不是继续沿用“2 个 RT 核 + 其余全是非 RT 核 + 若干 IRQ/NIC 全绑到 RT 核”的当前设计。

新的总体原则是：

1. 启动期只定义静态隔离边界，不在启动参数中写入过多业务假设。
2. 运行期通过服务编排、CPU 域划分、IRQ 域划分、内存带宽与设备访问控制来建立确定性。
3. 控制类硬实时任务与感知类高吞吐软实时任务必须分域，而不是一起放进“高性能模式”。
4. 待机降功耗不应通过削弱控制域确定性来实现，而应通过“运行状态感知 + 模式切换”完成。

因此，新方案的核心不是“把更多任务放到 RT 核上”，而是：

1. 把最关键控制路径做得更纯。
2. 把感知与高算力任务做成稳定的非 RT 高性能域。
3. 把系统噪声、网络堆栈和后台服务收容到系统域。
4. 用明确的系统状态机来决定什么时候进入高实时模式，什么时候退回低功耗模式。

## 2. 现有方案的问题

当前体系的主要问题不是“没有 RT 优化”，而是“RT 优化粒度不对，职责边界不清”。

现有方案的主要特征：

1. 通过启动参数固定 `nohz_full=6,7`、`rcu_nocbs=6,7`、`isolcpus=managed,domain,6,7`、`irqaffinity=0-5`。
2. 运行期脚本把 CPU 6,7 当作 RT 核，把 CPU 0-5 当作背景核。
3. 运行期脚本会停用 irqbalance、关闭 RT 核 cpuidle、将 RT 核切到 performance。
4. 运行期脚本还会把 `eth|can|tty` 相关 IRQ 绑定到 RT 核，并把 NIC 队列亲和也指向 RT 核。

这套方案的问题在于：

1. 它只有二分法，没有三分法。
   系统中实际上至少有三类任务：控制硬实时、感知软实时、系统噪声任务。当前方案只分 RT 和非 RT，不足以表达机器人系统的真实结构。

2. 它把“关键控制任务”和“大流量 IRQ/NIC 数据路径”混进了同一域。
   这对真正的高确定性控制是不利的，尤其是相机、激光雷达、以太网传感器、DDS 大流量回调存在时。

3. 它默认假设 RT 核也承载关键网络与串口中断。
   这对极少量关键总线可能有意义，但对 PX4 on SBC、FASTVIO、视觉惯导、激光雷达融合等组合工作负载，不是稳健的默认方案。

4. 它没有把“系统状态”建模出来。
   没有明确区分待机、预热、感知运行、控制闭环、飞控关键阶段、离线处理阶段，导致高性能模式过于常驻。

## 3. 新方案的适用目标

### 3.1 单层 SBC 直控伺服/执行器

本方案假设最极端场景之一是：

1. 没有额外 MCU 作为底层硬实时执行器。
2. SBC 直接承担控制回路、总线收发、PWM/串口/CAN 输出或等价控制输出。
3. 该路径必须尽可能降低调度抖动和不可预期阻塞。

这种场景比“普通机器人 ROS2 主控机”更严格，因此方案会优先围绕它设计，再向下兼容普通机器人部署。

### 3.2 机器人感知-决策-控制共存

方案同时适配以下常见组合：

1. 相机 + IMU + FASTVIO/VIO。
2. 激光雷达 + 里程计 + 局部规划。
3. ROS2 executor + DDS 通信 + 参数服务。
4. PX4 / 控制器 / 状态估计 / 执行机构输出。
5. 桌面调试、可视化、日志记录、录包等非实时负载。

### 3.3 动态功耗管理

方案要求支持：

1. 控制链活动时自动进入高实时高性能模式。
2. 纯感知但无控制闭环时进入受控高性能模式。
3. 空闲或待机时退到低功耗模式。

这里的关键不是单纯“降频”，而是保证：

1. 低功耗模式不会破坏下一次进入控制模式时的确定性。
2. 运行时模式切换不会动用不该热切换的启动级隔离参数。

## 4. 新架构总览

### 4.1 三域 CPU 架构

建议采用三域而不是二域。

对于 RK3588S 这类 8 核 big.LITTLE SoC，建议默认划分为：

1. 系统域：CPU 0-3
2. 感知计算域：CPU 4-5
3. 控制实时域：CPU 6-7

这不是绝对写死，但它是通用性最好的默认模板。

理由：

1. CPU 0-3 通常更适合吸纳系统后台、日志、桌面噪声、普通服务。
2. CPU 4-5 适合作为高算力感知域，承接 VIO、SLAM 前端、视觉前端、点云预处理、规划、推理前后处理。
3. CPU 6-7 作为控制实时域，为飞控、控制回路、关键执行机构和关键低带宽中断预留。

### 4.2 四层职责模型

建议从软件职责上再分四层：

1. 启动隔离层
   定义 boot profile，只负责静态 CPU 边界和基础调度前提。

2. 运行时模式层
   根据系统状态决定当前是 standby、perception-active、control-active 哪一种模式。

3. 服务编排层
   通过 systemd target 和 service 编排，让 ROS2/PX4/驱动服务在正确域内启动。

4. 任务域绑定层
   用 CPUAffinity、cpuset、IRQ affinity、NIC queue affinity、内存锁定策略把线程和设备路径放进各自域。

## 5. 新的启动级设计

### 5.1 Boot Profile 只做静态隔离，不做业务混绑

启动参数建议只区分两种 boot profile：

1. rt-control
2. balanced

其中：

1. rt-control 用于需要 SBC 直接承担控制闭环的部署。
2. balanced 用于没有极端控制硬实时要求、但仍需较好吞吐和较低功耗的部署。

建议：

1. 正式控制型产品默认使用 rt-control。
2. 调试机、纯感知机、桌面开发镜像可使用 balanced。

### 5.2 rt-control 启动参数建议

建议保留隔离思想，但不要再让启动参数表达过多业务约束。

建议项：

1. `nohz_full=6,7`
2. `rcu_nocbs=6,7`
3. `isolcpus=managed,domain,6,7`

不建议在启动参数层面继续写死复杂 IRQ 业务策略。IRQ 的具体去向应转移到运行期配置。

### 5.3 balanced 启动参数建议

balanced 模式建议不启用 RT 核隔离，只保留必要的通用启动参数，例如 CMA 等与多媒体或驱动有关的项。

这样待机、桌面调试、离线算法验证不会背着整套 RT 隔离副作用运行。

## 6. 新的运行时模式设计

### 6.1 模式定义

建议运行期定义三个模式：

1. standby
2. perception-active
3. control-active

#### standby

场景：

1. 系统启动完成但未进入控制任务。
2. ROS2 栈空闲或仅保活。
3. 设备连接待机。

行为：

1. 全核允许 cpuidle。
2. governor 使用 schedutil。
3. 大小核频率上限降低。
4. irqbalance 可启用，但关键设备可保留白名单。
5. NIC 恢复普通路径，不启用 RT 特化队列与 qdisc。

#### perception-active

场景：

1. 相机、IMU、激光雷达、FASTVIO、建图、规划在运行。
2. 尚未进入极端严格控制闭环，或控制已降级为非关键模式。

行为：

1. 感知域 CPU 4-5 提升到 performance 或 util-clamp 高性能策略。
2. 控制域 CPU 6-7 保持空闲或待命，不承接大流量传感器 IRQ。
3. NIC、串口、大流量设备 IRQ 进入感知域或系统域。
4. 可允许 GPU/NPU/devfreq 升频，但不污染控制域。

#### control-active

场景：

1. PX4 on SBC 进入主控制状态。
2. 伺服输出、姿态闭环、速度闭环、状态估计关键路径处于活动状态。
3. 必须保证关键线程调度抖动最小。

行为：

1. 控制域 CPU 6-7 进入高实时高性能模式。
2. 控制线程、关键执行器线程、关键总线线程进入控制域。
3. RT 核 cpuidle 可选择关闭，或者仅关闭最深层 idle state。
4. irqbalance 不再全局接管，关键 IRQ 白名单进入控制域，其余 IRQ 仍留在感知域或系统域。
5. 感知域保持高性能，但其负载不得侵入控制域。

### 6.2 模式切换原则

模式切换必须遵循：

1. 热切换只修改运行时项。
2. 启动隔离项只能通过配置文件和重启切换。
3. 进入 control-active 应早于控制服务启动。
4. 退出 control-active 应晚于控制服务完全停止。

## 7. IRQ 与设备路径重构原则

### 7.1 不再默认把所有 eth/can/tty IRQ 丢给 RT 域

新的默认原则：

1. 只有真正属于控制关键路径的 IRQ 才进入控制域。
2. 大流量感知数据链路的 IRQ 不进入控制域。
3. 系统后台设备 IRQ 尽量收容到系统域。

### 7.2 推荐 IRQ 分类

建议按设备类型分为三类：

1. 控制关键 IRQ
   例如关键执行器总线、关键 IMU 时间同步、极少量必须跟控制环强耦合的中断。

2. 感知吞吐 IRQ
   例如相机网口、激光雷达网口、USB3 视觉链路、感知串口桥接。

3. 系统噪声 IRQ
   例如桌面外设、调试接口、普通网络服务。

### 7.3 NIC 队列亲和重构

建议取消“默认把 RPS/XPS 全指向控制域”的策略。

推荐做法：

1. 控制链路专用 NIC 或专用队列才可绑定到控制域。
2. 传感器大流量 NIC 队列绑定到感知域。
3. 普通网络通信走系统域或感知域。

如果只有单网口，则必须由业务流量分类决定队列与 IRQ 去向，而不是全局默认进 RT 域。

## 8. 线程与服务编排建议

### 8.1 systemd target 模型

建议引入以下 target：

1. opibot-standby.target
2. opibot-perception.target
3. opibot-control.target

关系建议：

1. standby 是基础运行态。
2. perception 在 standby 之上启动感知与规划服务。
3. control 在 perception 之上或并列启动控制与执行器服务。

### 8.2 ROS2/PX4 服务分组

建议将服务分成 4 组：

1. 控制关键组
   例如 PX4 主循环、姿态控制、执行器接口、关键状态估计。

2. 感知高算力组
   例如 FASTVIO、视觉前端、雷达前端、地图局部处理、推理链。

3. 决策与规划组
   例如行为树、任务调度、局部/全局规划。

4. 支撑服务组
   例如 ros2 daemon、日志、录包、可视化桥接、监控。

### 8.3 CPUAffinity 建议

推荐默认绑定：

1. 控制关键组：CPU 6-7
2. 感知高算力组：CPU 4-5
3. 决策与规划组：CPU 4-5 或 0-5，取决于负载
4. 支撑服务组：CPU 0-3

如果控制任务极端关键，可进一步细化：

1. CPU 6 用于主控制环
2. CPU 7 用于关键通信与辅助实时线程

## 9. 对 PX4 on SBC 的特别建议

如果 SBC 直接承担 PX4 类飞控控制任务，应按“控制域优先于感知域”的原则设计。

建议：

1. 不把高吞吐视觉前端和主控制环放进同一 CPU 域。
2. 控制关键服务必须先于其他高负载感知任务获得 CPU 与 IRQ 资源。
3. 对关键控制线程启用 `SCHED_FIFO` 或等价 RT 策略，但必须限于明确受控的线程集合。
4. 对关键服务启用 `mlockall`、realtime group 和受控的 RT 优先级。
5. 保留 RT throttle 保护，不建议一开始就把 `kernel.sched_rt_runtime_us` 放宽到无限制。

在无 MCU 单层架构里，最大风险不是 RT 内核不够“实时”，而是错误的资源混绑导致控制链被感知链、驱动链或网络链污染。

## 10. 对 FASTVIO 等感知算法的判断

FASTVIO、VIO、SLAM、视觉前端、点云前端通常属于软实时高吞吐任务。

判断原则：

1. 它们需要稳定且连续的吞吐，不必默认进入 RT 控制域。
2. 它们最怕的是和系统噪声、DDS、日志、磁盘 IO、桌面进程混跑。
3. 它们也不适合默认侵占控制域。

因此推荐：

1. FASTVIO 默认放在感知域。
2. 保证其数据来源 IRQ、DMA 路径、用户线程尽量也留在感知域。
3. 若存在极少量时间同步关键线程，可单独提取并靠近控制域，而不是整个算法进入控制域。

## 11. 动态功耗管理策略

### 11.1 总原则

动态功耗管理必须是“状态驱动”的，而不是“简单降频”。

建议状态机如下：

1. standby -> perception-active -> control-active
2. control-active 退出后，不立即退到 standby，而是先退到 perception-active 或带宽限流状态
3. 设置合理滞回时间，避免频繁抖动切换

### 11.2 standby 模式策略

建议：

1. governor=schedutil
2. 限制大核上限频率
3. 限制小核上限频率
4. 允许 cpuidle
5. 开启 irqbalance 或最小人工亲和
6. 禁用 RT 特化的 qdisc、ETF、CBS、RPS/XPS 绑核

### 11.3 control-active 模式策略

建议：

1. 控制域 governor=performance
2. 感知域按需求可保持 performance 或 schedutil + util clamp
3. 只关闭控制域必要的 cpuidle 深层状态
4. 关键 IRQ 白名单进入控制域
5. 其他 IRQ 不进入控制域

### 11.4 温度与降额保护

建议：

1. 控制域不做粗暴降频，但必须有热保护策略。
2. 感知域优先降频或限并行度。
3. 若温度持续超过阈值，优先降级非关键感知任务，而不是先破坏控制域确定性。

## 12. 内核与系统建议

### 12.1 内核建议

建议保留 PREEMPT_RT 作为控制型产品默认内核。

原因：

1. 对无 MCU 的单层控制架构更有意义。
2. 可以降低关键锁竞争和内核抢占抖动。
3. 便于对关键控制线程做更强优先级保证。

但需要注意：

1. PREEMPT_RT 不是吞吐优化器。
2. 感知高算力任务不会因为 RT 内核自动变快。
3. 感知任务的稳定性主要取决于域划分和 IRQ/CPU 绑定，而不是 RT patch 本身。

### 12.2 系统服务建议

建议：

1. 所有关键服务都走 systemd，不靠登录 shell 启动。
2. 使用 target 组织生命周期。
3. 每个关键服务必须声明 CPUAffinity、IOScheduling、MemoryLock、Nice/RTPriority 策略。
4. 非关键服务默认留在系统域。

## 13. 推荐实施路线

建议分四阶段实施。

### 阶段 A：定义新模型，不动业务

1. 新建 boot profile 配置文件。
2. 新建三域模式配置。
3. 新建 systemd target 结构。
4. 先不改 ROS2/PX4 业务逻辑。

### 阶段 B：重构运行时切换框架

1. 重写模式切换脚本。
2. 去除“全网卡/全串口 IRQ 进入 RT 域”的默认行为。
3. 引入 standby/perception/control 三态。

### 阶段 C：服务分域

1. 将控制关键服务绑定控制域。
2. 将 FASTVIO、感知前端、SLAM 等绑定感知域。
3. 将日志、录包、可视化、桌面进程绑定系统域。

### 阶段 D：热管理与回归验证

1. 建立温度、频率、调度抖动、端到端控制延迟测试。
2. 验证待机功耗与控制模式稳定性。
3. 按实测结果调节 low-power 频率上限、感知域并行度和关键 IRQ 白名单。

## 14. 验证指标

建议至少验证以下指标：

1. 控制环周期抖动
2. 控制输出端到端延迟
3. 关键传感器时间同步偏差
4. FASTVIO 或等价感知算法帧间抖动
5. ROS2 executor 延迟分布
6. 待机温度、待机功耗
7. control-active 模式下 10 分钟、30 分钟、1 小时热稳定性

## 15. 方案优点

1. 比现有二分法更贴近真实机器人负载结构。
2. 更适合无 MCU 的单层 SBC 直控场景。
3. 可以同时兼顾 PX4 on SBC 和 ROS2 感知计算任务。
4. 功耗管理从“降频脚本”提升为“系统状态机”。
5. 对不同机器人应用具有较强通用性。
6. 便于后续做按服务分域、按设备分 IRQ、按模式切换的精细优化。

## 16. 方案缺点与代价

1. 实现复杂度显著高于当前脚本式方案。
2. 需要明确区分控制、感知、决策、支撑服务的职责边界。
3. 对 systemd 服务化、ROS2 启动方式、部署流程有更高要求。
4. 需要做比现在更多的实机测试和回归验证。
5. 如果业务程序本身线程模型混乱，仅靠系统配置无法完全解决实时性问题。

## 17. 是否建议实施

建议实施，但不建议一次性大爆炸替换。

建议结论：

1. 对于“单层 SBC 直接控制执行器”这一目标，当前体系不足以作为长期稳定架构。
2. 对于“机器人感知-决策-控制共存”这一目标，现有方案仍有明显的域污染风险。
3. 因此建议实施新方案，但必须按阶段演进，而不是直接在现有脚本上继续堆补丁。

推荐决策：

1. 立即采纳本文档作为新的目标架构。
2. 先实施阶段 A 和阶段 B，建立新的模式与分域框架。
3. 在确认 ROS2/PX4 服务边界后，再进入阶段 C 的服务分域。
4. 最后通过阶段 D 的实机验证决定是否完全替换现有 runtime-rt-tune 方案。

## 18. 实施设计稿

本节把上文的目标架构细化为可实施设计，重点回答以下问题：

1. 配置文件如何组织。
2. systemd 服务和 target 应该叫什么。
3. 运行时脚本应该暴露什么接口。
4. 如何从当前 userpatches 体系平滑迁移。

### 18.1 配置模型

建议把配置拆成四类，而不是继续把所有实时化参数塞进单个脚本。

#### A. Boot Profile 配置

用途：

1. 只描述重启后生效的静态隔离边界。
2. 由镜像构建阶段写入启动配置文件。

建议文件：

1. `/etc/default/opibot-boot-profile`

建议键：

1. `BOOT_PROFILE=rt-control|balanced`
2. `CONTROL_CPUS=6,7`
3. `PERCEPTION_CPUS=4,5`
4. `SYSTEM_CPUS=0-3`
5. `BOOT_RT_CMDLINE=<自动生成，不手工编辑>`

说明：

1. 这个文件是“静态配置源”，真正的 `/boot/orangepiEnv.txt` 由构建脚本或同步脚本根据它生成。
2. 正常运行过程中不应再通过 CLI 去修改启动参数。

#### B. Runtime Mode 配置

用途：

1. 描述待机、感知活动、控制活动三态下的热切换参数。

建议文件：

1. `/etc/default/opibot-runtime-mode`

建议键：

1. `DEFAULT_RUNTIME_MODE=standby`
2. `ROS2_ACTIVE_MODE=perception-active`
3. `CONTROL_ACTIVE_MODE=control-active`
4. `IDLE_RETURN_MODE=standby`
5. `IDLE_GRACE_SECONDS=120`
6. `LOW_POWER_BIG_MAX_FREQ_KHZ=1800000`
7. `LOW_POWER_LITTLE_MAX_FREQ_KHZ=1200000`
8. `PERCEPTION_BIG_MAX_FREQ_KHZ=2200000`
9. `CONTROL_BIG_MAX_FREQ_KHZ=<默认最大>`
10. `ENABLE_IDLE_AUTOSWITCH=yes`

#### C. IRQ 与设备域配置

用途：

1. 明确关键 IRQ、感知 IRQ、系统 IRQ 的划分，不允许继续写死在脚本逻辑里。

建议文件：

1. `/etc/default/opibot-irq-layout`

建议键：

1. `CONTROL_IRQ_PATTERNS="can fdcan pwm imu_sync"`
2. `PERCEPTION_IRQ_PATTERNS="eth lidar camera usb3 vision"`
3. `SYSTEM_IRQ_PATTERNS="xhci bluetooth wifi display"`
4. `CONTROL_IRQ_CPUS=6,7`
5. `PERCEPTION_IRQ_CPUS=4,5`
6. `SYSTEM_IRQ_CPUS=0-3`
7. `NIC_CONTROL_DEVICES=""`
8. `NIC_PERCEPTION_DEVICES="eth0"`

#### D. Service Domain 配置

用途：

1. 指定关键服务属于控制域、感知域、规划域还是系统域。

建议文件：

1. `/etc/default/opibot-service-layout`

建议键：

1. `CONTROL_SERVICES="px4.service actuator-bridge.service control-loop.service"`
2. `PERCEPTION_SERVICES="fastvio.service camera-front.service lidar-front.service"`
3. `PLANNING_SERVICES="planner.service behavior-tree.service"`
4. `SUPPORT_SERVICES="ros2-daemon.service rosbag.service telemetry.service"`

### 18.2 systemd 目标与服务命名

建议采用如下命名，不再沿用当前临时性的 `opibot-ros2.target` 作为唯一业务入口。

#### 基础模式服务

1. `opibot-runtime-mode.service`
   开机按配置应用默认运行时模式。

2. `opibot-runtime-autoswitch.service`
   常驻监视器，负责待机/感知/控制三态切换。

3. `opibot-irq-layout.service`
   根据 IRQ 分类配置在启动后设置亲和性。

4. `opibot-boot-profile-sync.service`
   构建期或维护期使用，用于把 boot profile 同步到 `/boot/orangepiEnv.txt`。

#### target 结构

1. `opibot-base.target`
   所有机器人系统公共基础目标。

2. `opibot-perception.target`
   感知、状态估计、建图、规划前端进入的目标。

3. `opibot-control.target`
   控制关键服务进入的目标。该 target 激活前必须先把系统切到 control-active。

4. `opibot-mission.target`
   完整任务目标，可同时拉起 perception 与 control 所需服务。

#### 预热服务

1. `opibot-perception-prepare.service`
   在 `opibot-perception.target` 之前切到 `perception-active`。

2. `opibot-control-prepare.service`
   在 `opibot-control.target` 之前切到 `control-active`。

推荐依赖关系：

1. `opibot-perception.target` Wants `opibot-perception-prepare.service`
2. `opibot-control.target` Wants `opibot-control-prepare.service`
3. `opibot-control-prepare.service` Before `opibot-control.target`
4. `opibot-perception.target` 可作为 `opibot-control.target` 的前置，也可按项目解耦

### 18.3 运行时脚本接口

建议把脚本职责从“修改所有东西”收敛成“应用运行时域策略”。

建议脚本：

1. `/usr/local/sbin/opibot-runtime-mode`
2. `/usr/local/sbin/opibot-irq-layout`
3. `/usr/local/sbin/opibot-boot-profile-sync`

#### `opibot-runtime-mode` 建议接口

只允许操作热切换项：

1. `opibot-runtime-mode apply standby`
2. `opibot-runtime-mode apply perception-active`
3. `opibot-runtime-mode apply control-active`
4. `opibot-runtime-mode apply-config`
5. `opibot-runtime-mode watch`
6. `opibot-runtime-mode status`

明确禁止：

1. 通过该脚本直接修改启动参数。
2. 通过该脚本直接写入 `/boot/orangepiEnv.txt`。

#### `opibot-irq-layout` 建议接口

1. `opibot-irq-layout apply`
2. `opibot-irq-layout apply control-active`
3. `opibot-irq-layout apply perception-active`
4. `opibot-irq-layout status`

#### `opibot-boot-profile-sync` 建议接口

1. `opibot-boot-profile-sync render`
2. `opibot-boot-profile-sync apply`
3. `opibot-boot-profile-sync diff`

注意：

1. 这个脚本可以在维护期手工执行。
2. 但正常运行过程中不作为动态切换入口。

### 18.4 目录布局建议

建议新的 overlay 目录组织如下：

1. `userpatches/overlay/etc/default/opibot-boot-profile`
2. `userpatches/overlay/etc/default/opibot-runtime-mode`
3. `userpatches/overlay/etc/default/opibot-irq-layout`
4. `userpatches/overlay/etc/default/opibot-service-layout`
5. `userpatches/overlay/etc/systemd/system/opibot-base.target`
6. `userpatches/overlay/etc/systemd/system/opibot-perception.target`
7. `userpatches/overlay/etc/systemd/system/opibot-control.target`
8. `userpatches/overlay/etc/systemd/system/opibot-mission.target`
9. `userpatches/overlay/etc/systemd/system/opibot-runtime-mode.service`
10. `userpatches/overlay/etc/systemd/system/opibot-runtime-autoswitch.service`
11. `userpatches/overlay/etc/systemd/system/opibot-perception-prepare.service`
12. `userpatches/overlay/etc/systemd/system/opibot-control-prepare.service`
13. `userpatches/overlay/etc/systemd/system/opibot-irq-layout.service`
14. `userpatches/overlay/usr/local/sbin/opibot-runtime-mode`
15. `userpatches/overlay/usr/local/sbin/opibot-irq-layout`
16. `userpatches/overlay/usr/local/sbin/opibot-boot-profile-sync`

### 18.5 对当前实现的映射与替换关系

当前已经有的文件可以视为过渡版本，而不是最终形态。

当前文件到目标文件的映射建议：

1. 当前的 `runtime-rt-tune`
   目标：拆成 `opibot-runtime-mode` 与 `opibot-irq-layout` 两部分。

2. 当前的 `opibot-performance-mode`
   目标：更名为 `opibot-runtime-mode`，职责收缩为纯运行时模式切换。

3. 当前的 `opibot-performance-mode.service`
   目标：更名为 `opibot-runtime-mode.service`。

4. 当前的 `opibot-performance-autoswitch.service`
   目标：更名为 `opibot-runtime-autoswitch.service`。

5. 当前的 `opibot-ros2-high-performance.service`
   目标：拆分为 `opibot-perception-prepare.service` 和 `opibot-control-prepare.service`。

6. 当前的 `opibot-ros2.target`
   目标：被 `opibot-perception.target`、`opibot-control.target`、`opibot-mission.target` 替代。

### 18.6 迁移步骤

#### 步骤 1：配置拆分

1. 将现有 `opibot-performance-mode` 配置拆成 boot profile、runtime mode、irq layout、service layout 四个配置文件。
2. 现有 `/boot/orangepiEnv.txt` 的写入逻辑迁移到 `opibot-boot-profile-sync`。

#### 步骤 2：重命名服务与脚本

1. 将所有 `performance-mode` 命名迁移到 `runtime-mode`。
2. 保留兼容别名一段时间，但新文档和新服务名统一使用新名称。

#### 步骤 3：建立 target 层次

1. 新建 `opibot-base.target`
2. 新建 `opibot-perception.target`
3. 新建 `opibot-control.target`
4. 新建 `opibot-mission.target`

#### 步骤 4：迁移业务服务

1. 把 PX4、控制桥接、执行器服务挂到 `opibot-control.target`
2. 把 FASTVIO、相机、雷达、状态估计前端挂到 `opibot-perception.target`
3. 把规划和行为树按业务强度挂到 perception 或 mission
4. 把日志、可视化、录包保持在 base 或系统域

#### 步骤 5：迁移 IRQ 策略

1. 先取消当前“全部 `eth|can|tty` 进入 RT 域”的默认行为。
2. 再按设备名单逐项恢复真正需要进入控制域的 IRQ。

#### 步骤 6：验证后再删除旧实现

1. 保留旧 `runtime-rt-tune` 作为 fallback 一段时间。
2. 等 control-active、perception-active 和 standby 三态验证通过后，再删除旧服务。

### 18.7 建议的首批实施范围

为了控制风险，首批建议只实现以下子集：

1. 配置文件拆分。
2. `opibot-runtime-mode` 更名与职责收缩。
3. `opibot-perception.target`、`opibot-control.target`、`opibot-mission.target`。
4. `opibot-control-prepare.service`。
5. 取消默认把全部网口与串口 IRQ 打进控制域。

首批不建议立即做的项：

1. 复杂的设备自动识别。
2. 基于应用层主题或 ROS graph 的自动模式推断。
3. 温度闭环自动降级策略。
4. 过于激进的 RT runtime 放宽。

### 18.8 验收门槛

要判断第一阶段是否成功，建议以以下门槛为准：

1. `rt-control` boot profile 下，控制服务启动前必定已经进入 `control-active`。
2. standby 模式待机温度和功耗明显低于 control-active。
3. FASTVIO 在 perception 域运行时，不再显著挤占控制域 CPU。
4. 控制闭环抖动在迁移后不高于当前方案，且长期热稳定性更好。
5. 任意模式切换失败时，系统仍能回退到可控状态，不因错误脚本导致控制链失效。

## 19. 实施建议结论

如果要从文档直接进入工程实施，建议下一步不是立刻全面改代码，而是先按以下顺序做：

1. 在文档层面冻结命名：统一采用 `boot-profile`、`runtime-mode`、`irq-layout`、`service-layout` 这一套术语。
2. 在代码层面完成第一阶段：重命名与配置拆分。
3. 在 systemd 层面完成 target 拆分。
4. 在业务层面只迁移最关键的一组控制服务和一组感知服务进行实机验证。

这是最保守、也最有工程成功率的路径。