# 鸿蒙开发与构建

`ohos` 分支包含 HarmonyOS 工程，包名为 `com.hibanaw.hizip`，支持 2in1、平板和手机。平台功能由仓库内维护的 [`nativeapi`](../packages/nativeapi/README.md) Flutter 插件实现，原生压缩引擎通过 entry 模块的 CMake 构建。当前平台行为、测试流程和限制见 [HarmonyOS 实现说明](../docs/HARMONYOS.md)。

## 已验证环境

- Flutter OH：`3.41.10-ohos-1.0.1`，Dart 3.11.5，SDK 提交 `adaf911c35`。
- Mac ARM Command Line Tools：26.0.0.621 Beta2，SDK API 26，Node 24.14.1。
- Java：DevEco Studio 自带的 JBR 21。
- 真机：ARM64、API 24，通过无线 hdc 连接。

本分支使用 Dart `^3.11.0`、Flutter `>=3.41.0`，将桌面窗口依赖改为本地维护的 `nativeapi 0.2.7+hizip.1`（桌面 C 绑定固定为 `cnativeapi 0.2.7`）。主分支原有的 Dart 3.13 / Flutter 3.47 要求不能直接用于这一版本的 Flutter OH。桌面窗口 API 已按该依赖版本调整，但本轮没有验证桌面应用运行。

工具链和缓存放在 Git 忽略的 `.toolchains/`，不修改系统 Flutter：

```text
.toolchains/
  flutter-ohos/          Flutter OH SDK
  command-line-tools/    独立 DevEco 工具包
  pub-cache/             依赖缓存
  forui-ohos/            自动生成的 ForUI 兼容副本
```

## 初始化与构建

准备上述 Flutter OH SDK 和 DevEco 工具包后，在项目根目录运行：

```sh
tools/flutter-ohos --version
tools/flutter-ohos doctor -v
tools/flutter-ohos precache --ohos
tools/flutter-ohos pub get
tools/flutter-ohos build hap --release
```

脚本优先使用 `.toolchains/command-line-tools`，否则使用 `/Applications/DevEco-Studio.app/Contents`。`HIZIP_DEVECO_HOME` 和 `HIZIP_JAVA_HOME` 可覆盖工具与 Java 路径。普通 `flutter` 命令仍使用系统 SDK；本分支请通过包装脚本解析依赖和构建。

ForUI 0.21.3 的两处平台枚举分支未覆盖 `ohos`。包装脚本会下载固定版本，复制到本地目录并加入触摸平台回退，再生成忽略的 `pubspec_overrides.yaml`。补丁检查源代码是否符合预期，不修改依赖缓存或 SDK；重新初始化无需手工修改 ForUI。

## 签名与安装

第一次运行包装脚本会从 `ohos/build-profile.template.json5` 生成本地 `ohos/build-profile.json5`。在 DevEco Studio 打开 `ohos/`，进入 Project Structure → Signing Configs，登录华为账号并生成调试签名，然后构建。

本地 `build-profile.json5` 包含签名路径与凭据，已被 Git 忽略。模板不包含签名信息。当前 Release 包使用开发签名供已登记设备测试，并非商店发布签名。

```sh
hdc tconn 192.168.10.184:42447
hdc -t 192.168.10.184:42447 install build/ohos/hap/entry-default-signed.hap
hdc -t 192.168.10.184:42447 shell aa start -b com.hibanaw.hizip -a EntryAbility
```

`hdc` 位于 SDK 的 `default/openharmony/toolchains/`。无线地址与端口可能随设备重新启用调试而变化。

## 文件行为与能力范围

