# HiZip nativeapi

这是 HiZip 在仓库内维护的 `nativeapi` Flutter 插件，基于上游 `nativeapi 0.2.7`，版本为 `0.2.7+hizip.1`。应用通过 path dependency 使用此目录，不依赖 pub.dev 上 nativeapi 的自动升级。

上游项目：[libnativeapi/nativeapi-flutter](https://github.com/libnativeapi/nativeapi-flutter)。上游代码保留原 MIT [LICENSE](LICENSE)。桌面 C/FFI 实现仍来自固定版本的 `cnativeapi 0.2.7`，本轮没有 fork 其 C++ 实现。

## 已维护的接口

| 接口 | 能力 | 平台 |
| --- | --- | --- |
| `Window` / `WindowManager` 等上游接口 | 桌面窗口、菜单等现有 FFI 能力 | 保留上游桌面实现 |
| `NativeDocuments` | 单文件/多文件选择、目录导入、保存位置、结果导出、默认应用打开 | 鸿蒙原生文档选择器与 Ability；选择器在其他平台委托 file_selector |
| `NativePaths` | 应用缓存目录与持久化支持目录 | 鸿蒙原生 context；其他平台委托 path_provider |
| `NativeSettings` | 字符串、整数设置读写和按键删除 | 鸿蒙 Preferences；其他平台委托 shared_preferences |
| `NativePlatform.hostInfo` | 设备类型、API 版本、能力清单 | 鸿蒙 |
| `NativeHostWindow` | 窗口位置/尺寸控制、状态订阅、标题、最小/最大尺寸、最小化、最大化、恢复、拖动、关闭当前 Ability | 鸿蒙，部分操作取决于设备和窗口模式 |

窗口尺寸与坐标使用物理像素。`NativeHostWindow` 为异步接口，与上游同步 FFI `Window` 接口分开，避免在鸿蒙加载桌面 C 绑定。HiZip 在支持窗口控制的鸿蒙设备上隐藏系统标题栏，保留系统最小化、最大化/还原和关闭按钮，并将装饰高度设为 49vp，使按钮与 Flutter 工具栏居中对齐。工具栏提供拖动和双击最大化/还原，按系统按钮矩形预留空间；系统窗口调整尺寸能力保留。隐藏标题栏失败时继续使用系统装饰。

`hostInfo` 不读取序列号、UDID 或其他唯一设备标识。能力清单表示系统声明的能力；具体窗口操作仍可能因当前设备模式返回 `PlatformException`，调用者应处理。

```dart
final subscription = NativeHostWindow.changes.listen((state) {
  print('${state.width} × ${state.height}, maximized: ${state.isMaximized}');
});
await NativeHostWindow.configure(
  title: 'HiZip', minWidth: 800, minHeight: 600, maxWidth: 1920,
);
await NativeHostWindow.setDecorVisible(false, height: 49);
await NativeHostWindow.moveTo(100, 100);
await NativeHostWindow.resize(1024, 768);
await subscription.cancel();
```

`changes` 在订阅时发送当前状态，之后响应位置、尺寸与窗口模式变化；最后一个订阅取消后卸载原生监听。移动和调整尺寸适用于浮动窗口，最终位置和尺寸由系统约束决定，应通过状态事件确认。状态提供 `isFullScreen`、`isMaximized`、`isMinimized`、`isFloating` 与 `isSplitScreen`。

`setDecorVisible` 控制系统标题栏，可选 `height` 设置装饰高度（37–112vp）。`NativeHostWindowState.decorVisible` 返回当前可见性，`titleButtons` 返回系统按钮矩形（vp）；`right` 为右侧间距，工具栏需要预留 `width + right`，矩形变化也触发 `changes`。应用内容扩展到隐藏标题栏后的空间，安全区仍按实际 Flutter 表面与系统避让区域的交集计算。`setClosePreparation` 注册系统关闭按钮的异步准备回调（API 15 起）；回调成功后允许关闭，失败时阻止关闭，传入 `null` 清除回调。HiZip 使用该回调等待应用任务和缓存清理完成。

## 文档操作约定

鸿蒙公共文件以 URI 授权访问。插件将打开的文档复制到私有工作目录，Dart/FFI 只获取沙箱路径。

`openFile` 返回一个沙箱副本或在取消时返回 `null`；`openFiles` 返回副本列表或空列表。两者与 `getSaveLocation` 均将 `XTypeGroup.extensions` 映射到鸿蒙文档后缀筛选，支持 `tar.gz` 等复合后缀；MIME、UTI 与 Web 类型字段不转换。

`openWithDefault(path, mimeType: ..., writable: false)` 在鸿蒙通过 `viewData` Want 打开沙箱文件，使用系统默认应用；没有默认项时由系统选择可用应用。省略 `mimeType` 时通过系统类型描述符按扩展名推断，未知类型使用 `application/octet-stream`。默认授予临时读取权限，`writable: true` 同时授予写入权限。仅接受沙箱内的普通文件，拒绝路径穿越与符号链接；没有可用应用或启动失败时抛出 `PlatformException`。调用方应保留文件直到外部应用不再使用它。该接口仅支持鸿蒙。

`openDirectory` 选择已有目录并将内容复制到沙箱，取消时返回 `null`；它与用于解压导出的 `getDirectoryPath` 不同。其他平台的 `openDirectory` 返回原始目录路径。鸿蒙目录导入和导出使用系统 URI 复制接口，其跨设备复制存在系统并发与文件数量限制，错误通过 `PlatformException` 返回。

```dart
import 'package:nativeapi/nativeapi.dart';

final selected = await NativeDocuments.openFiles();
if (selected.isNotEmpty) {
  await NativeDocuments.openWithDefault(selected.first.path);
}
final save = await NativeDocuments.getSaveLocation(suggestedName: 'Archive.zip');
if (save != null) {
  // 在 save.path 写入压缩包后，再调用：
  await NativeDocuments.finishSave(save.path);
}
// 导出沙箱内编辑后的副本；取消返回 false。
final saved = await NativeDocuments.exportFile(selected.first.path);
```

`getDirectoryPath` 返回私有 staging root。完成解压后调用 `finishDirectory(root, output)` 导出到用户授权的公开目录。授权映射只存在于插件实例中，不能跨应用重启复用。

导出只接受应用 `filesDir` / `cacheDir` 内的真实文件与目录，拒绝路径穿越、符号链接和特殊文件；目录导出还要求输出是授权 staging root 的后代，目标目录已存在时拒绝覆盖。成功保存或目录导出后消耗对应授权，失败时保留授权便于重试。导入副本由调用方在不再使用时清理。

HiZip 的压缩包条目“打开”使用 `openWithDefault`，保留原有缓存修改检测；若外部编辑器就地修改同一文件，可检测并写回可写压缩包的沙箱副本。工具栏“保存副本”仍通过 `exportFile` 选择导出位置。当前不会自动覆盖原始公开文档；编辑器另存副本与鸿蒙跨应用文件拖拽尚不支持。

## 维护方式

- `lib/src/generated.dart` 和原上游绑定文件维持 0.2.7 的接口，升级时先对比上游变更。
- HiZip 新增 Dart API 放在 `lib/src/host_services.dart`，避免写入生成文件。
- 鸿蒙原生实现位于 `ohos/src/main/ets/NativeApiPlugin.ets`，遵循 FlutterPlugin / AbilityAware 生命周期，由 Flutter 自动注册。
- 保持 MethodChannel `nativeapi/hizip` 的参数和返回值兼容；API 变更同步更新契约测试和真机自检。

```sh
# 在 HiZip 仓库根目录：
tools/flutter-ohos pub get
tools/flutter-ohos test packages/nativeapi/test
# 构建后安装并检查 HiLog 中的 HIZIP_DEVICE_SMOKE：
tools/flutter-ohos build hap --debug -t integration_test/ohos_native_smoke.dart
```

当前插件 24 项测试及应用侧 8 项鸿蒙桥接回归测试通过。默认打开的测试覆盖 MIME/权限参数、原生启动错误和压缩包条目的调用路径。API 24 基础真机自检 15 项通过，包括窗口事件订阅、支持目录、窗口参数、沙箱路径、路径穿越与文件后缀校验。符号链接检查因设备禁止创建链接而记录在 `skipped` 中；文件/目录选择、导出和窗口移动/缩放仍需交互验收。
