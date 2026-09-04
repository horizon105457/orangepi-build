# runtime 兼容链审计

日期：2026-04-10

对象：

1. [../../userpatches/overlay/usr/local/sbin/opibot-runtime-mode](../../userpatches/overlay/usr/local/sbin/opibot-runtime-mode)
2. [../../userpatches/overlay/usr/local/sbin/opibot-performance-mode](../../userpatches/overlay/usr/local/sbin/opibot-performance-mode)
3. [../../userpatches/overlay/usr/local/sbin/opibot-irq-layout](../../userpatches/overlay/usr/local/sbin/opibot-irq-layout)
4. [../../userpatches/overlay/usr/local/sbin/opibot-boot-profile-sync](../../userpatches/overlay/usr/local/sbin/opibot-boot-profile-sync)
5. [../../userpatches/overlay/usr/local/sbin/runtime-rt-tune](../../userpatches/overlay/usr/local/sbin/runtime-rt-tune)

结论：

当前 runtime 新框架已经完成命名冻结，但真实行为仍主要由旧链路驱动。

## 1. 角色划分

### 事实入口

1. [opibot-runtime-mode.service](../../userpatches/overlay/etc/systemd/system/opibot-runtime-mode.service)
2. [opibot-runtime-autoswitch.service](../../userpatches/overlay/etc/systemd/system/opibot-runtime-autoswitch.service)
3. [opibot-control-prepare.service](../../userpatches/overlay/etc/systemd/system/opibot-control-prepare.service)
4. [opibot-perception-prepare.service](../../userpatches/overlay/etc/systemd/system/opibot-perception-prepare.service)

### 兼容壳

1. [opibot-runtime-mode](../../userpatches/overlay/usr/local/sbin/opibot-runtime-mode)
2. [opibot-performance-mode](../../userpatches/overlay/usr/local/sbin/opibot-performance-mode)

### fallback / 底层执行器

1. [opibot-irq-layout](../../userpatches/overlay/usr/local/sbin/opibot-irq-layout)
2. [runtime-rt-tune](../../userpatches/overlay/usr/local/sbin/runtime-rt-tune)
3. [opibot-boot-profile-sync](../../userpatches/overlay/usr/local/sbin/opibot-boot-profile-sync)

## 2. 真实依赖链

### 启动时

1. systemd 启动 `opibot-runtime-mode.service`
2. service 调用 `opibot-runtime-mode apply-config`
3. `opibot-runtime-mode` 直接转调旧 `opibot-performance-mode`
4. 旧脚本再读取：
   `opibot-performance-mode`
   `opibot-boot-profile`
   `opibot-runtime-mode`
5. 旧脚本决定实际应用 `rt-high-performance` 或 `low-power`
6. 如需 IRQ 细化，控制态再借助 `runtime-rt-tune`

### 运行时 target 切换时

1. `opibot-control-prepare.service` 调 `apply control-active`
2. `opibot-perception-prepare.service` 调 `apply perception-active`
3. 这两个新模式在 `opibot-runtime-mode` 中被映射成旧模式
4. 最终仍由 `opibot-performance-mode` 执行具体行为

## 3. 关键问题

### 问题 1

新旧配置双轨并存。

证据：

1. [../../userpatches/overlay/etc/default/opibot-performance-mode](../../userpatches/overlay/etc/default/opibot-performance-mode)
2. [../../userpatches/overlay/etc/default/opibot-runtime-mode](../../userpatches/overlay/etc/default/opibot-runtime-mode)
3. [../../userpatches/overlay/etc/default/opibot-boot-profile](../../userpatches/overlay/etc/default/opibot-boot-profile)
4. [../../userpatches/overlay/etc/default/opibot-irq-layout](../../userpatches/overlay/etc/default/opibot-irq-layout)

影响：

1. 同一概念在不同文件里重复表达。
2. 读代码的人很难快速判断“哪个值真正生效”。

### 问题 2

新命名未对应新实现。

影响：

1. 文档上已经是 `control-active / perception-active / standby`
2. 行为上仍然主要是 `rt-high-performance / low-power`
3. 这会让后续优化容易误判真正变更点

### 问题 3

IRQ 层尚未真正独立。

`opibot-irq-layout` 当前更多是 runtime-rt-tune 的薄封装，而不是独立策略层。

### 问题 4

legacy service 仍保留且与新 service 并存。

对象：

1. [opibot-performance-mode.service](../../userpatches/overlay/etc/systemd/system/opibot-performance-mode.service)
2. [opibot-performance-autoswitch.service](../../userpatches/overlay/etc/systemd/system/opibot-performance-autoswitch.service)
3. [opibot-ros2-high-performance.service](../../userpatches/overlay/etc/systemd/system/opibot-ros2-high-performance.service)
4. [opibot-ros2.target](../../userpatches/overlay/etc/systemd/system/opibot-ros2.target)

影响：

1. 新旧路径并存时，接手者需要同时理解两套生命周期。
2. 这很容易成为 vibecoding 的误触发点。

## 4. 阶段二建议

当前建议只做非行为性收敛：

1. 标记事实入口、兼容壳、fallback 三类角色。
2. 冻结“哪个配置文件表达哪类语义”。
3. 文档上明确旧 service 属于 legacy compatibility path。
4. 不直接删除 legacy service 或旧脚本。

## 5. 阶段三候选优化点

1. 让 `opibot-runtime-mode` 先脱离对旧脚本的直接转调。
2. 让 `opibot-irq-layout` 先从 `runtime-rt-tune` 的薄封装变成独立策略入口。
3. 逐步缩减 `opibot-performance-mode` 为 fallback。