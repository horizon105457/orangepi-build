# Harness 风格重构接管规范

日期：2026-04-10

目标：

1. 在双仓开发环境中接管当前 RK3588S CM5 重构工作。
2. 以后续重构开发框架为主，尽量不直接改动代码本体。
3. 尽量不碰官方仓库基线内容，优先只动本地分支的二次开发层。
4. 将修改限制在可回滚、可审计、低漂移风险的区域。

## 1. 接管原则

采用 Harness 风格的最小侵入式接管原则：

1. 先冻结边界，再推进实现。
2. 先定义接口和目录职责，再迁移运行时行为。
3. 先改配置层、overlay 层、文档层，再考虑脚本层。
4. 能通过新增本地扩展解决的问题，不通过改官方基线解决。
5. 能在主仓完成的内核修改，不在 build 同步副本中手工修改。
6. 每一步都必须具备回滚路径。

## 2. 双仓职责边界

### 2.1 linux-orangepi-rt

这是 RT 内核源码主仓。

默认放在这里完成：

1. 内核源码修改。
2. 驱动修改。
3. DTS 修改。
4. Kconfig 修改。
5. 补丁基线整理。

### 2.2 orangepi-build

这是镜像构建与系统集成仓。

默认放在这里完成：

1. 镜像构建入口。
2. overlay 文件布局。
3. userpatches 配置。
4. rootfs 定制。
5. systemd 编排。
6. 集成验证与部署文档。

### 2.3 明确禁止的默认做法

1. 不把 `orangepi-build/kernel/orange-pi-6.1-rk35xx-rt` 当成长期开发主目录。
2. 不在 build 仓同步副本中积累长期手工修改。
3. 不把官方 build 脚本当作重构首选落点。

## 3. 修改优先级分层

后续所有改动按以下优先级选落点。

### A 层：优先修改区

这些区域默认允许作为重构框架的主要承载层：

1. `doc/`
2. `userpatches/config-*.conf`
3. `userpatches/customize-image.sh`
4. `userpatches/overlay/etc/default/`
5. `userpatches/overlay/etc/systemd/system/`
6. `userpatches/overlay/usr/local/sbin/`
7. `userpatches/overlay/usr/local/share/opibot/`
8. `userscripts/`

这类区域的用途是：

1. 冻结接口。
2. 收敛命名。
3. 承载运行时模式框架。
4. 承载部署文档。
5. 承载项目级二次开发逻辑。

### B 层：受控修改区

这些区域只在 A 层无法承载需求时才允许进入：

1. `external/config/boards/`
2. `external/config/kernel/`
3. `external/config/sources/families/`
4. `external/patch/`

进入条件：

1. 需求属于板级定义、内核 defconfig、源码来源配置或补丁编排。
2. 无法通过 `userpatches/`、overlay 或运行时配置解决。
3. 改动必须保持最小差异，并附带原因说明。

### C 层：默认避免区

这些区域即使在本地分支已有修改，也不作为当前重构框架的首选落点：

1. `scripts/main.sh`
2. `scripts/compilation.sh`
3. `scripts/image-helpers.sh`
4. `external/packages/`

进入条件：

1. 已确认存在 build 流程级阻断。
2. 无法通过配置、overlay、userpatches 或外部补丁解决。
3. 修改范围可控，且不会把本地分支进一步绑死在官方实现细节上。

### D 层：默认禁止区

1. `orangepi-build/kernel/orange-pi-6.1-rk35xx-rt`
2. `external/cache/`
3. `output/`
4. `toolchains/`
5. 任何构建生成物目录

这些目录不作为事实来源，也不作为长期维护位置。

## 4. 接管后的默认工作流

### 4.1 需求分类

先判断问题属于哪一层：

1. 内核能力缺失。
2. 镜像集成缺失。
3. 运行时编排缺失。
4. 配置命名混乱。
5. 验证闭环缺失。

### 4.2 落点选择

按顺序决策：

1. 能否只改文档或配置。
2. 能否只改 overlay 或 userpatches。
3. 能否只改 systemd 编排和运行时脚本。
4. 是否必须进入 build 配置层。
5. 是否必须进入内核主仓。

不满足上一步的必要性证明，不进入下一层。

### 4.3 变更实施

实施顺序固定为：

1. 文档或配置冻结。
2. 最小框架调整。
3. 实机或构建验证。
4. 记录回滚点。

### 4.4 验证原则

1. 所有构建、试跑、验证命令必须显式带 timeout。
2. 先验证本地扩展层，再验证整镜像链路。
3. 验证时必须明确区分内核主仓与 build 同步副本。

## 5. 当前阶段的重构策略

基于现有文档与分支状态，当前优先做“框架接管”，不优先做“代码重写”。

当前策略：

1. 继续沿用既有三态运行时框架命名：`standby`、`perception-active`、`control-active`。
2. 继续沿用既有 target 分层：`opibot-base.target`、`opibot-perception.target`、`opibot-control.target`、`opibot-mission.target`。
3. 后续重构优先整理接口、职责、部署入口和验证路径。
4. 不主动扩散到官方 build 主流程文件，除非已有明确阻断证据。

## 6. 当前允许优先推进的事项

1. 补全和收敛接管文档。
2. 固化二次开发目录职责。
3. 清理和统一 `userpatches/overlay/etc/default/` 下的策略文件含义。
4. 清理和统一 `userpatches/overlay/etc/systemd/system/` 下的 target 与 prepare service 关系。
5. 清理和统一 `userpatches/overlay/usr/local/sbin/` 下的运行时入口脚本职责。
6. 建立最小验证清单与回滚清单。

## 7. 当前默认不做的事项

1. 不重写官方 build 主流程。
2. 不批量修改官方仓大面积脚本。
3. 不在未证明必要前修改内核源码。
4. 不在 build 内核同步副本中做长期变更。
5. 不创建新的 Python 虚拟环境。
6. 不重置已有 git 改动。

## 8. 执行口径

后续若无更强约束，按以下口径执行：

1. 以 `linux-orangepi-rt` 作为内核事实来源。
2. 以 `orangepi-build` 的 `userpatches/` 与 `doc/` 作为重构框架主落点。
3. 以最小侵入方式推进分层、命名、编排与验证闭环。
4. 对官方内容采取“能不动就不动、必须动时只动最小差异”的策略。