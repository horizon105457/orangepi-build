# 系统诊断文档

日期：2026-03-13

目标：为下一次离线编译和镜像修复提供基于当前运行系统的故障清单、根因判断、修复优先级与回归验证清单。

## 1. 环境概况

- 系统版本：Ubuntu 22.04.5 LTS，Orange Pi Jammy 定制镜像
- 内核版本：6.1.99-rt36-rockchip-rk3588-rt
- 平台：RK3588 系列，设备树文件为 rockchip/rk3588s-orangepi-cm5-tablet.dtb
- 启动附加参数：
  - cma=128M
  - nohz_full=6,7
  - rcu_nocbs=6,7
  - isolcpus=managed,domain,6,7
  - irqaffinity=0-5

相关配置来源：

- /etc/os-release
- /boot/orangepiEnv.txt
- /boot/config-6.1.99-rt36-rockchip-rk3588-rt

底板说明：

- 当前 SoC 搭配的外设底板不是最终产品底板。
- 因此一部分外设探测失败、I2C 器件缺失、PCIe 或显示链路不匹配，可能是板卡组合不一致带来的预期噪声，而不一定是镜像本身的缺陷。
- 后续分析时应优先区分两类问题：
   - 与具体底板绑定的外设描述不匹配
   - 与镜像构建、服务编排、用户配置、权限和默认策略有关的系统性问题

## 2. 执行摘要

当前系统可以进入桌面并联网，但启动过程中仍存在明确的系统级集成错误。已经确认的高优先级问题有 4 类：

1. runtime-rt-tune 服务无法执行，原因是脚本权限和安装属性错误。
2. systemd-sysctl 失败，原因是 RT 调优配置中包含 4 个当前内核不存在的 sysctl 键。
3. dnsmasq 与 systemd-resolved 同时争抢 53 端口，DNS 架构冲突。
4. 控制台自动登录仍写死为 orangepi，系统中该用户不存在，导致反复认证失败日志。

除此之外，还有一批更偏底层的硬件描述或设备树集成问题，包括 HDMI DDC/EDID 失败、一个 PCIe host 初始化失败、RTC/触摸屏 I2C 探测失败、OPTEE/SCMI 协议异常、若干 VOP/VENC/DMC regulator 与 OPP 相关错误，以及一个 USB 调试设备在总线中反复断开重连。

考虑到当前不是正式产品底板，上述硬件相关报错中有一部分很可能属于“板卡不匹配噪声”。但这不影响对镜像本身问题的结论：当前镜像仍处于“功能可用但系统集成不干净”的状态，不建议直接作为稳定基线继续叠加功能。

## 3. 高优先级问题

### 3.1 runtime-rt-tune 服务无法启动

现象：

- systemctl --failed 中存在 runtime-rt-tune.service
- systemd 状态为 203/EXEC
- 报错为 Permission denied

直接证据：

- 服务文件：/etc/systemd/system/runtime-rt-tune.service
- 脚本文件：/usr/local/sbin/runtime-rt-tune

关键观察：

- 服务通过 ExecStart=/usr/local/sbin/runtime-rt-tune 直接执行脚本
- 当前文件属性为：-rw-rw-r-- 1 horizon sudo ... /usr/local/sbin/runtime-rt-tune
- 脚本没有执行位
- 脚本所有者还是 horizon:sudo，而不是 root:root

根因判断：

- 这是镜像构建或打包阶段的文件权限错误，不是脚本逻辑错误。
- 即使脚本内容本身可执行，systemd 也会因为缺少 x 位而直接在 EXEC 阶段失败。

离线修复建议：

1. 在 rootfs 打包阶段把 /usr/local/sbin/runtime-rt-tune 的属主改为 root:root。
2. 权限改为 0755。
3. 检查该脚本是否是通过 overlay、fakeroot、cp 命令或 install 命令放入镜像；优先改成 install -m 0755 -o root -g root。
4. 如果该脚本确实属于镜像内置组件，建议从 /usr/local 迁移到 /usr/sbin 或通过 deb 包统一安装，避免“开发阶段手工复制文件权限不稳定”。

额外建议：

