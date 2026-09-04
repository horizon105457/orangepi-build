# RK3588S NPU Path Probe Summary (2026-03-28)

## Raw Output
- /home/horizon/Developments/USC_ws/src/mipi_camera_cpp/docs/rk3588s_npu_path_probe_raw_20260328_204649.log

## Required Conclusion Format

NPU 访问路径：
- B: 走 /dev/dri/renderD*

证据：
- /dev/rknpu* 不存在。
- /dev/dri/renderD128 与 /dev/dri/renderD129 存在，权限组为 render。
- dmesg 出现 `[drm] Initialized rknpu 0.9.8 20240828 for fdab0000.npu on minor 1`，说明 rknpu 通过 DRM 子系统注册。

权限风险：
- 中

证据：
- 当前用户 horizon 在 video 组，但不在 render 组。
- render 节点权限为 `crw-rw---- root render`，若运行时走 render 节点则普通用户可能无访问权限。

运行可用性：
- WARN

证据：
- rknn_demo 与样例模型存在，但执行失败：`error while loading shared libraries: libjpeg.so.62: cannot open shared object file`。
- strace 不存在（NOT_FOUND），无法直接抓取 openat/ioctl 的设备节点访问轨迹。
- debugfs 已挂载，但 `/sys/kernel/debug/rknpu/version` 为 `RKNPU_DEBUG_VERSION_NOT_FOUND`。

建议动作（按优先级）
1. 先补齐用户态运行依赖（至少 libjpeg.so.62 的提供包），再重复最小推理验证。
2. 将执行推理的业务用户加入 render 组，或通过受控 udev 规则下放 render 节点访问权限。
3. 在不安装新工具前提下，使用现有日志与应用自带 verbose 选项确认是否打开 /dev/dri/renderD*。
4. 若允许后续增强诊断，安装 strace 后复测并固定证据链（openat/ioctl 到 render 节点）。
5. 对 debugfs 缺失 rknpu version 进行内核配置核查（是否裁剪了对应 debug 节点导出）。

## Re-Test After Permission Registration

### Re-test Raw Evidence (excerpt)
- `sudo -n usermod -aG render horizon` 返回 `EXIT_CODE=0`
- `getent group render` 变为 `render:x:109:horizon`
- `id horizon` 包含 `109(render)`
- 当前旧会话 `id/groups` 仍未显示 render（会话缓存）
- 新进程 `sudo -n -u horizon id` 与 `sudo -n -u horizon bash -lc "groups"` 均显示 render
- `rknn_demo /usr/share/rknn_demo/mobilenet_ssd.rknn` 仍失败：缺少 `libjpeg.so.62`

### Updated Conclusion
- NPU 访问路径：仍为 B（/dev/dri/renderD*）
- 权限风险：从中等下降到低-中（账号权限已修复，但旧会话需重登或新 shell）
- 运行可用性：仍为 WARN（阻断点从权限侧转为用户态依赖侧）

### Current Blocking Items (Top 3)
1. `libjpeg.so.62` 缺失，导致 `rknn_demo` 无法启动。
2. 当前终端会话未刷新补充组，需要新登录会话才可直接继承 render 组。
3. 由于示例程序未成功启动，尚未在运行态采集到设备节点 open/ioctl 证据链。
