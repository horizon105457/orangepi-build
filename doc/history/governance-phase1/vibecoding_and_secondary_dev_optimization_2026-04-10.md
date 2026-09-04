# Vibecoding 流程与二次开发优化建议

日期：2026-04-10

目标：

1. 给当前双仓环境建立一套可控、高效、低跑偏风险的 AI 辅助开发流程。
2. 基于现有代码审计，给出项目二次开发的优化建议。
3. 明确哪些技术债应优先处理，哪些先通过流程约束兜住。

## 1. 审计结论

### 结论 A：当前运行时框架完成了“命名冻结”，但尚未完成“实现脱钩”

证据：

1. [userpatches/overlay/usr/local/sbin/opibot-runtime-mode](../../../userpatches/overlay/usr/local/sbin/opibot-runtime-mode) 仍直接调用旧的 `opibot-performance-mode`。
2. [userpatches/overlay/usr/local/sbin/opibot-performance-mode](../../../userpatches/overlay/usr/local/sbin/opibot-performance-mode) 同时兼容新旧配置文件，并把 `control-active`、`perception-active`、`standby` 映射回 `rt-high-performance`、`low-power`。
3. [userpatches/overlay/usr/local/sbin/opibot-irq-layout](../../../userpatches/overlay/usr/local/sbin/opibot-irq-layout) 当前仍主要把控制态委托给 `runtime-rt-tune`，尚未真正成为独立的 IRQ 策略层。

影响：

1. 新命名降低了文档层混乱，但没有真正降低实现复杂度。
2. 后续 AI 或人工接手时，容易误以为已经完成了 Phase B 的解耦。
3. 审计和调试时必须同时跟踪新入口和旧实现，认知成本偏高。

### 结论 B：镜像集成入口过于集中，`customize-image.sh` 已成为高风险变更点

证据：

1. [userpatches/customize-image.sh](../../../userpatches/customize-image.sh) 当前函数数目已达到 28 个以上。
2. 同一文件同时承担 overlay 合并、APT 安装、ROS2/OpenCV 安装、RT 引导、systemd enable、部署文档复制、硬件提示注入、可选桌面软件安装等职责。
3. hpw 的多次提交都反复集中在这个文件，说明它已经是最主要的人工接缝点。

影响：

1. 任何小改动都容易引起非目标区域回归。
2. AI 辅助修改时，如果上下文控制不好，最容易把 unrelated 逻辑一起改坏。
3. 该文件会天然吸走过多二次开发逻辑，降低后续模块化机会。

### 结论 C：systemd 目标分层是当前最值得保留的结构资产

证据：

1. [userpatches/overlay/etc/systemd/system/opibot-base.target](../../../userpatches/overlay/etc/systemd/system/opibot-base.target)
2. [userpatches/overlay/etc/systemd/system/opibot-mission.target](../../../userpatches/overlay/etc/systemd/system/opibot-mission.target)
3. [userpatches/overlay/etc/systemd/system/opibot-control-prepare.service](../../../userpatches/overlay/etc/systemd/system/opibot-control-prepare.service)
4. [userpatches/overlay/etc/systemd/system/opibot-perception-prepare.service](../../../userpatches/overlay/etc/systemd/system/opibot-perception-prepare.service)

影响：

1. 当前最可控的演化方向不是重写脚本，而是继续把业务和模式切换绑定到 target 层。
2. 这是最适合 vibecoding 逐步推进的区域，因为边界相对清晰、验证也较容易。

### 结论 D：build 仓官方脚本接缝已经存在，但仍应视为“最后进入区”

证据：

1. hpw 的 RT 接入已经修改过 `scripts/main.sh`、`scripts/compilation.sh`、`scripts/image-helpers.sh`。
2. 这些修改目前看是接缝性质，不是业务主落点。

影响：

1. 如果后续把大量二次开发继续压进官方脚本，会显著增加与 upstream 的偏离成本。
2. vibecoding 场景下，这类文件最容易出现“顺手多改几处”的风险，应继续严格限流。

## 2. 对 vibecoding 开发流程的优化建议

### 建议 1：强制使用“三层证据链”驱动每次开发

每次开始前必须明确：

1. 当前事实来源：`doc/current/` 和实际代码配置。
2. 当前变更热点：`hpw_change_hotspots_2026-04-10.md`。
3. 当前验证入口：工作区任务或显式带 timeout 的命令。

推荐顺序：

1. 先看 [current/trusted_reference_map_2026-04-10.md](../../current/trusted_reference_map_2026-04-10.md)
2. 再看 [current/hpw_change_hotspots_2026-04-10.md](../../current/hpw_change_hotspots_2026-04-10.md)
3. 再决定是进入 build 仓、内核仓，还是只改文档与配置

