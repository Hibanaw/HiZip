# HiZip nativeapi

这是 HiZip 在仓库内维护的 `nativeapi` Flutter 插件，基于上游 `nativeapi 0.2.7`，版本为 `0.2.7+hizip.1`。应用通过 path dependency 使用此目录，不依赖 pub.dev 上 nativeapi 的自动升级。

上游项目：[libnativeapi/nativeapi-flutter](https://github.com/libnativeapi/nativeapi-flutter)。上游代码保留原 MIT [LICENSE](LICENSE)。桌面 C/FFI 实现仍来自固定版本的 `cnativeapi 0.2.7`，本轮没有 fork 其 C++ 实现。

## 已维护的接口

| 接口 | 能力 | 平台 |
| --- | --- | --- |
| `Window` / `WindowManager` 等上游接口 | 桌面窗口、菜单等现有 FFI 能力 | 保留上游桌面实现 |
| `NativeDocuments` | 文件多选、保存位置、目录选择、结果导出 | 鸿蒙原生文档选择器；其他平台委托 file_selector |
| `NativePaths` | 应用缓存目录 | 鸿蒙原生 context；其他平台委托 path_provider |
| `NativeSettings` | 字符串、整数设置读写和按键删除 | 鸿蒙 Preferences；其他平台委托 shared_preferences |
| `NativePlatform.hostInfo` | 设备类型、API 版本、能力清单 | 鸿蒙 |
| `NativeHostWindow` | 窗口位置、尺寸、状态、标题、最小尺寸、最小化、最大化、恢复、拖动、关闭当前 Ability | 鸿蒙，部分操作取决于设备和窗口模式 |

窗口尺寸与坐标使用物理像素。`NativeHostWindow` 为异步接口，与上游同步 FFI `Window` 接口分开，避免在鸿蒙加载桌面 C 绑定。应用保留鸿蒙系统窗口装饰，通过此插件设置窗口标题。

`hostInfo` 不读取序列号、UDID 或其他唯一设备标识。能力清单表示系统声明的能力；具体窗口操作仍可能因当前设备模式返回 `PlatformException`，调用者应处理。

## 文档操作约定

鸿蒙公共文件以 URI 授权访问。插件将打开的文档复制到私有工作目录，Dart/FFI 只获取沙箱路径。

```dart
import 'package:nativeapi/nativeapi.dart';

final selected = await NativeDocuments.openFiles();
final save = await NativeDocuments.getSaveLocation(suggestedName: 'Archive.zip');
if (save != null) {
  // 在 save.path 写入压缩包后，再调用：
  await NativeDocuments.finishSave(save.path);
}
// 导出沙箱内编辑后的副本；取消返回 false。
final saved = await NativeDocuments.exportFile(selected.first.path);
```

`getDirectoryPath` 返回私有 staging root。完成解压后调用 `finishDirectory(root, output)` 导出到用户授权的公开目录。授权映射只存在于插件实例中，不能跨应用重启复用。

当前没有自动写回原文档、外部编辑器同步或鸿蒙跨应用文件拖拽。公开目录复制和选择器交互仍需完整真机验收。

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

本轮静态分析通过，应用和插件 128 项测试全部通过；真机自检九项通过，包括设置存储与删除、运行时能力查询和窗口尺寸读取。签名 2in1 Release 包已构建并安装。桌面原生运行和会改变窗口状态的命令需在对应平台继续验收。
