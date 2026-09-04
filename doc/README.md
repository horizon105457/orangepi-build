# OPiBot 双仓可信文档入口

本目录用于承载双仓开发环境下的辅助文档入口。

目标不是覆盖所有历史材料，而是提供一套可持续维护的“可信参考顺序”，避免后续开发被过时文档、构建副本和一次性诊断记录误导。

项目级 Harness 框架入口见 [../harness/README.md](../harness/README.md)。

## 0. 目录结构

1. [current](current)：当前接管规则、边界与参考映射
2. [design](design)：设计参考与板级方案说明
3. [history](history)：历史方案、诊断与调查记录

## 1. 建议阅读顺序

### 第一层：当前事实来源

优先阅读这些文件：

1. [current/dual-workspace-handover.md](current/dual-workspace-handover.md)
2. [current/harness_refactor_takeover_2026-04-10.md](current/harness_refactor_takeover_2026-04-10.md)
3. [current/trusted_reference_map_2026-04-10.md](current/trusted_reference_map_2026-04-10.md)
4. [current/hpw_change_hotspots_2026-04-10.md](current/hpw_change_hotspots_2026-04-10.md)
5. [current/technical_debt_matrix_2026-04-10.md](current/technical_debt_matrix_2026-04-10.md)
6. [current/customize_image_responsibility_audit_2026-04-10.md](current/customize_image_responsibility_audit_2026-04-10.md)
7. [current/runtime_compatibility_chain_audit_2026-04-10.md](current/runtime_compatibility_chain_audit_2026-04-10.md)
8. [current/mainline_dev_playbook_2026-04-10.md](current/mainline_dev_playbook_2026-04-10.md)
9. [../userpatches/config-opibot.conf](../userpatches/config-opibot.conf)
10. [../userpatches/overlay/usr/local/share/opibot/runtime-deployment-guide.md](../userpatches/overlay/usr/local/share/opibot/runtime-deployment-guide.md)

### 第二层：当前实现参考

当需要理解镜像构建与运行时链路时，优先读这些实现文件：

1. [../build.sh](../build.sh)
2. [../userpatches/customize-image.sh](../userpatches/customize-image.sh)
3. [../userpatches/overlay/usr/local/sbin/opibot-runtime-mode](../userpatches/overlay/usr/local/sbin/opibot-runtime-mode)
4. [../userpatches/overlay/etc/default/opibot-runtime-mode](../userpatches/overlay/etc/default/opibot-runtime-mode)
5. [../userpatches/overlay/etc/systemd/system/opibot-runtime-mode.service](../userpatches/overlay/etc/systemd/system/opibot-runtime-mode.service)
6. [../userpatches/overlay/etc/systemd/system/opibot-runtime-autoswitch.service](../userpatches/overlay/etc/systemd/system/opibot-runtime-autoswitch.service)

### 第三层：设计与历史参考

这些文档保留参考价值，但不能替代当前代码和配置：

1. [design/orangepicm5-cc-design.md](design/orangepicm5-cc-design.md)
2. [history/governance-phase1/README.md](history/governance-phase1/README.md)
3. [history/realtime_rearchitecture_proposal_2026-03-13.md](history/realtime_rearchitecture_proposal_2026-03-13.md)
4. [history/realtime_rearchitecture_checklist_2026-03-13.md](history/realtime_rearchitecture_checklist_2026-03-13.md)
5. [history/opibot_runtime_diagnosis_report_2026-03-13.md](history/opibot_runtime_diagnosis_report_2026-03-13.md)
6. [history/system_diagnosis_2026-03-13.md](history/system_diagnosis_2026-03-13.md)
7. [history/rk3588s_system_survey_summary_20260328.md](history/rk3588s_system_survey_summary_20260328.md)
8. [history/rk3588s_npu_path_probe_summary_20260328.md](history/rk3588s_npu_path_probe_summary_20260328.md)

已归档的历史文档统一放在 [history](history) 下，避免继续占用仓库根目录。
阶段性治理材料已从 [current](current) 降级到 [history/governance-phase1](history/governance-phase1)，避免把“接管期材料”误当成当前事实层。

## 2. 项目最小运行逻辑

当前项目可以按下面这条最小主链理解：

1. [../build.sh](../build.sh) 是构建入口，负责环境检查、提权和进入 Orange Pi build 主流程。
2. [../userpatches/config-opibot.conf](../userpatches/config-opibot.conf) 决定 OPiBot 目标镜像的构建参数，包括 RT 构建开关、板型、发行版和内核源码来源。
3. build 主流程在镜像阶段调用 [../userpatches/customize-image.sh](../userpatches/customize-image.sh)，将 overlay、systemd、RT 配置、ROS2/OpenCV 与项目级集成逻辑写入根文件系统。
4. 镜像启动后，systemd 通过 [../userpatches/overlay/etc/systemd/system/opibot-runtime-mode.service](../userpatches/overlay/etc/systemd/system/opibot-runtime-mode.service) 和 [../userpatches/overlay/etc/systemd/system/opibot-runtime-autoswitch.service](../userpatches/overlay/etc/systemd/system/opibot-runtime-autoswitch.service) 进入运行时模式链路。
5. 当前的 [../userpatches/overlay/usr/local/sbin/opibot-runtime-mode](../userpatches/overlay/usr/local/sbin/opibot-runtime-mode) 仍是对旧 `opibot-performance-mode` 的兼容封装，说明运行时框架已冻结新命名，但实现尚未完全去旧。
6. RT 内核源码事实来源是双工作区中的 linux-orangepi-rt；orangepi-build 下的内核同步副本只用于构建消费。

## 3. hpw 变更热点（概要）

详见 [current/hpw_change_hotspots_2026-04-10.md](current/hpw_change_hotspots_2026-04-10.md)。

**build 仓**：RT 内核配置、`customize-image.sh`、runtime 三层框架（runtime-mode → irq-layout → service-layout）、少量构建接缝。

**内核仓**：PREEMPT_RT 基线 6.1.99-rt36、CM5-CC DTS/overlay、dtb 安装链路。

## 4. 使用规则

1. 代码与配置永远比文档更高优先级。
2. 诊断报告只用于提供背景，不直接作为当前实现结论。
3. 设计文档用于理解意图，不直接视为已落地事实。
4. 若文档与实现冲突，以实现为准，并在本目录补充纠偏说明。

## 5. 维护原则

1. 新增文档优先放到本目录并纳入索引。
2. 新增文档时必须标明“事实来源 / 设计参考 / 历史诊断”之一。
3. 若文档明显过时，不立即删除，先在索引中降级标注。