### 建议 2：把 vibecoding 的工作单元固定成“小闭环”

每一轮只允许做一种主操作：

1. 文档冻结
2. 配置整理
3. 单脚本小改
4. 单链路验证

不建议在一轮里同时做：

1. `customize-image.sh` 重构
2. systemd 编排调整
3. 内核 DTS 改动
4. 整镜像构建验证

推荐闭环模板：

1. 先说明目标热区。
2. 只改一个主文件或一组紧耦合文件。
3. 只跑对应最小验证。
4. 补一条文档或任务入口变化。

### 建议 3：把 AI 辅助开发默认限制在“热区优先 + 接缝后置”

默认优先级：

1. `doc/current/`
2. `userpatches/overlay/etc/default/`
3. `userpatches/overlay/etc/systemd/system/`
4. `userpatches/overlay/usr/local/sbin/`
5. `userpatches/customize-image.sh`
6. `external/config/*`
7. `scripts/*`
8. `linux-orangepi-rt`

说明：

1. 这不是技术优先级，而是 vibecoding 的默认改动安全优先级。
2. 真正涉及内核能力或 DTS 时，直接跳到 linux-orangepi-rt。

### 建议 4：把“长构建”从默认动作降级成“阶段性验证”

推荐验证金字塔：

1. 语法检查
2. 链路状态检查
3. 目标脚本 dry-read
4. kernel-only build
5. full image build

不要每次都直接做 full image build。

### 建议 5：所有 AI 辅助开发都附带一条“回退锚点”

每轮变更前至少记录：

1. 目标热区文档
2. 关键文件路径
3. 对应 hpw 提交或当前分支状态

这样后续即使多人或多代理接力，也能快速回到正确上下文。

## 3. 对项目二次开发的优化建议

### 建议 A：先拆职责，再拆代码

当前不要急着把 [userpatches/customize-image.sh](../../../userpatches/customize-image.sh) 大卸八块。

先做两步：

1. 给函数按职责分组并冻结边界。
2. 确定哪些逻辑应迁到 overlay 脚本、哪些留在构建期。

推荐先形成 5 组职责：

1. overlay 合并与权限修复
2. 基础软件安装
3. RT 引导与 service enable
4. 运行时文档与默认配置下发
5. 可选桌面/硬件提示逻辑

### 建议 B：逐步去掉 `opibot-runtime-mode -> opibot-performance-mode` 的硬依赖

不是一次性重写，而是分三步：

1. 先把旧逻辑中的“状态读取”和“模式映射”列清单。
2. 再把 `opibot-runtime-mode` 变成真正的一层编排入口。
3. 最后再缩减旧 `opibot-performance-mode` 的职责。

目标不是马上删旧脚本，而是让它退化为 fallback。

### 建议 C：保持 systemd target 作为业务部署主界面

后续业务服务接入时，优先通过：

1. `opibot-base.target`
2. `opibot-perception.target`
3. `opibot-control.target`
4. `opibot-mission.target`

不要把业务逻辑继续直接塞进运行时脚本。

### 建议 D：build 仓只保留“集成规则”，不要承载真实内核事实

保持原则：

1. DTS、overlay、Kconfig、驱动和 patch 基线在 linux-orangepi-rt。
2. build 仓只负责消费、集成和验证。
3. build 同步副本继续视为一次性消费物，不做长期人工维护。

### 建议 E：优先建设“可审计入口”，再追求自动化

当前比继续写更多脚本更重要的是：

1. 文档入口清晰
2. 工作区任务可复用
3. 热区导航稳定
4. 验证命令统一带 timeout

这些做好以后，再考虑更细的自动化任务。

## 4. 当时的后续推进顺序

以下顺序反映 2026-04-10 形成该文档时的治理建议，不代表今天仍应按同样优先级执行。

### 第一阶段

1. 对 `customize-image.sh` 做职责审计文档，不改实现。
2. 对运行时脚本兼容链做职责审计文档，不改实现。

### 第二阶段

1. 收敛工作区任务，补齐语法检查和双仓状态快照。
2. 固化“每轮变更只进一个热区”的开发规则。

### 第三阶段

1. 开始挑一条最小链路做去兼容壳试点。
2. 只在试点成功后，再继续扩到 runtime / irq / boot profile 三件套。

## 5. 归档时可立即执行的动作

1. 每次开发前先看 [hpw_change_hotspots_2026-04-10.md](../../current/hpw_change_hotspots_2026-04-10.md) 选热区。
2. 每次动脚本前先跑工作区中的语法检查任务。
3. 涉及双仓一致性时先跑“RT heads 对比”和双仓状态快照。
4. 暂时不要直接重构 `customize-image.sh` 和 `opibot-performance-mode`，先做只读职责审计。