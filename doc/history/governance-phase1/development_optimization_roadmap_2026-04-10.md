# 开发优化路线图

日期：2026-04-10

目标：

1. 将后续接管工作固定为三阶段推进。
2. 第一阶段只优化开发流程，并把规则固化到文档和工程辅助结构。
3. 第二阶段只优化二次开发工程本身，重点做技术债清理和职责收敛。
4. 第三阶段才允许做局部代码优化，并明确这是唯一允许改变项目产物行为的阶段。

## 1. 总原则

### 原则 A

先治理开发流程，再治理工程结构，最后才治理实现行为。

### 原则 B

前两阶段的主要产物是：

1. 文档
2. 目录结构
3. 工作区设置
4. 任务入口
5. 职责边界

不以“代码重写”作为阶段目标。

### 原则 C

每一阶段结束前，都必须有明确的进入下一阶段条件。

## 2. 阶段一：开发流程优化

### 目标

把 vibecoding 开发流程变成“可控、可追踪、低跑偏”的标准动作。

### 允许修改的内容

1. [doc](../../README.md)
2. [.vscode/tasks.json](../../../.vscode/tasks.json)
3. [rk3588s-cm5-dual-kernel-dev.code-workspace](../../../rk3588s-cm5-dual-kernel-dev.code-workspace)
4. 其他不影响项目产物行为的辅助入口

### 核心动作

1. 固化可信文档入口。
2. 固化 hpw 热区导航。
3. 固化每轮开发的最小验证入口。
4. 固化双仓状态快照和头指针对比入口。
5. 固化“先选热区、再做单闭环”的开发协议。

### 归档时已落地内容

1. [README.md](../../README.md)
2. [current/trusted_reference_map_2026-04-10.md](../../current/trusted_reference_map_2026-04-10.md)
3. [current/hpw_change_hotspots_2026-04-10.md](../../current/hpw_change_hotspots_2026-04-10.md)
4. [current/vibecoding_and_secondary_dev_optimization_2026-04-10.md](vibecoding_and_secondary_dev_optimization_2026-04-10.md)
5. [.vscode/tasks.json](../../../.vscode/tasks.json)
6. [../../harness/README.md](../../../harness/README.md)

### 退出条件

1. 当前规则、设计参考、历史归档三层文档结构稳定。
2. 常用开发入口已有任务或明确命令模板。
3. 双仓职责边界和热区导航不再依赖口头说明。

## 3. 阶段二：二次开发工程优化

### 目标

在不改变项目产物行为的前提下，降低二次开发工程的复杂度和技术债。

### 允许修改的内容

1. 文档继续扩充
2. `userpatches/overlay/etc/default/` 的注释、命名和结构性整理
3. `userpatches/overlay/etc/systemd/system/` 的单位关系整理
4. `userpatches/overlay/usr/local/sbin/` 的职责边界整理
5. `userpatches/customize-image.sh` 的非行为性重构准备工作

### 禁止事项

1. 不改变运行模式切换行为
2. 不改变 boot profile 生效行为
3. 不改变镜像中实际安装的软件集合
4. 不改变内核、DTS、defconfig 的产物结果

### 核心动作

1. 为 [userpatches/customize-image.sh](../../../userpatches/customize-image.sh) 建立职责分组图。
2. 为 `opibot-runtime-mode -> opibot-performance-mode -> runtime-rt-tune` 建立真实依赖图。
3. 收敛 systemd target 与 prepare service 的边界。
4. 标记兼容壳、fallback、事实入口、过渡入口。
5. 收敛 build 仓对官方脚本接缝的进入条件。

### 推荐交付物

1. `customize-image` 职责审计文档
2. runtime 兼容链职责审计文档
3. systemd 目标关系文档
4. 技术债清单和优先级矩阵
5. Harness contracts / plans / audits / registry 框架层

### 退出条件

1. 主要技术债都有文档化边界。
2. 每个核心脚本都能回答“它负责什么、不负责什么”。
3. 已识别出可安全试点的最小局部优化链路。

## 4. 阶段三：局部代码优化

### 目标

在前两阶段稳定后，选择最小链路做代码层优化，提升质量和效率。

### 这是唯一允许改变项目产物行为的阶段

这里的“行为改变”包括：

1. 运行模式切换逻辑变化
2. service enable/disable 路径变化
3. 镜像默认内容变化
4. boot profile 同步逻辑变化
5. IRQ/CPU 绑定逻辑变化

### 进入条件

1. 已完成阶段一和阶段二文档化工作。
2. 已选定单一热区和单一试点目标。
3. 已准备最小验证方法和回滚锚点。

### 推荐试点顺序

1. 先试点运行时兼容链的单点收敛。
2. 再试点 `customize-image.sh` 中一个独立职责块的局部提取。
3. 最后才考虑更大范围的工程代码重构。

### 禁止事项

1. 不跨多个热区同时改行为。
2. 不把 build 仓官方脚本和 overlay 运行时脚本一起大改。
3. 不在没有验证入口时直接做整链路行为变更。

## 5. 推荐执行顺序

### 当时应优先做的事

1. 完成 `customize-image.sh` 的职责审计。
2. 完成运行时兼容链的职责审计。
3. 建立技术债优先级清单。

### 当时不应优先做的事

1. 直接重写 `opibot-performance-mode`
2. 直接拆分 `customize-image.sh`
3. 直接扩大对 `scripts/` 的修改面
4. 直接进入 full image build 驱动开发节奏

## 6. 开发协议

后续每轮开发建议固定为下面格式：

1. 指明当前阶段
2. 指明当前热区
3. 指明本轮是否允许改行为
4. 指明最小验证入口
5. 指明回滚锚点

建议模板：

1. 阶段：一 / 二 / 三
2. 热区：build 集成 / runtime / DTS / RT 基线
3. 行为变更：否 / 是
4. 验证：语法检查 / 状态快照 / kernel-only build / full image build
5. 回滚：对应文件 + 对应提交点