- 使用系统文档选择器打开文件、选择保存位置和解压目标。
- 选择的文件先复制到应用沙箱，压缩引擎仅处理本地路径，公开文档 URI 留在 ArkTS 层。
- 压缩包修改发生在沙箱工作副本中，验证成功后自动写回获授权的系统源文件；写回前检查源文件摘要，避免覆盖其他应用的修改。只有读授权时保持只读，可使用“保存副本”导出。
- 新建压缩包和解压操作完成后，将结果复制到授权的公开位置。
- 应用设置通过 HarmonyOS Preferences 保存，缓存通过原生接口获取。
- 支持窗口控制的设备隐藏系统标题栏，保留系统最小化、最大化/还原与关闭按钮；通过 49vp 装饰高度使按钮与 Flutter 工具栏居中对齐，并按实际按钮矩形预留空间。工具栏提供拖动、双击最大化/还原，系统关闭按钮等待后台任务与缓存清理完成；隐藏标题栏失败时保留系统装饰。
- 压缩包内文件“打开”调用系统默认应用；未配置默认项时由系统选择可用应用。外部编辑使用保留文件名及后缀的独立私有目录，修改经确认后写回归档并同步系统源文件。关闭时同步最后的修改，再清理可安全删除的编辑副本。
- 桌面文件剪贴板、跨应用拖拽、Quick Look 与 macOS 文件关联尚未移植。

鸿蒙原生构建包含 zlib，并从固定源码交叉编译 bzip2、XZ/liblzma 和 Mbed TLS。已验证 ZIP、7z、XZ、BZip2、ZIP AES-256 与加密固实 RAR5。其他算法仍以运行时能力查询为准。系统选择器的实际点击与公共目录批量合并、覆盖及链接导出仍有验收或实现限制，详见实现说明。

## 验证

最初迁移时，静态分析及启用宿主原生引擎后的 128 项测试通过，签名 Release 包可安装并启动。后续已补充系统源文件写回、外部编辑和图标回归；最新迁移记录见实现说明。插件由 Flutter 自动注册。

```sh
tools/flutter-ohos analyze --no-pub lib test integration_test \
  packages/hizip_native packages/nativeapi/lib packages/nativeapi/test
# 使用已构建的宿主原生库执行完整原生回归：
HIZIP_NATIVE_LIBRARY=/path/to/libhizip_native.dylib \
  tools/flutter-ohos test --no-pub test packages/nativeapi/test
# 构建真机自检入口，安装、启动后通过 HiLog 查看 HIZIP_DEVICE_SMOKE：
tools/flutter-ohos build hap --debug -t integration_test/ohos_native_smoke.dart
```

真机自检只处理自建的临时文件，结束后启动正常应用。完成自检后重新构建并安装默认 Release 入口。

`nativeapi` 的窗口增量实现提供 `NativeHostWindow.changes`、`moveTo`、`resize` 与最大尺寸约束；文件接口新增 `openFile`、`openDirectory` 和支持目录，选择器支持扩展名过滤。接口约定与示例见 [插件说明](../packages/nativeapi/README.md)。本轮插件 20 项测试与新增代码静态分析通过，签名 Release 包构建成功。

自检新增支持目录、窗口事件订阅、窗口参数、导出沙箱路径、路径穿越和文件后缀校验。若设备禁止创建用于检查的符号链接，该检查记录在报告的 `skipped` 数组中。文档选择器、目录复制和改变窗口位置/尺寸的交互仍需单独验收。

本轮 API 24 真机自检 15 项通过，符号链接检查因设备返回 `Permission denied` 跳过；原生错误在选择器弹出前正确返回。

默认应用打开的专项自检可按以下方式构建；安装启动后会创建测试 ZIP 并通过 `ArchiveService.open` 打开其中的中文文本文件。HiLog 中的 `HIZIP_DEFAULT_OPEN` 记录路径校验和系统启动结果，实际文档显示需在设备上确认。测试保留缓存文件供外部应用读取，完成后重新安装正常 Release 入口。

```sh
tools/flutter-ohos build hap --release --no-pub \
  -t integration_test/ohos_native_smoke.dart \
  --dart-define=HIZIP_SMOKE_OPEN_DEFAULT=true
```
