# Harness 框架入口

本目录是叠加在项目之上的非侵入式 Harness 开发框架层。

Harness 契约回答三个问题：
1. 哪个目录/组件负责什么。
2. 哪些改动允许进入，哪些必须设闸。
3. 哪些入口是事实来源，哪些只是兼容壳。

目标：

1. 不改官方 build 工程主干。
2. 不改变现有项目产物行为。
3. 让双仓开发具备稳定的契约、计划、审计和进入条件。

## 1. 设计原则

1. official code stays where it is：官方构建系统仍以 [build.sh](../build.sh) 和 [scripts](../scripts) 为主干。
2. project-specific integration stays local：项目二次开发仍以 [userpatches](../userpatches) 和 [doc](../doc) 为主落点。
3. Harness 只负责把“怎么开发、怎么审计、怎么进入行为改动”固定下来。

## 2. 目录结构

1. [contracts](contracts/)\: 组件边界、变更闸门、事实入口契约
   - [component_ownership.md](contracts/component_ownership.md)
   - [change_gates.md](contracts/change_gates.md)
2. [registry/source_of_truth.md](registry/source_of_truth.md)\: 事实源、热区和开发入口
3. [../doc/current/](../doc/current/)\: 审计正文和当前规则（统一入口，正文不长驻 harness 目录）

## 3. 当前最小进入顺序

1. 看 [registry/source_of_truth.md](registry/source_of_truth.md)
2. 看 [contracts/component_ownership.md](contracts/component_ownership.md)
3. 看 [contracts/change_gates.md](contracts/change_gates.md)
4. 看 [../doc/current/mainline_dev_playbook_2026-04-10.md](../doc/current/mainline_dev_playbook_2026-04-10.md)
5. 需要审计时进入 [../doc/current/](../doc/current/)：当前审计覆盖 `customize-image.sh`、runtime 兼容链、技术债矩阵

若要直接回到主线开发，优先看 [../doc/current/mainline_dev_playbook_2026-04-10.md](../doc/current/mainline_dev_playbook_2026-04-10.md)。

## 4. 与现有文档体系的关系

本目录不是替代 [doc/current](../doc/current)，而是把它们组织成项目级工程框架。

对应关系：

1. `doc/current`：当前规则与审计正文
2. `harness/`：工程框架入口、契约和计划层

## 5. 当前结论

项目已按 Harness 风格运作。Harness 框架层保持精简：

1. 后续开发优先进入 `harness/` 和 `doc/current/`，不是直接在工程代码里摸索。
2. 只有经过契约和审计确认后，才进入行为变更。
3. 已完成使命的阶段性迁移材料已降级到 `doc/history/governance-phase1/`。