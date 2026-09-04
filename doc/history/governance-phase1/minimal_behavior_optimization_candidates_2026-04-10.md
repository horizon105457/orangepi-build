# 最小行为优化候选

日期：2026-04-10

目标：

1. 基于当前二次开发代码，给出最小行为优化候选。
2. 每个候选只覆盖一条最小链路。
3. 为后续 Gate C 提供明确入口，但当前不直接改代码。

## 1. 候选筛选原则

只保留满足以下条件的候选：

1. 影响面小
2. 可单独验证
3. 有明确回滚锚点
4. 不要求同时改 build 仓和内核仓

## 2. 候选 A：统一 CPU 列表解析

状态：已执行

### 目标

让 runtime 相关脚本对 CPU 列表和 CPU 范围使用同一套解析策略。

### 触发原因

1. [../../userpatches/overlay/usr/local/sbin/opibot-performance-mode](../../../userpatches/overlay/usr/local/sbin/opibot-performance-mode) 有 `expand_cpulist`
2. [../../userpatches/overlay/usr/local/sbin/runtime-rt-tune](../../../userpatches/overlay/usr/local/sbin/runtime-rt-tune) 里的部分逻辑直接用 `tr ',' ' ' | tr '-' ' '` 处理 CPU 列表

### 最小改动边界

1. 只改 [../../userpatches/overlay/usr/local/sbin/runtime-rt-tune](../../../userpatches/overlay/usr/local/sbin/runtime-rt-tune)
2. 不改模式切换语义
3. 不改 systemd 单位

### 预期收益

1. 消除未来配置从 `6,7` 演进到 `4-7` 时的潜在错误
2. 属于低风险高收益修复

### 风险

1. 很低

### 最小验证

1. `Harness: preflight`
2. `Harness: runtime issue snapshot`
3. 脚本静态检查

### 回滚锚点

1. [../../userpatches/overlay/usr/local/sbin/runtime-rt-tune](../../../userpatches/overlay/usr/local/sbin/runtime-rt-tune)

### 执行结果

1. 已在 [../../userpatches/overlay/usr/local/sbin/runtime-rt-tune](../../../userpatches/overlay/usr/local/sbin/runtime-rt-tune) 中新增统一的 `expand_cpulist`
2. 已将 cpuidle 处理路径切换到统一展开逻辑
3. 已完成最小语法校验，未引入新错误

## 3. 候选 B：收敛 runtime 入口转调方式

状态：已执行

### 目标

让 [../../userpatches/overlay/usr/local/sbin/opibot-runtime-mode](../../../userpatches/overlay/usr/local/sbin/opibot-runtime-mode) 不再只做极薄的参数转发壳。

### 触发原因

1. 当前新入口名义上是事实入口
2. 实际行为仍直接交给 [../../userpatches/overlay/usr/local/sbin/opibot-performance-mode](../../../userpatches/overlay/usr/local/sbin/opibot-performance-mode)

### 最小改动边界

1. 只改 `opibot-runtime-mode`
2. 不删除旧 `opibot-performance-mode`
3. 旧脚本继续作为 fallback

### 预期收益

1. 降低新旧入口歧义
2. 为后续真正解耦打基础

### 风险

1. 中

### 最小验证

1. `Harness: preflight`
2. `Harness: gate-b audit pack`
3. `Harness: runtime issue snapshot`
4. `opibot-runtime-mode status` 行为核对

### 回滚锚点

1. [../../userpatches/overlay/usr/local/sbin/opibot-runtime-mode](../../../userpatches/overlay/usr/local/sbin/opibot-runtime-mode)

### 执行结果

1. 已将 [../../userpatches/overlay/usr/local/sbin/opibot-runtime-mode](../../../userpatches/overlay/usr/local/sbin/opibot-runtime-mode) 收敛为显式公共入口
2. 已显式处理 `apply`、`apply-config`、`watch`、`status` 与帮助输出
3. 旧 `opibot-performance-mode` 仍保留为后端执行路径，未扩大行为改动面
4. 已完成最小语法校验，未引入新错误

## 4. 候选 C：明确三态中的 perception-active 行为

状态：已执行

### 目标

决定 `perception-active` 当前是否应继续等价于 `rt-high-performance`，还是应有与 `control-active` 不同的最小行为。

### 触发原因

1. 文档层已经存在三态模型
2. 当前实现中 `perception-active` 和 `control-active` 都映射为同一旧模式

### 最小改动边界

1. 只改 runtime 脚本层
2. 不动 build 主流程
3. 不动内核仓

### 预期收益

