# 实时化重构实施清单

日期：2026-03-13

对应设计文档：

1. [realtime_rearchitecture_proposal_2026-03-13.md](realtime_rearchitecture_proposal_2026-03-13.md)

目标：

1. 将实时化重构方案拆解为可执行 checklist。
2. 明确每个阶段需要新增、修改、替换、验证和保留回滚路径的内容。
3. 用于指导后续代码实施，而不是继续在旧体系上无序叠加修补。

## 1. 总实施策略

采用四阶段落地：

1. 阶段 A：配置与命名冻结
2. 阶段 B：运行时模式框架重构
3. 阶段 C：业务服务分域
4. 阶段 D：验证、收敛与退役旧实现

实施原则：

1. 每个阶段都必须可回滚。
2. 每个阶段都必须先完成结构重构，再进入业务迁移。
3. 不在同一阶段同时大改脚本、service 和业务服务。
4. 旧 `runtime-rt-tune` 在阶段 D 前保留为回退路径。

## 2. 阶段 A：配置与命名冻结

### 2.1 目标

1. 固化新术语和新目录结构。
2. 将“启动级配置”和“运行时配置”分离。
3. 为后续 systemd target 和脚本重构建立稳定接口。

### 2.2 要完成的文件

建议新增：

1. `userpatches/overlay/etc/default/opibot-boot-profile`
2. `userpatches/overlay/etc/default/opibot-runtime-mode`
3. `userpatches/overlay/etc/default/opibot-irq-layout`
4. `userpatches/overlay/etc/default/opibot-service-layout`

建议保留但标记为过渡：

1. `userpatches/overlay/etc/default/opibot-performance-mode`

建议修改：

1. `.gitignore`
2. `userpatches/customize-image.sh`

### 2.3 阶段 A 任务清单

1. 新建 `opibot-boot-profile`，只保存 boot profile 和 CPU 域定义。
2. 新建 `opibot-runtime-mode`，只保存 standby/perception/control 三态参数。
3. 新建 `opibot-irq-layout`，只保存 IRQ 分类和 CPU 域映射。
4. 新建 `opibot-service-layout`，只保存服务分组和域映射。
5. 在 `customize-image.sh` 中引入新配置文件权限修复逻辑。
6. 在 `.gitignore` 中放行上述 4 个新配置文件。
7. 将现有 `opibot-performance-mode` 标记为过渡文件，避免继续扩展它。

### 2.4 阶段 A 验收

1. 新配置文件全部进入版本控制视野。
2. `customize-image.sh` 语法检查通过。
3. 文档中的术语与文件命名一致。
4. 当前系统行为不因阶段 A 改动发生变化。

### 2.5 阶段 A 回滚点

1. 删除新配置文件。
2. 恢复 `.gitignore` 与 `customize-image.sh` 到阶段 A 之前版本。

## 3. 阶段 B：运行时模式框架重构

### 3.1 目标

1. 把当前 `performance-mode` 脚本收敛为新的运行时模式框架。
2. 建立 standby、perception-active、control-active 三态。
3. 去掉通过 CLI 修改启动参数的能力。

### 3.2 要新增或替换的文件

建议新增：

1. `userpatches/overlay/usr/local/sbin/opibot-runtime-mode`
2. `userpatches/overlay/usr/local/sbin/opibot-irq-layout`
3. `userpatches/overlay/usr/local/sbin/opibot-boot-profile-sync`

建议新增的 service：

1. `userpatches/overlay/etc/systemd/system/opibot-runtime-mode.service`
2. `userpatches/overlay/etc/systemd/system/opibot-runtime-autoswitch.service`
3. `userpatches/overlay/etc/systemd/system/opibot-irq-layout.service`
4. `userpatches/overlay/etc/systemd/system/opibot-boot-profile-sync.service`

建议保留为 fallback：

1. `userpatches/overlay/usr/local/sbin/runtime-rt-tune`
2. `userpatches/overlay/etc/systemd/system/runtime-rt-tune.service`

建议替换的旧实现：

