# 可信参考映射

日期：2026-04-10

本文档用于给当前双仓开发环境建立“可信辅助文档系统”的判定规则。

## 1. 分级规则

### T0：当前事实来源

特点：

1. 直接约束当前开发边界。
2. 与当前分支、当前构建入口或当前实现直接对应。
3. 优先级仅低于代码本身。

### T1：当前实现参考

特点：

1. 解释当前实现如何运行。
2. 适合快速理解系统链路。
3. 若与代码冲突，以代码为准。

### T2：设计与迁移参考

特点：

1. 用于理解设计意图和未来方向。
2. 可能部分过时。
3. 不可直接视为当前行为。

### T3：历史诊断与一次性记录

特点：

1. 用于问题背景、证据链和历史判断。
2. 时效性有限。
3. 只能辅助排查，不能替代当前状态确认。

## 2. 当前映射

### T0

1. [dual-workspace-handover.md](dual-workspace-handover.md)
2. [harness_refactor_takeover_2026-04-10.md](harness_refactor_takeover_2026-04-10.md)
3. [../../userpatches/config-opibot.conf](../../userpatches/config-opibot.conf)
4. [../../userpatches/customize-image.sh](../../userpatches/customize-image.sh)
5. [../../userpatches/overlay/etc/default/opibot-runtime-mode](../../userpatches/overlay/etc/default/opibot-runtime-mode)
6. [../../userpatches/overlay/etc/systemd/system/opibot-runtime-mode.service](../../userpatches/overlay/etc/systemd/system/opibot-runtime-mode.service)
7. [../../userpatches/overlay/etc/systemd/system/opibot-runtime-autoswitch.service](../../userpatches/overlay/etc/systemd/system/opibot-runtime-autoswitch.service)
8. linux-orangepi-rt 当前分支 `orange-pi-6.1-rk35xx-rt`

### T1

1. [hpw_change_hotspots_2026-04-10.md](hpw_change_hotspots_2026-04-10.md)
2. [customize_image_responsibility_audit_2026-04-10.md](customize_image_responsibility_audit_2026-04-10.md)
3. [runtime_compatibility_chain_audit_2026-04-10.md](runtime_compatibility_chain_audit_2026-04-10.md)
4. [technical_debt_matrix_2026-04-10.md](technical_debt_matrix_2026-04-10.md)
5. [mainline_dev_playbook_2026-04-10.md](mainline_dev_playbook_2026-04-10.md)
6. [../../build.sh](../../build.sh)
7. [../../userpatches/overlay/usr/local/sbin/opibot-runtime-mode](../../userpatches/overlay/usr/local/sbin/opibot-runtime-mode)
8. [../../userpatches/overlay/usr/local/share/opibot/runtime-deployment-guide.md](../../userpatches/overlay/usr/local/share/opibot/runtime-deployment-guide.md)
9. [../design/orangepicm5-cc-design.md](../design/orangepicm5-cc-design.md)

### T2

1. [../history/realtime_rearchitecture_proposal_2026-03-13.md](../history/realtime_rearchitecture_proposal_2026-03-13.md)
2. [../history/realtime_rearchitecture_checklist_2026-03-13.md](../history/realtime_rearchitecture_checklist_2026-03-13.md)

### T3

1. [../history/opibot_runtime_diagnosis_report_2026-03-13.md](../history/opibot_runtime_diagnosis_report_2026-03-13.md)
2. [../history/system_diagnosis_2026-03-13.md](../history/system_diagnosis_2026-03-13.md)
3. [../history/rk3588s_system_survey_summary_20260328.md](../history/rk3588s_system_survey_summary_20260328.md)
4. [../history/rk3588s_npu_path_probe_summary_20260328.md](../history/rk3588s_npu_path_probe_summary_20260328.md)
5. [../history/governance-phase1/README.md](../history/governance-phase1/README.md)

## 3. 实际使用建议

### 看事实

先看 T0，再看代码。

### 看运行链路

先看 T0，再补 T1。

### 看未来重构方向

先确认 T0/T1 当前状态，再参考 T2。

### 看历史问题背景

只在需要证据链或复盘时参考 T3。

## 4. hpw 提交的当前参考重点

若目标是追踪本地二次开发，优先看 hpw 的这些提交面：

### orangepi-build

1. `419d3ad`：RT 内核接入框架
2. `06389dd`：RT 配置收敛与旧脚本清理
3. `4065387`：overlay 运行时框架与部署文档
4. `c21befc`：工作区收尾、诊断文档与 RT 配置补充
5. `693f54c`：`customize-image.sh` 持续整理

### linux-orangepi-rt

1. `eeaf443e4`：PREEMPT_RT patch 基线
2. `b03e5140c`：CM5-CC DTS 与 overlay 预设
3. `80c266675`：dtb 安装链路补口
4. `a91ae6388`：CM5-CC camera endpoint 修正
5. `dcb75246f`：默认 overlay 推荐项收敛

## 5. 维护动作

后续若新增辅助文档，建议按下面方式维护：

1. 先判断属于 T0、T1、T2 还是 T3。
2. 再把它加入 [../README.md](../README.md) 的阅读顺序。
3. 如果旧文档失效，不删除原文，先在本映射中降级。