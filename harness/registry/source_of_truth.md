# 事实源注册表

## 1. 代码事实源

1. 内核： [../../../linux-orangepi-rt](../../../linux-orangepi-rt)
2. 构建入口： [../../build.sh](../../build.sh)
3. 镜像集成入口： [../../userpatches/customize-image.sh](../../userpatches/customize-image.sh)
4. runtime 入口： [../../userpatches/overlay/usr/local/sbin/opibot-runtime-mode](../../userpatches/overlay/usr/local/sbin/opibot-runtime-mode)

## 2. 文档事实源

1. [../../doc/current/README.md](../../doc/current/README.md)
2. [../../doc/current/trusted_reference_map_2026-04-10.md](../../doc/current/trusted_reference_map_2026-04-10.md)
3. [../../doc/current/hpw_change_hotspots_2026-04-10.md](../../doc/current/hpw_change_hotspots_2026-04-10.md)

## 3. 任务入口

1. [../../.vscode/tasks.json](../../.vscode/tasks.json)

## 4. 约束

1. 若 Harness 层文档与代码冲突，以代码和配置为准。
2. 若要进入行为修改，必须先通过 `contracts/change_gates.md`。