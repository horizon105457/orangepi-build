# 双工作区接管说明

## 目标

为了按双仓协作方式继续开发，开发入口统一切换到共同上级目录下的多根工作区：

- `../rk3588s-cm5-dual-kernel-dev.code-workspace`

该工作区同时挂载：

- `orangepi-build`：镜像构建、overlay、userpatches、打包流程
- `linux-orangepi-rt`：RT 内核源码主仓

## 目录职责

### 1. `linux-orangepi-rt` 是 RT 内核源码真身

这里是日常内核开发、DTS 修改、驱动修改、补丁整理的主工作区。

当前接管时的内核仓分支为：

- `orange-pi-6.1-rk35xx-rt`

### 2. `orangepi-build/kernel/orange-pi-6.1-rk35xx-rt` 是构建同步副本

该目录由构建流程按 `KERNELSOURCE` 和 RT 分支约定自动拉取/更新，用于 build 系统消费。

不要把这里当作长期维护的源码主仓，也不要优先在这里做手工修改；否则后续重新拉取后容易被覆盖，且与外部 RT 仓偏离。

## 当前构建约定

在 `orangepi-build/userpatches/config-opibot.conf` 中，当前 RT 构建入口已经指向外部内核仓：

- `build_rt_image="yes"`
- `KERNELSOURCE="https://github.com/horizon105457/linux-orangepi.git"`
- RT 分支约定：`orange-pi-6.1-rk35xx-rt`

本地对应开发仓路径为：

- `../linux-orangepi-rt`

## 推荐工作流

1. 在 `linux-orangepi-rt` 中完成内核源码修改。
2. 将需要进入构建系统验证的提交推送到 RT 远端分支。
3. 回到 `orangepi-build` 触发构建，让其自动同步到 `kernel/orange-pi-6.1-rk35xx-rt`。
4. 板级配置、overlay、rootfs 定制、镜像集成类修改继续放在 `orangepi-build`。

## Workspace 设计说明

多根工作区中额外排除了以下高噪声目录，以降低索引与误操作概率：

- `orangepi-build/external/cache`
- `orangepi-build/output`
- `orangepi-build/toolchains`
- `orangepi-build/kernel/orange-pi-6.1-rk35xx-rt`

其中最后一项是刻意排除的“构建镜像副本目录”，用于提醒后续开发优先修改 `linux-orangepi-rt`。