1. 让文档语义与运行语义开始对齐
2. 为感知/控制分域打下真实基础

### 风险

1. 中到高

### 最小验证

1. `Harness: preflight`
2. 对 `opibot-control-prepare.service` 与 `opibot-perception-prepare.service` 的切换行为做人工核对
3. 必要时再进入 kernel-only build 或镜像级验证

### 回滚锚点

1. [../../userpatches/overlay/usr/local/sbin/opibot-runtime-mode](../../../userpatches/overlay/usr/local/sbin/opibot-runtime-mode)
2. [../../userpatches/overlay/usr/local/sbin/opibot-performance-mode](../../../userpatches/overlay/usr/local/sbin/opibot-performance-mode)
3. [../../userpatches/overlay/usr/local/sbin/opibot-irq-layout](../../../userpatches/overlay/usr/local/sbin/opibot-irq-layout)

### 执行结果

1. 已在 [../../userpatches/overlay/usr/local/sbin/opibot-runtime-mode](../../../userpatches/overlay/usr/local/sbin/opibot-runtime-mode) 中增加 runtime 语义态持久化，避免新入口调用后再次丢失 `control-active` 与 `perception-active` 的差异
2. 已在 [../../userpatches/overlay/usr/local/sbin/opibot-performance-mode](../../../userpatches/overlay/usr/local/sbin/opibot-performance-mode) 中补齐语义态跟随更新，使 autoswitch 回到 `standby` 时不会留下陈旧状态
3. 已在 [../../userpatches/overlay/usr/local/sbin/opibot-irq-layout](../../../userpatches/overlay/usr/local/sbin/opibot-irq-layout) 中把 `control-active` 保持为 RT 定向 IRQ 布局，把 `perception-active` 收敛为通用 irqbalance 布局
4. 当前三态的最小行为差异已落在 IRQ 策略层，未扩大到 boot 参数或内核仓修改

## 5. 候选 D：收敛 boot 参数渲染权威源

状态：已执行

### 目标

只保留一个权威的 boot 参数渲染实现。

### 触发原因

1. [../../userpatches/customize-image.sh](../../../userpatches/customize-image.sh) 中有直接写 `orangepiEnv.txt` 的兼容逻辑
2. [../../userpatches/overlay/usr/local/sbin/opibot-boot-profile-sync](../../../userpatches/overlay/usr/local/sbin/opibot-boot-profile-sync) 中也有独立实现

### 最小改动边界

1. 优先只做权威源确认
2. 如进入行为修改，只改一处实现

### 当前已完成

1. 已在 [../../userpatches/overlay/usr/local/sbin/opibot-boot-profile-sync](../../../userpatches/overlay/usr/local/sbin/opibot-boot-profile-sync) 中标记其为 boot 参数渲染权威源
2. 已在 [../../userpatches/customize-image.sh](../../../userpatches/customize-image.sh) 中标记 inline 写入逻辑仅为 compatibility fallback
3. 已将 [../../userpatches/customize-image.sh](../../../userpatches/customize-image.sh) 中的 inline 渲染实现收敛为缺失 helper 时的 fail-fast 闸门
4. 当前 boot 参数只通过 [../../userpatches/overlay/usr/local/sbin/opibot-boot-profile-sync](../../../userpatches/overlay/usr/local/sbin/opibot-boot-profile-sync) 渲染

### 预期收益

1. 降低构建期和运行期逻辑漂移风险

### 风险

1. 中

### 最小验证

1. `Harness: runtime issue snapshot`
2. `opibot-boot-profile-sync diff`

### 回滚锚点

1. [../../userpatches/customize-image.sh](../../../userpatches/customize-image.sh)
2. [../../userpatches/overlay/usr/local/sbin/opibot-boot-profile-sync](../../../userpatches/overlay/usr/local/sbin/opibot-boot-profile-sync)

## 6. 推荐顺序

### 第一优先级

1. 候选 A：统一 CPU 列表解析（已完成）

### 第二优先级

1. 候选 B：收敛 runtime 入口转调方式（已完成）

### 第三优先级

1. 候选 D：收敛 boot 参数渲染权威源（已完成）

### 第四优先级

1. 候选 C：明确 perception-active 行为（已完成）

## 7. 归档时结论

当前最小行为优化链已全部落完，可以回到主线开发；如果后续还要继续重构，应该进入更高层的 runtime/service-layout 解耦，而不是继续在同一层做小修。

原因：

1. 候选 A、B、D 已经完成
2. 候选 C 已完成最小可验证分化
3. 后续再改会开始触碰更高风险的运行时策略边界