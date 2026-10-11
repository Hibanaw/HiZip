# macOS Finder 集成

macOS 构建包含 `HiZipFinder.appex`，Finder 文件右键菜单仅添加一个 **HiZip** 条目，二级菜单为 **创建压缩包** 和 **快速创建 ZIP**。Finder 菜单使用系统语言，配置弹窗使用应用语言。

将 HiZip 放在固定位置（发布时通常为 `/Applications`），启动一次，然后在 **设置 → 通用 → Finder 右键菜单 → 管理 Finder 扩展** 中启用 HiZip。系统界面由 `FIFinderSyncController.showExtensionManagementInterface()` 打开。系统负责加载扩展；更新后若仍显示旧菜单，可在系统设置中关闭再启用扩展。

| 来源 | 创建压缩包默认嵌套 | 快速 ZIP |
| --- | --- | --- |
| 单个文件 | 否 | 原位旁边创建，不嵌套 |
| 单个文件夹 | 否，保留来源文件夹本身 | 原位旁边创建，不额外嵌套 |
| 多个文件或文件夹 | 是 | 原位旁边创建，不嵌套 |

创建压缩包会显示格式、加密密码、嵌套文件夹、压缩等级等配置，再选择保存名称和位置。格式列表来自引擎能力，只显示可创建容器的格式。当前密码加密支持 ZIP AES-256，其他格式会明确说明不支持。

嵌套文件夹使用最终压缩包名称，去掉完整格式后缀，例如 `备份.tar.gz` 内部为 `备份/`。嵌套通过归档路径实现，不移动或复制原始文件。

快速 ZIP 使用默认 ZIP 选项，不弹配置和保存对话框。单个文件使用文件名去掉扩展名，单个文件夹保留完整文件夹名；多选使用第一个所选项目的父文件夹名称，并写在该父文件夹中。重名使用 `名称 (2).zip` 等后缀，目录、文件和符号链接均视为已占用；提交时使用排他发布，避免覆盖在名称检查后才出现的目标。

## 请求传递

Finder 扩展使用 `NSWorkspace.open` 将 `hizip://compress?request=…` 发送给其所在应用包。JSON 载荷为版本、UUID、动作和完整所选路径，Base64 与 URLQueryItem 编码保留中文、空格及特殊字符。主应用校验载荷，并在 Flutter 安装事件监听后按顺序交付请求；应用冷启动和已运行均可处理。UUID 防止同一请求被重复执行。

Finder 展示的是跨进程复制的菜单。扩展使用系统保留的菜单 `tag` 区分动作，在点击回调中调用 `selectedItemURLs()` 获取选择；不依赖不会传回的 `representedObject`。

## 分发与权限

主应用和 Finder 扩展均启用 **App Sandbox**。主应用仅使用用户选择文件的读写权限和应用范围的安全作用域书签；Finder 扩展只传递路径，不读取所选文件。

首次访问未授权目录时，主应用弹出系统目录选择面板。选择所需目录（或包含它的上级目录）并点击“授权此目录”，之后该目录内的快速 ZIP 无需额外弹窗。授权以安全作用域书签保存，启动后恢复；取消授权会停止当前操作。书签失效或目录迁移时可能需要重新授权。

打开压缩包可使用文件级只读授权。创建、编辑与解压需要目标目录的读写权限，因为安全更新会先在同目录创建临时文件，再提交替换；不能仅依赖保存面板对单个输出文件的授权。分卷读取需要父目录权限，以访问其余分卷与校验清单。所有 Flutter 引擎及后台任务共用进程级授权，访问应用容器和缓存无需额外授权。

此配置已恢复 Mac App Store 所需的沙盒基础。App Store 发布仍需开发者签名、Provisioning Profile，以及其他提交资料与审核；当前本机构建不能视为已通过商店审核。直接分发正式版本另需签名和公证。

macOS 27 / Rust 1.97 上，拖放依赖的 Release 构建遇到了 Rust 宏动态库符号表未对齐问题。Podfile 为该依赖的非 Debug 配置保留**宿主构建依赖**的调试信息，避免 Rust 的剥离步骤；应用本身仍使用 Release 优化。原因见 [Rust 上游问题 #157750](https://github.com/rust-lang/rust/issues/157750)。

## 验证

```sh
flutter build macos --debug
cmake -S packages/hizip_native/src -B build/native -DCMAKE_BUILD_TYPE=Release
cmake --build build/native --target hizip_native -j 4
HIZIP_NATIVE_LIBRARY="$PWD/build/native/libhizip_native.dylib" \
  flutter test test/finder_compression_test.dart test/archive_security_test.dart test/archive_basic_features_test.dart
flutter test test/sandbox_access_test.dart test/finder_compression_widget_test.dart test/archive_security_dialogs_test.dart test/localization_coverage_test.dart
xcrun swiftc macos/Runner/FinderCompressionRequest.swift test/macos/finder_request_test.swift \
  -o /tmp/hizip-finder-request-tests
/tmp/hizip-finder-request-tests
xcrun swiftc macos/Runner/FinderCompressionRequest.swift macos/HiZipFinder/FinderSync.swift \
  test/macos/finder_menu_test.swift -o /tmp/hizip-finder-menu-tests
/tmp/hizip-finder-menu-tests
xcrun swiftc -module-cache-path /tmp/hizip-swift-cache \
  packages/hizip_native/macos/Classes/SandboxFileAccess.swift \
  test/macos/sandbox_file_access_test.swift -o /tmp/hizip-sandbox-access-tests
/tmp/hizip-sandbox-access-tests
```

手工验证（沙盒）：首次快速 ZIP 应出现目录授权；取消不写入文件；授权后生成 ZIP。重启应用后重复相同目录的快速 ZIP，不应再次要求授权。

手工验证：在 Finder 选择单文件、单文件夹和多选，确认 HiZip 二级菜单；分别执行两种动作，核对弹窗默认值、原位 ZIP、中文路径、重名处理和原始内容保留，再对比应用未启动与已运行的结果。

2026-10-10 已在已安装的 `/Applications/HiZip.app` 实测 Finder 菜单：单个中文带空格文件的“创建压缩包”能显示配置弹窗，“快速创建 ZIP”能在旁边生成 ZIP。读取输出确认只有来源文件，无额外嵌套目录，文件内容一致。菜单回调另有模拟 Finder 复制菜单字段的 Swift 回归测试。

权限实现参考 [Apple 沙盒文件访问](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)。

2026-10-11 沙盒版已更新至 `/Applications/HiZip.app` 并实测：首次目录授权后可创建中文带空格名称的 ZIP；退出后由 Finder 冷启动再次压缩，无需重复授权并自动避开重名；另一目录取消授权不创建任何输出。创建压缩包配置、打开 ZIP、编辑文本并安全保存、解压到系统面板选择的新目录均正常，核对源文件保持不变、解压内容与编辑后的 ZIP 一致。完整 Flutter 回归测试 421 项通过，静态分析、Swift 权限边界测试、Finder 菜单复制回归与 Release 签名校验通过。

Finder 扩展实现参考 [Apple Finder Sync 文档](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Finder.html)。

2026-10-11 后续调整：按用户要求移除 Edit Text 菜单、内置文本编辑器及其保存接口。以上编辑实测记录对应移除前的沙盒版本；文本预览与外部应用编辑写回仍保留。更新后的 Release 已安装并实测原生 Edit 菜单和可写文本文件右键菜单均无 Edit Text，文本预览正常；69 项相关回归测试、静态分析及签名校验通过。
