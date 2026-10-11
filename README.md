# HiZip

HiZip 是基于 Flutter 与 libarchive 的原生压缩包管理器，将压缩包浏览、预览、解压和内部编辑放在同一个工作区。项目处于早期开发阶段，主要面向 macOS 桌面；仓库也包含 Windows、Linux、Android 和 iOS 工程，平台能力与发布流程仍在完善中。**不支持 Web。**

## 当前功能

- 多标签浏览，以及列表、图标、多栏和画廊视图；目录树、搜索、排序和信息侧栏。
- 大目录按需构建条目。超过 1,000 项时可展开折叠内容，搜索和全选仍覆盖全部条目。
- 图片与文本预览；内置 UTF-8 文本编辑，保存时检测内容冲突。macOS 提供系统文件图标和 Quick Look。
- 创建压缩包、创建空容器压缩包、解压全部或所选项目、解压到同名文件夹；显示文件与总体进度。
- 压缩包内导入、复制、移动、删除、重命名、新建文件夹和空白文件，支持剪贴板与拖拽。
- ZIP 注释读取、编辑及创建时填写；重建时保留压缩包与条目注释，保存前检测外部修改。
- ZIP/7z 连续分卷创建与自动打开，支持缺卷及校验检查；分卷打开后只读。
- 解压冲突可询问、覆盖、跳过或自动改名；任务支持暂停、继续、取消与提交前失败重试。
- 压缩包完整性测试：读取全部条目数据，报告解码或校验错误，不生成解压文件。
- 密码解压；支持引擎具备能力时创建 ZIP AES-256 加密包。密码不会写入应用设置。
- 创建时选择 ZIP 的 Deflate 或 Store（不压缩），调整 ZIP/7z 的压缩等级；格式菜单按当前引擎能力筛选。
- 在 HiZip 中打开嵌套压缩文件，或通过外部应用打开普通文件；检测外部修改并询问写回。
- 浅色、深色和系统主题，六种主题色，七种界面语言，各视图缩放、DPI 与浏览偏好持久化。
- 菜单、密码与压缩选项弹窗、文本编辑及操作提示使用所选界面语言；文件名、路径和文件内容保留原文。“跟随系统”选项使用系统语言。
- macOS 系统菜单、最近打开、文件关联和独立设置窗口；Linux 提供文件关联设置。
- macOS Finder 的 HiZip 二级菜单：创建压缩包、快速创建 ZIP；支持按选择数量默认嵌套同名文件夹。启用方法与沙盒授权流程见 [Finder 集成说明](docs/MACOS_FINDER.md)。

## 格式与加密

| 操作 | 格式 |
| --- | --- |
| 读取 | ZIP、7z、RAR、TAR、CPIO、CAB、ISO、XAR、AR 等 libarchive 支持的格式 |
| 容器创建与更新 | ZIP、7z、TAR、TAR.gz、TAR.bz2、TAR.xz、TAR.lzma、TAR.zst、TAR.lz4、TAR.lzip、TAR.Z、CPIO、AR |
| 单文件压缩 | gzip、bzip2、xz、LZMA、zstd、LZ4、lzip、compress |
| 加密创建 | ZIP AES-256，要求当前引擎支持 AES，且至少包含一个普通文件 |

格式和算法取决于平台的 libarchive 与编解码依赖；菜单能力检查与实际操作都会检查错误。RAR、CAB、ISO 等格式只提供读取。单文件压缩格式需要一个普通文件，不能创建空包或加入多个文件。

RAR 使用内置官方 UnRAR 7.23 解压引擎，无需另行安装 WinRAR。支持 RAR4/RAR5、密码与文件名加密、固实压缩，以及 `.partNN.rar` 和旧式 `.rar/.r00/.r01` 分卷；可从任意分卷打开，所有分卷需放在同一目录。缺卷会明确报错，不发布不完整解压结果。RAR 不提供创建或内部修改；硬链接、文件复制引用和部分旧式链接暂不提取。

