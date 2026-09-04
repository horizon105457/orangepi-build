# customize-image 职责审计

日期：2026-04-10

对象：[../../userpatches/customize-image.sh](../../userpatches/customize-image.sh)

结论：

这是当前 build 仓最重要的二次开发主入口，也是当前最大的职责膨胀点。

## 1. 事实概况

当前函数族至少包含以下 6 类职责：

1. 通用工具：APT、下载、权限修复
2. overlay 合并：白名单、校验、rsync、权限修复
3. 软件安装：ROS2、OpenCV、NoMachine、mDNS
4. 运行时与 boot 策略：RT 参数、service enable、权限设置
5. 文档与提示：运行手册同步、CM5-CC overlay hints
6. 历史/可选路径：OpenMediaVault、桌面附加路径

## 2. 当前职责分组

### A 组：构建环境与通用工具

函数：

1. `SetOwnerModeIfFileExists`
2. `AptUpdate`
3. `AptInstall`
4. `AptInstallBestEffort`
5. `AptFixBrokenInstall`
6. `DownloadFile`
7. `EnsureCustomizeImageContext`

判断：

1. 这些是底层通用能力。
2. 应继续留在该文件或被抽成单独库，但当前不应先动。

### B 组：overlay 合并引擎

函数：

1. `OverlayResolveWhitelist`
2. `OverlayValidateInputs`
3. `OverlayPrepareRsyncOptions`
4. `OverlayMergeFull`
5. `OverlayMergePartial`
6. `OverlayPostMergePermissionsFix`
7. `MergeOverlayToRoot`

判断：

1. 这是一个相对完整、边界较清晰的子系统。
2. 适合在后续阶段二被视为独立职责块。
3. 当前不建议继续往这一组里混入业务安装逻辑。

### C 组：基础软件安装

函数：

1. `InstallMDNS`
2. `InstallROS2Humble`
3. `InstallOpenCV`
4. `InstallOptionalNoMachine`

判断：

1. 这些函数本质上是“镜像内容安装器”。
2. 与 overlay 合并、RT 策略和文档下发不是同一职责层。
3. 后续阶段二应把它们视为单独分组，而不是继续散落在主流程中。

### D 组：加速/NPU 辅助能力

函数：

1. `EnsureRenderGroupAccess`
2. `InstallAccelHealthcheck`

判断：

1. 这是 hpw 较新的集成补丁层。
2. 与 RT 主线关系有限，但与目标镜像可用性相关。
3. 后续需要被标记为“平台能力补丁”，避免继续侵入主流程判断逻辑。

### E 组：运行时与 boot 编排

函数：

1. `FixRuntimeRTTunePermissions`
2. `DisableDnsmasqByDefault`
3. `RemoveConsoleAutologinOverrides`
4. `ConfigureRTKernel`

判断：

1. 这是整个文件里最关键、也最容易出错的部分。
2. 它把 boot profile、runtime service enable、兼容壳探测都混在一起。
3. 当前应优先被审计，而不是直接重构。

### F 组：文档与板级提示

函数：

1. `InstallRuntimeDeploymentGuide`
2. `InjectCm5CcOverlayHints`

判断：

1. 这是相对低风险的辅助层。
2. 边界清晰，适合作为后续工程整理的低风险试点区。

## 3. 主流程审计

主流程 [Main](../../userpatches/customize-image.sh#L964) 当前顺序为：

1. 校验 chroot 上下文
2. 合并 overlay
3. 修复默认权限与服务默认值
4. 按发行版分发 RT 配置与软件安装
5. 同步运行文档
6. 注入 CM5-CC overlay hints

结论：

1. 这个顺序本身是合理的。
2. 真正的问题不是顺序，而是同一文件承担了过多横切职责。

## 4. 当前技术债

### 债务 1

`ConfigureRTKernel` 过重。

它同时负责：

1. 读取兼容配置
2. 生成 boot args
3. 写 `/boot/orangepiEnv.txt`
4. enable/disable 多种 service
5. 建 realtime 组

### 债务 2

安装器与平台编排器混在同一文件。

### 债务 3

历史/可选路径没有被明确标记为“非主链”。

## 5. 阶段二建议

当前建议只做以下非行为性整理：

1. 在文档中冻结 6 组职责边界。
2. 标记哪些函数属于主链，哪些属于可选链。
3. 标记 `ConfigureRTKernel` 为优先审计块。
4. 不直接拆函数，不改变主流程顺序。

## 6. 阶段三候选优化点

1. 让 boot profile 下发与 service enable 解耦。
2. 让安装器逻辑与运行时编排逻辑解耦。
3. 将文档/提示逻辑从主链中进一步独立。