# 组件归属契约

## 1. 双仓归属

1. [../../../linux-orangepi-rt](../../../linux-orangepi-rt)：RT 内核源码主仓
2. [../..](../..)：镜像构建、overlay、userpatches、部署与验证仓

## 2. build 仓中的组件归属

### 官方主干

1. [../../build.sh](../../build.sh)
2. [../../scripts](../../scripts)
3. [../../external](../../external)

规则：

1. 默认不作为二次开发首选落点。
2. 仅在 userpatches、overlay、外部内核仓无法承载需求时进入。

### 项目二次开发主层

1. [../../userpatches](../../userpatches)
2. [../../doc](../../doc)
3. [../../.vscode/tasks.json](../../.vscode/tasks.json)

规则：

1. 默认在这里承载项目级扩展、规则、部署和验证。

### 构建消费副本

1. [../../kernel/orange-pi-6.1-rk35xx-rt](../../kernel/orange-pi-6.1-rk35xx-rt)

规则：

1. 不作为事实来源。
2. 不承载长期手工修改。

## 3. 当前高价值组件

1. [../../userpatches/customize-image.sh](../../userpatches/customize-image.sh)
2. [../../userpatches/overlay/usr/local/sbin/opibot-runtime-mode](../../userpatches/overlay/usr/local/sbin/opibot-runtime-mode)
3. [../../userpatches/overlay/usr/local/sbin/opibot-performance-mode](../../userpatches/overlay/usr/local/sbin/opibot-performance-mode)
4. [../../userpatches/overlay/etc/systemd/system](../../userpatches/overlay/etc/systemd/system)

这些组件是当前二次开发的主热区。