1. `opibot-performance-mode`
2. `opibot-performance-mode.service`
3. `opibot-performance-autoswitch.service`

### 3.3 阶段 B 任务清单

1. 新建 `opibot-runtime-mode`，仅支持运行时模式切换。
2. 从 `opibot-runtime-mode` 中移除任何直接修改 `/boot/orangepiEnv.txt` 的逻辑。
3. 新建 `opibot-boot-profile-sync`，专门负责 boot profile 渲染与同步。
4. 新建 `opibot-irq-layout`，专门负责 IRQ/NIC 队列/亲和策略下发。
5. 把当前 standby/low-power 的逻辑迁移到 `standby` 模式。
6. 把当前 rt-high-performance 的逻辑拆成 `perception-active` 与 `control-active` 两层。
7. 明确 `control-active` 只处理控制域强化，不默认吞下全部网口与串口中断。
8. 新建 `opibot-runtime-mode.service`，开机按配置应用默认运行时模式。
9. 新建 `opibot-runtime-autoswitch.service`，负责三态切换监控。
10. 新建 `opibot-irq-layout.service`，在运行模式变化后可再次下发 IRQ 布局。
11. 保留 `runtime-rt-tune` 作为 fallback，不立即删除。

### 3.4 阶段 B 验收

1. `opibot-runtime-mode`、`opibot-irq-layout`、`opibot-boot-profile-sync` 语法检查通过。
2. 三态切换命令可用：`standby`、`perception-active`、`control-active`。
3. 没有任何 CLI 接口再直接写启动参数。
4. fallback 路径仍保留可手工启用。
5. 旧 `performance-mode` 路径不再是默认入口。

### 3.5 阶段 B 回滚点

1. 停用 `opibot-runtime-mode.service` 和 `opibot-runtime-autoswitch.service`。
2. 重新启用 `runtime-rt-tune.service` 作为默认运行时入口。

## 4. 阶段 C：systemd target 与业务分域

### 4.1 目标

1. 建立新的 target 层次。
2. 把控制、感知、规划、支撑服务分域。
3. 使模式切换与业务服务生命周期绑定。

### 4.2 要新增的 target 与 prepare service

建议新增：

1. `userpatches/overlay/etc/systemd/system/opibot-base.target`
2. `userpatches/overlay/etc/systemd/system/opibot-perception.target`
3. `userpatches/overlay/etc/systemd/system/opibot-control.target`
4. `userpatches/overlay/etc/systemd/system/opibot-mission.target`
5. `userpatches/overlay/etc/systemd/system/opibot-perception-prepare.service`
6. `userpatches/overlay/etc/systemd/system/opibot-control-prepare.service`

现有过渡实现：

1. `userpatches/overlay/etc/systemd/system/opibot-ros2.target`
2. `userpatches/overlay/etc/systemd/system/opibot-ros2-high-performance.service`

### 4.3 阶段 C 任务清单

1. 新建 `opibot-base.target` 作为统一基础目标。
2. 新建 `opibot-perception.target`。
3. 新建 `opibot-control.target`。
4. 新建 `opibot-mission.target`。
5. 新建 `opibot-perception-prepare.service`，在感知目标之前切到 `perception-active`。
6. 新建 `opibot-control-prepare.service`，在控制目标之前切到 `control-active`。
7. 选择一组最小业务服务先迁移：
   - 1 个控制服务
   - 1 个感知服务
   - 1 个支撑服务
8. 为这 3 组服务分别补 CPUAffinity、Nice、MemoryLock、RTPriority 配置。
9. 将控制服务挂到 `opibot-control.target`。
10. 将感知服务挂到 `opibot-perception.target`。
11. 将支撑服务保留在 `opibot-base.target` 或系统域。
12. 暂不大规模迁移所有 ROS2 服务，先做小规模实机验证。

### 4.4 阶段 C 验收

1. 启动 `opibot-control.target` 前，系统已进入 `control-active`。
2. 启动 `opibot-perception.target` 前，系统已进入 `perception-active`。
3. 控制服务不会和感知服务落在同一 CPU 域。
4. 待机状态下自动退回 `standby`。

