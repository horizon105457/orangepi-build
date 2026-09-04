**OrangePi CM5-CC design — 可按需启用外设（不修改上游）**

目标
----
- 在保持与 `orangepicm5-tablet` 功能等价的前提下，使部分外设在默认情况下不启用（减少 probe 报错与功耗）。
- 编译后仍可按需开启外设（通过 boot overlay 或配置文件），并支持运行时通过修改 `/boot/orangepiEnv.txt` 并重启来切换。

方案概要
--------
1. 在当前工作区新增 BOARD 配置：`external/config/boards/orangepicm5-cc.conf`。
2. 在内核源提供新的 DTS（基于 tablet 的拷贝 `rk3588s-orangepi-cm5-cc.dts`），将默认应禁用的节点设置为 `status = "disabled"`。
3. 为关键外设提供 overlay 片段（`enable-*` / `disable-*`）：DSI、触控、音频 PA、Wi‑Fi/BT、可选 CSI 摄像头等。
4. 将 DTS/overlay/defconfig 变更以补丁形式保存在 `external/patch/` 或提交到内核 fork；本仓库会在构建时应用补丁或拉取你的 fork。
5. 在镜像层（`userpatches/`）提供默认 `orangepicm5-cc` 配置（已添加 `userpatches/config-orangepicm5-cc.conf`），并保持 `IGNORE_UPDATES=""` 以便拉取上游补丁/分支。

可行性与限制
---------------
- 可行性：高。Linux DT/overlay 与 U-Boot 的 overlay 机制支持在引导时加载 dtbo，修改 `/boot/orangepiEnv.txt` 并重启即可切换设备树行为，无需重新编译内核。
- 限制：某些硬件（特定驱动）可能要求在内核构建时启用对应驱动模块；需要在 defconfig 中启用通用驱动支持（模块化优先）。
- 风险：如果某些驱动不能以模块形式存在（必须内建），则无法在运行时禁用；需在内核 defconfig 中确保这些驱动为可模块化或提供安全禁用片段。

执行优先级（建议）
-----------------
1. 把 DSI（panel + backlight）和触摸控制器在新 DTS 中设为 `disabled`。
2. 为触摸、DSI、音频 PA 写 `enable-*` overlay（设置节点为 `okay` 并配置引脚）。
3. 确保 I2C/SPI/CAN 的 pinctrl 条目以 overlay 可修改的方式声明（使用 pinctrl fragment 指向可覆盖的 phandles）。
4. 将 CSI/DSI 的硬件复用和引脚说明写成可 overlay 覆盖的结构，确保运行时可通过 overlay 修改引脚与 status。