从只读压缩包打开的文件会以只读权限交给外部应用，不触发修改写回提示；编辑需另存到其他位置。macOS/Linux 同时锁定单文件临时目录，Windows 设置文件只读属性。嵌套打开继承只读状态；关闭时恢复临时文件权限并清理缓存。

密码读取已在 macOS 原生引擎上验证 ZIP AES-256；其他加密变体取决于引擎。密码错误、不支持的加密算法和损坏文件会导致解锁失败，可重新输入密码。解锁前会读取全部数据进行验证，大型加密包可能需要较长时间。

ZIP AES 加密保护文件内容，**不会隐藏文件名**。加密压缩包目前只读，不支持内部修改或重新写入。7z 加密读取，以及文件名加密、字典大小和固实压缩的创建配置尚未实现。

## 使用

通过应用菜单打开或创建压缩包。“快速创建 ZIP”选择文件或文件夹后自动保存在源位置；“创建压缩包…”可选择压缩内容、保存位置和压缩选项。macOS Finder 也可使用 HiZip 打开文件，默认关联可在“设置 → 通用 → 文件关联”中配置。

任务进度与结果始终显示在下方状态栏。设置中的辅助窗口显示方式控制对话框的位置：画面内使用变暗、模糊的背景，独立对话框处理完成或关闭前阻止操作主窗口；设置和属性窗口可以与主窗口同时操作。紧凑布局下对话框全屏显示。

右键文件或文件夹可重命名、解压、删除和新建项目。宽窗口下在原文件名位置编辑，Return 保存、Esc 取消；紧凑窗口使用统一样式的对话框。默认选中文件名并保留扩展名，保存失败保留输入。完整性测试位于应用菜单中。

打开加密包时输入密码，解锁后可预览、打开和解压。密码仅在当前会话中使用，关闭对应压缩包后清除服务中的密码缓存。

双击受支持的内部压缩文件会在 HiZip 中打开；普通文件通过默认外部应用打开，“打开方式”可选择其他应用。外部修改可写回可写压缩包；未保存的修改按关闭流程保留或丢弃。嵌套压缩包的修改发生在缓存副本中，写回父包仍走外部修改检测与保存确认。

解压前可选择询问、覆盖、跳过或自动改名。询问、覆盖和跳过策略会合并同名目录，再处理内部文件冲突；自动改名保留独立目录。文件先解压到暂存区，确认全部冲突后发布；失败时恢复已覆盖的原文件。恢复失败时保留备份及恢复记录，并报告路径，需人工处理。对于压缩包内仅大小写不同的路径，可选择改名或跳过。解压可恢复符号链接；链接指向绝对路径或解压目录外时询问是否保留。硬链接与特殊文件会跳过，不安全的条目路径会拒绝。

| 快捷键 | 操作 |
| --- | --- |
| `⌘O` | 打开所选项目；未选择时打开压缩包 |
| `⌘N` | 创建 ZIP |
| `⌘W` | 关闭当前标签或窗口 |
| `⌘,` | 打开设置 |
| `⌘C` / `⌘V` | 复制 / 粘贴 |
| `⌘A` | 全选 |
| `⌘⇧N` | 新建文件夹 |
| `Return` | 重命名所选文件或文件夹 |
| `⌘↓` | 打开所选文件或文件夹 |
| `⌘↑` | 返回上一级浏览位置 |
| `⌘⌫` | 删除所选项目 |
| `Space` | macOS Quick Look |
| `Alt+←` | 返回上一级位置 |

上表以 macOS 为例；其他桌面平台使用 F2 重命名、Enter 打开，复制、粘贴等操作可使用 Ctrl。图标视图支持方向键导航，Command/Ctrl 点击增减选择，Shift 点击连续选择。

## 开发与构建

使用满足 [pubspec.yaml](pubspec.yaml) 要求的 Flutter/Dart SDK。macOS 需要 Xcode 及其命令行工具；原生引擎链接系统 libarchive。

```sh
flutter pub get
flutter run -d macos
flutter build macos --release
```