### 4.5 阶段 C 回滚点

1. 把迁移的最小业务服务重新挂回旧 target 或默认 multi-user 路径。
2. 停用 prepare service。

## 5. 阶段 D：验证、收敛与退役旧实现

### 5.1 目标

1. 建立实机验证闭环。
2. 收敛温度、频率、抖动和功耗参数。
3. 最终退役旧 `runtime-rt-tune` 体系。

### 5.2 阶段 D 任务清单

1. 建立控制环周期抖动测试。
2. 建立控制输出端到端延迟测试。
3. 建立 FASTVIO 或等价感知任务的帧间抖动测试。
4. 建立 standby/perception/control 三态温度与功耗对比测试。
5. 建立 10 分钟、30 分钟、1 小时热稳定测试。
6. 调整低功耗模式大小核频率上限。
7. 调整感知域频率上限与并行度策略。
8. 明确关键 IRQ 白名单。
9. 在所有关键指标稳定后，停用旧 `runtime-rt-tune.service`。
10. 删除旧 `opibot-performance-mode` 过渡命名与兼容路径。

### 5.3 阶段 D 验收

1. 控制闭环抖动不高于旧方案。
2. 感知任务在感知域中的稳定性优于旧方案。
3. 待机功耗和温度显著下降。
4. 模式切换不会导致控制服务异常。
5. 旧实现可以安全下线。

### 5.4 阶段 D 回滚点

1. 若关键控制指标退化，重新启用旧 `runtime-rt-tune.service` 并停用新 target 编排。

## 6. 文件实施顺序建议

建议按以下顺序动文件：

1. `.gitignore`
2. `userpatches/customize-image.sh`
3. `userpatches/overlay/etc/default/opibot-boot-profile`
4. `userpatches/overlay/etc/default/opibot-runtime-mode`
5. `userpatches/overlay/etc/default/opibot-irq-layout`
6. `userpatches/overlay/etc/default/opibot-service-layout`
7. `userpatches/overlay/usr/local/sbin/opibot-runtime-mode`
8. `userpatches/overlay/usr/local/sbin/opibot-irq-layout`
9. `userpatches/overlay/usr/local/sbin/opibot-boot-profile-sync`
10. `userpatches/overlay/etc/systemd/system/opibot-runtime-mode.service`
11. `userpatches/overlay/etc/systemd/system/opibot-runtime-autoswitch.service`
12. `userpatches/overlay/etc/systemd/system/opibot-base.target`
13. `userpatches/overlay/etc/systemd/system/opibot-perception.target`
14. `userpatches/overlay/etc/systemd/system/opibot-control.target`
15. `userpatches/overlay/etc/systemd/system/opibot-mission.target`
16. `userpatches/overlay/etc/systemd/system/opibot-perception-prepare.service`
17. `userpatches/overlay/etc/systemd/system/opibot-control-prepare.service`

## 7. 建议的第一轮实施边界

如果现在就进入代码重构，建议第一轮只做这些：

1. 配置文件拆分。
2. `performance-mode` 到 `runtime-mode` 的命名和职责迁移。
3. `opibot-perception.target`、`opibot-control.target`、`opibot-mission.target` 的建立。
4. 去掉当前“全部 `eth|can|tty` 默认进 RT 域”的行为。

第一轮不要做：

1. 自动识别所有传感器设备并动态分类 IRQ。
2. 大规模迁移全部 ROS2 服务。
3. 复杂的热降级控制策略。
4. 激进 RT 调度参数放宽。

## 8. 进入代码实施前的决策门槛

开始真正改代码前，建议你先确认以下 5 个问题：

1. 控制关键服务名单是否已经明确。
2. 感知高算力服务名单是否已经明确。
3. PX4 或等价控制任务是否确定直接跑在 SBC 上。
4. 哪些总线与设备中断必须进入控制域是否已有初步名单。
5. 是否接受在迁移期间短期保留旧 `runtime-rt-tune` 作为 fallback。

只要这 5 个问题能回答，第一阶段实施就可以开始。