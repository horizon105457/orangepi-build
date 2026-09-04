# 技术债矩阵

日期：2026-04-10

目标：

1. 把当前二次开发的主要技术债按优先级固定下来。
2. 区分哪些债属于流程债、结构债、实现债。
3. 指导阶段二和阶段三的进入顺序。

## 1. P0：必须先文档化的债

### P0-1 runtime 兼容链不透明

类型：结构债

位置：

1. [runtime_compatibility_chain_audit_2026-04-10.md](runtime_compatibility_chain_audit_2026-04-10.md)

原因：

1. 不先搞清真实依赖链，就不应进入行为修改。

### P0-2 customize-image 主入口过载

类型：结构债

位置：

1. [customize_image_responsibility_audit_2026-04-10.md](customize_image_responsibility_audit_2026-04-10.md)

原因：

1. 不先划分职责边界，任何脚本重构都高风险。

## 2. P1：阶段二优先处理的债

### P1-1 新旧配置双轨并存

类型：结构债

对象：

1. `opibot-performance-mode`
2. `opibot-runtime-mode`
3. `opibot-boot-profile`
4. `opibot-irq-layout`

建议：

1. 先文档化各自语义，不先改行为。

### P1-2 systemd 新旧入口并存

类型：结构债

对象：

1. 新 runtime service
2. 旧 performance service
3. 旧 ros2 compatibility service

建议：

1. 先标记 legacy path。

### P1-3 工作区辅助入口仍偏少

类型：流程债

建议：

1. 继续补充审计与快照任务。

## 3. P2：阶段三候选债

### P2-1 runtime 新旧模式解耦

类型：实现债

状态：已完成首个入口收敛

前提：

1. 已完成兼容链文档化。

说明：

1. [../../userpatches/overlay/usr/local/sbin/opibot-runtime-mode](../../userpatches/overlay/usr/local/sbin/opibot-runtime-mode) 已从极薄转发壳收敛为显式公共入口
2. 旧 `opibot-performance-mode` 仍作为后端执行路径保留

### P2-2 customize-image 局部拆分

类型：实现债

前提：

1. 已完成职责审计和边界冻结。

### P2-3 IRQ 策略层独立化

类型：实现债

状态：已完成首个行为分化

前提：

1. 已完成 runtime 链职责收敛。

说明：

1. [../../userpatches/overlay/usr/local/sbin/opibot-irq-layout](../../userpatches/overlay/usr/local/sbin/opibot-irq-layout) 已开始承接三态中的 IRQ 行为分化
2. `control-active` 保持 RT 定向 IRQ 策略，`perception-active` 切回通用 irqbalance 策略
3. 差异仍限制在 runtime 脚本层，未扩大到 boot 参数与内核仓

### P2-6 service-layout 资源域平台化

类型：实现债

状态：已完成首个可消费骨架

说明：

1. [../../userpatches/overlay/usr/local/sbin/opibot-service-layout](../../userpatches/overlay/usr/local/sbin/opibot-service-layout) 已成为服务到资源域的统一入口
2. 已新增 control/perception/planning/support 四类 slice，并允许通过 [../../userpatches/overlay/etc/default/opibot-service-layout](../../userpatches/overlay/etc/default/opibot-service-layout) 映射业务服务
3. 当前平台策略优先保护控制域，不让感知与规划默认侵入控制 CPU 域

### P2-4 CPU 列表解析一致性

类型：实现债

状态：已完成首个局部修复

说明：

1. [../../userpatches/overlay/usr/local/sbin/runtime-rt-tune](../../userpatches/overlay/usr/local/sbin/runtime-rt-tune) 已统一 cpuidle 路径的 CPU 列表展开逻辑
2. 同类问题后续仅需在其他 runtime 脚本中按需复核，无需再把它作为首要阻断项

### P2-5 boot 参数渲染单源化

类型：实现债

状态：已完成

说明：

1. [../../userpatches/overlay/usr/local/sbin/opibot-boot-profile-sync](../../userpatches/overlay/usr/local/sbin/opibot-boot-profile-sync) 已标记为权威渲染源
2. [../../userpatches/customize-image.sh](../../userpatches/customize-image.sh) 中的 inline 写入逻辑已收敛为 helper 缺失时的 fail-fast 闸门
3. boot 参数当前只保留一个行为性渲染实现

## 4. 当前建议顺序

1. 先完成 P0。
2. 再完成 P1 的文档化与入口化。
3. 最后选择一个 P2 作为行为试点。