# 最小优化顺序

日期：2026-04-10

目标：

1. 将当前二次开发代码中的关键问题收敛成最小优化顺序。
2. 区分哪些问题可以先做非行为性收敛，哪些必须进入行为优化阶段。
3. 让后续主线开发只在必要时触发治理动作。

## 1. 当前优先级结论

### P1

运行时事实源不清晰。

涉及：

1. [../../userpatches/overlay/usr/local/sbin/opibot-runtime-mode](../../../userpatches/overlay/usr/local/sbin/opibot-runtime-mode)
2. [../../userpatches/overlay/usr/local/sbin/opibot-performance-mode](../../../userpatches/overlay/usr/local/sbin/opibot-performance-mode)
3. [../../userpatches/overlay/etc/default/opibot-performance-mode](../../../userpatches/overlay/etc/default/opibot-performance-mode)
4. [../../userpatches/overlay/etc/default/opibot-runtime-mode](../../../userpatches/overlay/etc/default/opibot-runtime-mode)

判断：

1. 这是最高优先级问题。
2. 先做事实源收敛和角色标注，不先改行为。

### P2

三态模型文档已成立，但行为未真正分化。

涉及：

1. [../../userpatches/overlay/etc/default/opibot-boot-profile](../../../userpatches/overlay/etc/default/opibot-boot-profile)
2. [../../userpatches/overlay/etc/default/opibot-runtime-mode](../../../userpatches/overlay/etc/default/opibot-runtime-mode)
3. [../../userpatches/overlay/usr/local/sbin/opibot-runtime-mode](../../../userpatches/overlay/usr/local/sbin/opibot-runtime-mode)
4. [../../userpatches/overlay/usr/local/sbin/opibot-performance-mode](../../../userpatches/overlay/usr/local/sbin/opibot-performance-mode)

判断：

1. 这是首个行为优化候选。
2. 但前提是先完成 P1 的非行为性收敛。

### P3

CPU 列表解析策略不一致。

涉及：

1. [../../userpatches/overlay/usr/local/sbin/runtime-rt-tune](../../../userpatches/overlay/usr/local/sbin/runtime-rt-tune)

判断：

1. 这是低风险高收益问题。
2. 可作为阶段三中优先级很高的局部代码优化。

### P4

boot 参数同步存在双份实现。

涉及：

1. [../../userpatches/customize-image.sh](../../../userpatches/customize-image.sh)
2. [../../userpatches/overlay/usr/local/sbin/opibot-boot-profile-sync](../../../userpatches/overlay/usr/local/sbin/opibot-boot-profile-sync)

判断：

1. 先标记单一权威渲染源。
2. 再决定是否在行为阶段做代码收敛。

## 2. 建议顺序

### 第一步：Gate B 非行为性收敛

做这些事：

1. 标记 runtime 事实入口、兼容壳、fallback。
2. 标记 boot 参数渲染权威源。
3. 记录三态模型当前“文档值”和“行为值”的差异。

不做这些事：

1. 不改 runtime 切换行为。
2. 不改 boot 参数实际渲染结果。

### 第二步：Gate C 最小行为试点

优先试点顺序：

1. CPU 列表解析一致性
2. runtime 新旧入口单点收敛
3. 三态模型差异收敛
4. boot 参数渲染单源化

## 3. 归档时可直接执行的检查

1. 跑 `Harness: preflight`
2. 跑 `Harness: gate-b audit pack`
3. 跑 `Harness: runtime issue snapshot`

## 4. 归档时建议

若没有新的行为性主线需求，先停在 Gate B。

若已经出现明确主线阻断，则优先从 P3 开始做最小行为试点。