“设置 → 外观 → 辅助窗口显示方式”可选择画面内显示或独立窗口显示，控制设置、属性及操作提示。设置和属性窗口在下次打开时采用新模式；正在显示的操作提示随模式切换。需要输入文件名的操作仍在工作区内完成。系统文件选择器和 Quick Look 由系统管理。

编译时可指定首次启动的默认值（未指定时为 `separate`）：

```sh
flutter build macos --release --dart-define=HIZIP_WINDOW_MODE=inline
flutter build macos --release --dart-define=HIZIP_WINDOW_MODE=separate
```

此编译项也适用于 `flutter run`。已保存的用户设置优先于编译默认值；无效值回退为 `separate`。

Windows、Linux 和 Android 使用 CMake 编译仓库内固定版本的 libarchive 源码包。编解码库由目标平台构建环境提供；Linux 等平台的 AES 能力可通过可选 OpenSSL 启用，缺少密码学后端时禁用 AES 创建选项。跨平台构建细节见 [原生引擎说明](packages/hizip_native/README.md)。

## 验证

```sh
flutter analyze --no-pub lib test packages/hizip_native
flutter test
```

默认测试会跳过要求真实原生引擎的用例。在 macOS 上编译测试库并启用原生回归：

```sh
cmake -S packages/hizip_native/src -B build/native -DCMAKE_BUILD_TYPE=Release
cmake --build build/native --target hizip_native -j 4

HIZIP_NATIVE_LIBRARY="$PWD/build/native/libhizip_native.dylib" \
  python3 test/native/archive_engine_test.py

HIZIP_NATIVE_LIBRARY="$PWD/build/native/libhizip_native.dylib" \
  python3 test/native/rar_engine_test.py
HIZIP_NATIVE_LIBRARY="$PWD/build/native/libhizip_native.dylib" flutter test
```

测试包括格式读写、加密与密码会话、压缩配置、外部编辑写回、ZIP 注释保留、连续分卷、解压冲突与回滚、缓存、任务控制和界面交互。缺少 zstd/LZ4 等编解码能力时，回归验证明确拒绝操作且不产生输出；具备能力时验证读写。当前验证结果与发布前待办见 [实施计划](docs/IMPLEMENTATION_PLAN.md)。

## 限制与后续工作

- 分卷创建支持连续切分的 `.zip.001` / `.7z.001`；RAR 分卷支持读取，不支持创建，PKZIP `.z01` 尚不支持。ZIP/7z 分卷创建时附带大小及 SHA-256 清单，应与所有分卷一起保存。
- 暂停和取消在数据块及条目检查点生效；最终提交阶段不可中断。仅提交前失败的任务可重试，取消不会自动重试。
- 注释编辑限未加密且可写的 ZIP。保留 ZIP 注释不代表保留全部格式专有扩展或原始压缩参数；无法安全映射的旧编码条目注释会拒绝重建并保留原包。
- 异常回滚失败会保留备份与恢复记录，尚无启动时自动恢复流程。商业发布仍需各平台实机验收、签名和分发验证。
- 图片预览上限为 20 MiB。文本预览会截断显示。
- 打开、解压、导入和写回不设置应用层文件大小或条目数上限，实际容量受格式、内存、磁盘与系统资源限制。
- 移动端文件授权、外部编辑、分享和各平台发布流程尚未完成。

## 代码结构

```text
lib/models/                 条目、索引、偏好与操作配置
lib/services/               压缩操作、缓存会话、任务队列与平台集成
lib/ui/                     浏览、注释编辑、密码与压缩选项界面
packages/hizip_native/       Dart FFI、共享 C/C++ 引擎与平台接口
packages/cnativeapi/         桌面原生窗口依赖
test/                      Flutter 与原生回归测试
docs/                      实施计划
```

耗时压缩工作在后台执行。可写压缩包使用独立暂存输出，验证与冲突检查后替换原包。第三方来源与许可见 [依赖说明](packages/hizip_native/third_party/README.md) 和 [libarchive LICENSE](packages/hizip_native/src/vendor/LIBARCHIVE-LICENSE)。