- 脚本当前会 stop/disable irqbalance，并对网卡队列、qdisc、IRQ 亲和性做强制设置。
- 在下一次镜像修复时，建议给它增加以下前置检查：
  - 网卡 eth0 是否存在
  - tc、ethtool、cpupower 是否已安装
  - RT CPU 列表与当前 CPU 数量是否匹配
  - 对 /sys/class/net/${NIC_DEV}/queues/* 的写入前先判断路径存在

### 3.2 systemd-sysctl 启动失败

现象：

- systemctl --failed 中存在 systemd-sysctl.service
- service 状态为 status=1/FAILURE

直接证据：

- 配置文件：/etc/sysctl.d/99-rt-kernel-tuning.conf

逐项校验结果：

- 存在的键：
  - kernel.sched_rt_runtime_us
  - kernel.sched_rt_period_us
  - vm.nr_hugepages
  - vm.swappiness
  - vm.max_map_count
  - vm.mmap_min_addr
  - net.core.default_qdisc
  - net.core.rmem_max
  - net.core.wmem_max
  - net.ipv4.tcp_rmem
  - net.ipv4.tcp_wmem
  - kernel.msgmax
  - kernel.msgmnb
  - kernel.msgmni
  - kernel.sysrq
  - kernel.timer_migration
  - kernel.kptr_restrict

- 不存在的键：
  - kernel.sched_domain_debug
  - kernel.sched_migration_cost_ns
  - kernel.sched_min_granularity_ns
  - vm.transparent_hugepage

根因判断：

- systemd-sysctl 失败不是 service 本身问题，而是 RT 调优配置中混入了当前内核不支持的 sysctl 键。
- 其中 vm.transparent_hugepage 尤其明显，它不是当前系统支持的 /proc/sys 接口。
- 另外 3 个 scheduler 调优项虽然常见于某些内核版本或调试配置，但在这版内核运行时并没有暴露对应节点。

离线修复建议：

1. 从 /etc/sysctl.d/99-rt-kernel-tuning.conf 中移除以下 4 项：
   - kernel.sched_domain_debug
   - kernel.sched_migration_cost_ns
   - kernel.sched_min_granularity_ns
   - vm.transparent_hugepage
2. 若确实需要这些调优项，不要直接假设它们存在，改为：
   - 在启动脚本里做存在性判断后再写入；或
   - 由构建系统根据内核版本和配置模板按条件生成 sysctl 文件。
3. 对 transparent hugepage 的需求单独处理：
   - 先确认内核是否真正启用了 THP；当前 config 中只有 CONFIG_HAVE_ARCH_TRANSPARENT_HUGEPAGE=y，未看到 CONFIG_TRANSPARENT_HUGEPAGE=y。
   - 如果下次内核仍不启用 THP，就不要在 sysctl 里保留任何 THP 配置。
   - 如果下次启用 THP，再根据实际接口决定走 /sys 或内核参数，不要直接写 vm.transparent_hugepage。

### 3.3 dnsmasq 与 systemd-resolved 冲突

现象：

- systemctl --failed 中存在 dnsmasq.service
- 报错：failed to create listening socket for port 53: Address already in use

直接证据：

- 53 端口当前由 127.0.0.53:53 占用
- systemd-resolved 正常运行
- /etc/dnsmasq.conf 仍是默认模板

根因判断：

- 当前镜像同时启用了 systemd-resolved 和 dnsmasq，但没有做端口分工或级联配置。
- 结果是 systemd-resolved 先绑定 127.0.0.53:53，dnsmasq 再启动时直接失败。
- 这不是 dnsmasq 配置语法错误，而是系统架构冲突。

离线修复建议：

必须二选一，不能让两个服务默认都争夺本机 53：

方案 A：保留 systemd-resolved，禁用 dnsmasq

- 适用于系统只需要普通客户端 DNS 解析，不需要本机 DHCP/TFTP/DNS 缓存服务。
- 构建阶段直接禁用 dnsmasq.service。

方案 B：保留 dnsmasq，关闭 resolved 的 stub listener

- 如果系统需要本地 DNS/DHCP/TFTP，就应以 dnsmasq 为主。
- 需要关闭 systemd-resolved 的 stub listener，或彻底禁用 resolved，并确保 /etc/resolv.conf 指向正确的上游配置。

方案 C：两者级联，但显式分工

- 例如 dnsmasq 不监听 53，或只监听特定接口。
- 这类方案可以做，但不建议作为当前镜像的默认状态，除非你非常明确需要它。

建议：

- 如果目标是机器人/嵌入式终端而不是网关，优先方案 A，减少维护面。

### 3.4 控制台自动登录仍引用 orangepi 用户

现象：

- journalctl 中反复出现：could not identify user (from getpwnam(orangepi))
- /etc/passwd 中并不存在 orangepi 用户，当前实际用户为 horizon

直接证据：

- /lib/systemd/system/getty@.service.d/override.conf
- /lib/systemd/system/serial-getty@.service.d/override.conf

当前覆盖内容明确写死：

- ExecStart=-/sbin/agetty --noissue --autologin orangepi %I $TERM

根因判断：

- 这是镜像继承自 Orange Pi 默认模板的 getty 自动登录遗留项。
- 系统已经把图形自动登录改成了 horizon，但控制台和串口 getty 仍然试图自动登录 orangepi。
- 所以每次控制台 login/getty 拉起时都会反复失败并刷日志。

离线修复建议：

1. 删除这两个 override，恢复 systemd 默认 getty 行为；这是最干净的方案。
2. 如果确实需要自动登录，改为在镜像构建阶段用真实默认用户动态生成，而不是硬编码 orangepi。
3. 不建议同时对 tty1 和 serial-getty 默认启用自动登录，尤其是在机器人或量产镜像里。

## 4. 中优先级问题

说明：

- 本节有较高概率混入“非正式底板导致的预期报错”。
- 如果某个功能在正式产品底板上不存在，最优做法不是继续兼容当前测试底板，而是在最终镜像对应的 DTS 或 overlay 中只保留正式硬件需要的节点。
- 因此本节条目更适合用于“裁剪和收敛设备树”，而不一定都应理解为必须在当前测试底板上修通。

### 4.1 HDMI DDC/EDID 反复失败

现象：

- dwhdmi-rockchip fde80000.hdmi: i2c read time out!
- ddc read failed offset:0x1
- failed to get edid

影响判断：

- 说明 HDMI DDC 通道无法稳定读取显示器 EDID。
- 但系统仍能显示桌面，说明显示路径并非完全不可用，可能是在使用固定模式、缓存模式、另一路显示输出，或热插拔场景下部分成功。

可能原因：

1. 设备树中的 HDMI DDC/HPD 引脚、I2C 复用或 GPIO 配置不正确。
2. 当前外接显示链路不是标准直连 HDMI，而是带转换器或 Type-C AV 适配器，导致 DDC 不稳定。
3. 物理线材或供电问题。

离线修复建议：

1. 复核 fde80000.hdmi 对应 DTS 节点的 ddc-i2c-bus、hpd-gpios、pinctrl。
2. 如果当前产品形态主要走 eDP/MIPI/固定面板，且 HDMI 不是必需输出，可考虑禁用未使用 HDMI 节点，减少错误日志。
3. 如果 HDMI 是主输出，下一版镜像需要用目标显示器或目标适配器链路做冷启动 EDID 回归测试。

### 4.2 PCIe host 初始化失败

现象：

- rk-pcie fe190000.pcie: PCIe Link Fail, LTSSM is 0x3
- rk-pcie fe190000.pcie: failed to initialize host

影响判断：

- 表示至少有一个 PCIe root port 初始化失败。
- 如果该口在产品设计里未接设备，可视为应通过 DTS 禁用的闲置节点。
- 如果该口有设计用途，则当前设备树、reset、regulator、clock 或参考时钟链路存在问题。

离线修复建议：

1. 确认 fe190000.pcie 对应的是哪一路 PCIe 控制器。
2. 若硬件未接外设，直接在 DTS 中禁用该节点。
3. 若应接设备，则检查：
   - reset-gpios
   - vpcie3v3-supply / vpcie1v8-supply
   - refclk
   - PERST# 时序
   - lane/phy 复用是否和 USB/Type-C 冲突

### 4.3 RTC、触摸屏和若干 I2C 外设探测失败

已观察到：

- Goodix-TS 1-0014: I2C communication failure: -6
- rtc-hym8563: probe of 7-0051 failed with error -110
- ES8323 3-0011: i2c recv Failed

影响判断：

- 这些都是典型的“设备树声明了设备，但板上该器件不在线、供电未起、复位脚不对、I2C 地址/总线错误”的表现。
- 如果这块板型并不一定带这些器件，就不该在通用 DT 中默认全部启用。

离线修复建议：

1. 复核当前板型是否真的带 Goodix 触摸、HYM8563 RTC、ES8323 音频 codec。
2. 未实装的器件直接在 DTS 中设为 disabled。
3. 已实装但探测失败的器件，逐项复核：
   - I2C 总线编号
   - 设备地址
   - reset-gpios / irq-gpios
   - 电源 regulator
   - 上电时序

### 4.4 OPTEE / SCMI 相关异常

已观察到：

- arm-scmi firmware:scmi: Failed. SCMI protocol 17 not active.
- optee: probe of firmware:optee failed with error -22

影响判断：

- 这说明内核打开了相关支持，但固件链路并未提供匹配的运行环境，或设备树/secure world 配置不一致。
- 如果镜像目标不依赖 OPTEE/SCMI，则这些能力不应半启用。

离线修复建议：

1. 如果产品不依赖 TEE/SCMI，考虑在设备树或内核配置里关闭对应节点/功能。
2. 如果依赖，则必须同时核对：
   - BL31 / Trust firmware
   - OPTEE OS
   - kernel config
   - DTS 中 firmware/optee/scmi 节点

### 4.5 VOP/VENC/DMC regulator 与 OPP 初始化不完整

已观察到：

- rockchip-vop2 ... no regulator (vop) found
- mpp_rkvenc2 ... no regulator (venc) found
- failed to init opp info / failed to add venc devfreq
- rockchip-dmc: probe of dmc failed with error -1

影响判断：

- 这些问题一般说明设备树里的 regulator/opp/devfreq 描述不完整或与当前板级电源树不匹配。
- 轻则导致动态调频失效，重则造成显示、多媒体编码性能和稳定性异常。

离线修复建议：

1. 复核 VOP、VENC、DMC、GPU、NPU 相关 supply 节点。
2. 检查对应 OPP table 是否完整挂接。
3. 若某些功能块在当前产品根本不用，可考虑先在 DTS 里关闭，先换取干净启动日志。

## 5. 额外值得继续诊断的内容

以下项目即使和当前测试底板无关，也仍然值得继续检查，因为它们直接影响镜像质量、可维护性和后续量产收敛。

### 5.1 启用服务与默认策略收敛

目标：确认镜像里哪些服务应该默认启用，哪些只是开发阶段残留。

建议检查：

- systemctl list-unit-files --state=enabled
- /etc/systemd/system
- /lib/systemd/system/*.d
- /etc/lightdm
- /etc/default

重点关注：

- 是否还有为开发调试保留的自动登录、串口登录、firstrun、硬件优化脚本
- 是否有服务既被启用又无明确产品用途
- 是否存在由 Orange Pi 基础镜像继承但对正式产品无意义的默认服务

### 5.2 启动时间与启动链依赖

目标：在功能之外，优化启动时序并发现隐藏的依赖问题。

建议检查：

- systemd-analyze blame
- systemd-analyze critical-chain
- systemd-analyze plot

重点关注：

- 哪些服务阻塞图形界面或网络就绪
- runtime-rt-tune 这类脚本是否放在了过早或过晚的阶段
- 是否有 timeout 很长但最终失败的服务拖慢启动

### 5.3 用户态包与镜像内容最小化

目标：确认镜像是否带入了不需要的软件包、演示包或开发包。

建议检查：

- dpkg -l
- apt-mark showmanual
- /usr/local
- /opt

重点关注：

- 开发工具、调试包、测试脚本是否被错误带入量产镜像
- /usr/local 下是否存在手工放入、未纳入包管理的文件
- 图形环境、网络工具、硬件工具是否超出实际产品需求

### 5.4 内核模块、固件与设备树的一致性

目标：确认内核配置、设备树、模块和固件是同一套假设，没有“半启用”状态。

建议检查：

- lsmod
- /lib/modules/$(uname -r)
- /lib/firmware
- /boot/dtb 和实际加载的 dtb
- initramfs 内容

重点关注：

- 内核启用了但板级没有配套固件或设备树节点的功能
- 设备树声明了但固件或模块未就绪的功能
- 正式产品底板需要的外设是否已进入最终 dtb，而不是依赖临时 overlay

### 5.5 网络命名、路由和开机联网策略

目标：确认网络行为对正式产品是可预测的。

建议检查：

- ip -br addr
- ip route
- NetworkManager 连接配置
- /etc/NetworkManager
- /etc/netplan
- resolvectl status

重点关注：

- 网卡命名是否稳定
- WiFi 与有线优先级是否符合产品预期
- DNS、NTP、联网恢复策略是否一致
- 是否残留测试环境 WiFi、静态 IP 或调试网络配置

### 5.6 日志噪声与真正故障的分层

目标：让启动日志有足够信噪比，便于后续发现真正异常。

建议检查：

- journalctl -b -p warning
- dmesg -T
- 高频重复日志来源

重点关注：

- 将“底板不匹配的预期错误”与“镜像一定要修的问题”分层
- 对正式产品无意义的节点直接禁用，减少重复日志
- 避免像 HDMI DDC、错误 autologin、重复 USB 重连这类日志淹没有价值的故障信息

### 5.7 电源、温度和频率策略

目标：确认镜像默认功耗和调频策略与产品目标一致。

建议检查：

- cpufreq governor 默认值
- thermal zone 行为
- devfreq 策略
- zram、swap、journald 持久化策略

重点关注：

- RT 场景和普通桌面场景是否混用了一套策略
- 温控与性能上限是否合理
- 当前底板不匹配时的供电问题不要误判成最终产品问题

### 5.8 首次启动和账户初始化流程

目标：确保镜像第一次启动时不会留下旧模板用户名、默认口令或错误引导流程。

建议检查：

- /boot/orangepi_first_run.txt.template
- /usr/lib/orangepi/orangepi-firstrun-config
- /usr/lib/orangepi/orangepi-firstlogin
- getty、lightdm、AccountsService 相关配置

重点关注：

- 默认用户生成逻辑是否与实际镜像策略一致
- 是否还残留 orangepi 这类模板用户名
- 图形自动登录、串口自动登录、首登脚本之间是否互相冲突

## 6. 低优先级但建议处理的问题

### 5.1 dw-apb-uart DMA 回退到中断模式

已观察到：

- of_dma_request_slave_channel: dma-names property of node '/serial@febc0000' missing or empty
- dw-apb-uart febc0000.serial: failed to request DMA, use interrupt mode

影响判断：

- 不是致命问题，但说明串口节点设备树不完整。
- 若串口吞吐或实时性敏感，建议修好。

离线修复建议：

- 为对应 UART 节点补全 dmas 和 dma-names，或明确不使用 DMA 并移除相关期望。

### 5.2 USB 调试设备反复重连

现象：

- Bus 03 上的 Espressif USB JTAG/serial debug unit 持续 disconnect/reconnect

影响判断：

- 这更像外设链路或 Hub 稳定性问题，而不是内核主控整体失效。
- 但它会污染日志，也可能影响同一 Hub 下其他低速设备的枚举稳定性。

离线修复建议：

1. 优先排查物理链路和供电。
2. 若该设备不是默认量产链路的一部分，建议在系统验证时先移除，避免误判平台 USB 稳定性。

## 7. 启动参数风险提示

当前 /boot/orangepiEnv.txt 中启用了比较激进的 RT 启动参数：

- nohz_full=6,7
- rcu_nocbs=6,7
- isolcpus=managed,domain,6,7
- irqaffinity=0-5

这些参数本身不一定错误，但会显著提高系统调试复杂度。建议策略：

1. 在下一版镜像中先保证“基础硬件与服务全部无错误启动”。
2. 之后再逐项恢复 RT 隔离参数，并记录每一项引入后的行为差异。
3. 若目标是量产镜像，建议保留一个“基础稳定配置”和一个“RT 优化配置”，不要只维护一套混合镜像。

## 8. 离线修复优先级清单

### P0：下一版镜像必须修复

1. 修正 /usr/local/sbin/runtime-rt-tune 的属主和执行权限。
2. 删除 /etc/sysctl.d/99-rt-kernel-tuning.conf 中 4 个当前内核不存在的键。
3. 在 dnsmasq 与 systemd-resolved 之间做单一默认方案选择。
4. 删除 getty 和 serial-getty 中写死 orangepi 的自动登录 override。

### P1：下一版镜像强烈建议修复

1. 清理或修正 HDMI DDC/EDID 失败。
2. 处理 fe190000.pcie 初始化失败。
3. 对未实装的 I2C 外设节点做 DTS 精简，避免无意义 probe 失败。
4. 整理 OPTEE/SCMI 的启用策略。
5. 补全 VOP/VENC/DMC 相关 regulator 与 OPP 描述。

注：

- 如果这些报错仅来自当前测试底板而正式产品底板没有对应器件，则目标应调整为“对正式产品底板生成更干净的 DTS/overlay 组合”，而不是强行让测试底板的所有外设都工作。

### P2：后续优化项

1. 修复 UART DMA 描述。
2. 评估 USB Hub 与调试设备的稳定性。
3. 重新审视 RT 启动参数与运行时调优脚本的协同设计。
4. 收敛默认启用服务、首次启动流程和镜像包集。
5. 做一次正式底板导向的启动时间和日志噪声优化。

## 9. 下次刷机后的验收清单

建议在下一版镜像首次启动后执行以下检查：

```bash
systemctl --failed --no-pager --plain
journalctl -b -p err..alert --no-pager
dmesg -T | grep -Ei 'error|fail|failed|timeout|denied|BUG|Oops'
ss -lntup '( sport = :53 )'
systemctl status dnsmasq.service systemd-resolved.service --no-pager -l
systemctl status runtime-rt-tune.service systemd-sysctl.service --no-pager -l
grep -Rni 'autologin' /lib/systemd/system/getty@.service.d /lib/systemd/system/serial-getty@.service.d /etc/lightdm 2>/dev/null
```

理想结果：

- systemctl --failed 为空
- 不再出现 getpwnam(orangepi) 相关日志
- 不再出现 dnsmasq 端口冲突
- runtime-rt-tune 正常执行
- systemd-sysctl 不再失败
- 在正式产品底板上，关键硬件日志中不再有大量重复的 HDMI、PCIe、I2C 探测错误

## 10. 直接涉及的文件

- /etc/systemd/system/runtime-rt-tune.service
- /usr/local/sbin/runtime-rt-tune
- /etc/sysctl.d/99-rt-kernel-tuning.conf
- /etc/dnsmasq.conf
- /lib/systemd/system/getty@.service.d/override.conf
- /lib/systemd/system/serial-getty@.service.d/override.conf
- /etc/lightdm/lightdm.conf.d/22-orangepi-autologin.conf
- /boot/orangepiEnv.txt
- /boot/config-6.1.99-rt36-rockchip-rk3588-rt

扩展诊断时建议重点关注：

- /etc/systemd/system
- /lib/systemd/system/*.d
- /usr/lib/orangepi
- /etc/NetworkManager
- /etc/netplan
- /usr/local
- /boot/dtb
- /lib/modules
- /lib/firmware

## 11. 结论

当前镜像的问题主要不是“单个包坏了”，而是多个层面的系统集成还没有收敛：

- 有明显的打包权限错误
- 有运行时配置与内核能力不匹配
- 有默认服务架构冲突
- 有默认用户名模板残留
- 有若干设备树或板级外设描述未按实际硬件裁剪

同时需要明确：当前测试环境使用的不是正式产品底板，因此一部分外设报错本身并不需要在这块测试底板上被“修通”。更合理的目标是基于正式产品底板重新收敛 DTS、overlay、默认服务与镜像内容，避免把测试底板噪声误当成量产缺陷。

建议下一次离线修复以“先清空启动失败项和重复错误日志”为目标，不要先继续叠加新功能。只要先把 P0 和大部分 P1 解决，这套镜像的可维护性会明显提高。