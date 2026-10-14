# Windows 资源管理器右键菜单

对应 macOS 的 Finder 扩展：文件和文件夹的右键菜单中出现一个 **HiZip** 条目，二级菜单为 **创建压缩包** 和 **快速创建 ZIP**，行为与 [MACOS_FINDER.md](MACOS_FINDER.md) 中的规则一致（默认嵌套、快速 ZIP 命名、重名处理）。

在 **设置 → 通用 → 资源管理器右键菜单** 中点击“启用右键菜单”即可，“移除右键菜单”会同时删除两种菜单。菜单文字：Windows 11 菜单跟随系统语言（与 Finder 扩展一致），传统菜单使用写入时的应用语言。命令指向当前运行的 `hizip.exe`，移动安装位置后需重新启用。两种菜单都不需要管理员权限。

## 两种菜单

| | Windows 11 新式菜单 | 传统菜单 |
| --- | --- | --- |
| 位置 | 右键菜单顶层 | “显示更多选项”（Windows 10 为顶层） |
| 实现 | [hizip_shell.cpp](../windows/shell_ext/hizip_shell.cpp)：`IExplorerCommand`（含子命令），由 Explorer 的 COM 代理加载 | `HKCU\Software\Classes\*\shell\HiZip` 与 `Directory\shell\HiZip`（级联 `SubCommands`） |
| 注册 | 稀疏包（[AppxManifest.xml](../windows/shell_ext/AppxManifest.xml)，包名 `com.hibanaw.hizip.ContextMenu`），用 `Add-AppxPackage -Register … -ExternalLocation <exe 目录>` 以松散文件方式注册 | `reg add` |
| 条件 | Windows 11，且开启“开发人员模式”（未签名的松散注册需要它） | 无 |

启用时优先注册新式菜单，成功后删除传统菜单以免重复；注册失败（Windows 10、未开启开发人员模式等）自动退回传统菜单，设置页会提示。构建时 CMake 把 `hizip_shell.dll` 和 `shell_package/`（清单与 logo）放在 `hizip.exe` 旁边。

## Microsoft Store / MSIX 版本

打包版本不能在运行时注册菜单（`HKCU` 写入会被虚拟化，也不能调用 `Add-AppxPackage`），所以 [build_msix.ps1](../scripts/build_msix.ps1) 把下列声明直接写进主包清单，设置页只显示说明、不再提供启用/移除按钮（`DesktopIntegration.isPackaged`，按 `\WindowsApps\` 路径判断）：

- `windows.fileExplorerContextMenus` 与 `windows.comServer`：`hizip_shell.dll` 随包安装，菜单随安装出现、随卸载消失。Windows 10 会忽略这些扩展（已加入 `IgnorableNamespaces`），因此商店版在 Windows 10 上没有右键菜单。
- `windows.appExecutionAlias`（`hizip.exe`）：包内 exe 不能被直接启动，DLL 在包内时改为通过 `%LOCALAPPDATA%\Microsoft\WindowsApps\hizip.exe` 别名 `ShellExecute` 启动。
- “设为默认打开方式”改为打开系统“默认应用”设置（`ms-settings:defaultapps`），文件关联由清单中的 `file_extension` 声明。

```powershell
# 提交到 Partner Center：身份取自 Partner Center 的“产品身份”页，不签名
pwsh scripts/build_msix.ps1 -Store -IdentityName '<Package/Identity/Name>' `
  -Publisher '<Package/Identity/Publisher>' -PublisherDisplayName '<发布者显示名>'
# 本地侧载测试：默认用自签名开发证书签名
pwsh scripts/build_msix.ps1
```

已验证：makeappx 接受含这些扩展的清单；以 `Add-AppxPackage -Register` 松散注册成功，`hizip.exe` 执行别名生成。尚未在已安装的商店版里实际点击验证菜单（Explorer → DLL → 别名 → 应用的整条链），也没有在 Windows 10 上验证安装。注意：若系统里已有正在运行的主窗口，新进程会把请求转给它；用旧版本做对照测试前先退出旧实例。

## 请求传递

新式菜单一次启动 `hizip.exe --hizip-compress=<create|quickZip> "<路径>" …` 带上全部所选项目；传统菜单由 Explorer 对每个项目启动一个进程。[compress_request.cc](../windows/runner/compress_request.cc) 在 `wWinMain` 最开始处理：

1. 第一个拿到命名互斥体 `Local\HiZipCompressCollector` 的进程成为收集者，创建仅消息窗口；其他进程用 `WM_COPYDATA` 把路径发给它后退出。
2. 收集者在 400 ms 内没有新路径时结束收集，去重。
3. 如果已有 HiZip 主窗口，则用 `WM_COPYDATA` 发给它，由 `FlutterWindow` 转成 `compressFiles` 调用（与 Finder 请求同一条 Dart 路径）并置前窗口，随后退出；否则收集者作为新实例继续启动，Dart 在 `initializeArchives` 中通过 `initialCompressRequest` 取走请求。

传统菜单受 Explorer 多选限制（超过约 15 个时系统不显示该菜单）；新式菜单没有这个限制。

## 验证

```sh
flutter test test/windows_shell_menu_test.dart test/finder_compression_test.dart
flutter build windows --debug
```

手工：并发启动多个 `hizip.exe --hizip-compress=quickZip "<文件>"`，应只出现一个应用进程和一个 ZIP；应用已运行时再次启动，应由已有窗口处理。启用菜单后在资源管理器右键单个文件、多个文件和文件夹，核对两个子项。
