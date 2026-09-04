# RK3588S System Survey Summary (2026-03-28)

## Raw Output Log
- /home/horizon/Developments/USC_ws/src/mipi_camera_cpp/docs/rk3588s_system_survey_raw_20260328_full_202401.log

## Final Status Table

| Item | Status | Evidence |
|---|---|---|
| NPU 驱动状态 | WARN | dmesg 出现 `[drm] Initialized rknpu 0.9.8 20240828`，但 `/dev/rknpu*` 不存在，仅见 `/dev/mali0`。 |
| NPU Runtime 状态 | WARN | `/usr/lib/librknnrt.so` 存在，`strings` 显示 `librknnrt version: 2.3.0`；但 `/sys/kernel/debug/rknpu/version` 返回 `RKNPU_VERSION_NOT_FOUND`。 |
| GPU 驱动状态 | OK | dmesg 显示 `mali ... Probed as mali0`，并且 `/dev/mali0`、`libmali.so` 存在。 |
| OpenCL 状态 | OK | `ldconfig -p` 可见 `libOpenCL` 与 `libMaliOpenCL`；`/etc/OpenCL/vendors/mali.icd` 存在且内容为 `libMaliOpenCL.so.1`；`clinfo` 能返回平台/设备信息。 |
| 版本匹配风险 | 中 | RKNN runtime 为 2.3.0，内核 rknpu 为 0.9.8（20240828）；驱动已初始化但设备节点缺失，存在用户态/内核态不完全对齐或 udev/权限链路异常风险。 |

## Health Check Decisions (G)
1. `/dev/rknpu*` 与 `/dev/mali*`：仅 `mali` 存在，`rknpu` 缺失。
2. `librknnrt` 与 `libmali`：均存在。
3. OpenCL ICD：可见且有效（`mali.icd -> libMaliOpenCL.so.1`）。
4. dmesg 持续 fault/timeout：看到 `rk3x-i2c ... timeout`，未见 NPU/GPU 持续 fault 循环。
5. cmdline 是否含 cma：包含 `cma=128M`。

## Recommended Actions (Priority)
1. 核实 rknpu 设备节点创建链路：检查 devtmpfs/udev 是否生成 `/dev/rknpu*`（仅只读排查）。
2. 在应用进程上下文验证组权限：确认运行用户是否在 `video` 组（当前 `mali0` 与 dma_heap 走 `video` 组权限）。
3. 使用最小 RKNN demo 做一次 runtime 调用探测，观察是否因设备节点缺失直接失败。
4. 若需更深排查，补采 `ls -l /sys/class/drm` 与 `ls -l /dev/dri`（只读）确认 rknpu 映射路径是否改名到 drm render 节点。
5. 复核 RKNN toolkit 与 runtime 主版本对齐策略（当前 runtime=2.3.0，建议与模型编译链一致）。
6. 对 i2c timeout 进行独立硬件链路排查，避免误判为 NPU/GPU 稳定性问题。
7. 维持当前 hold 包策略并记录基线版本，后续升级时先做灰度验证。
8. 若业务依赖零拷贝链路，增加一次 dma_heap 分配与跨模块导入的健康测试并留存日志。
