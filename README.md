# HiZip

HiZip 是一款基于 Flutter 和 libarchive 的本地压缩包管理器。它将目录浏览、文件预览、解压和压缩包内编辑整合在同一个工作空间中，提供接近文件管理器的使用体验。

项目处于早期开发阶段，以 macOS 桌面体验为主要方向。

## 功能

- **多标签浏览**：同时打开多个压缩包，独立保存各标签的目录、搜索与选择状态。
- **四种视图**：列表、图标、多栏和画廊，配合目录树、路径导航与文件信息侧栏。
- **大目录浏览**：仅按需构建可见条目；目录超过 1,000 项时先折叠剩余内容，双击末尾提示展开。折叠不影响搜索和全选。
- **文件预览**：图片与文本预览；macOS 支持系统文件图标和 Quick Look。
- **压缩与解压**：创建压缩包，解压全部内容或所选文件、文件夹，显示解压进度。
- **大数量条目**：读取、导入、更新和批量解压不设置固定条目数上限，实际容量取决于设备资源和压缩格式。
- **压缩包内编辑**：导入、复制、移动、删除、新建文件夹和空白文档；支持剪贴板与拖拽。
- **外部应用编辑**：将文件临时解压后打开，检测内容变化并询问是否写回原压缩包。
- **个性化设置**：浅色、深色和系统主题，中文与英文界面，各视图独立缩放，浏览偏好持久化。
- **编码与性能配置**：文件名编码自动识别或手动选择，压缩等级与解压线程设置。
- **macOS 集成**：系统菜单、最近打开、文件关联和独立设置窗口。

## 支持的格式

外观设置提供海蓝、紫罗兰、青绿、森林绿、琥珀橙和玫瑰红主题色，适用于主要按钮、选中控件及文件选择；支持浅色与深色模式并自动保存。

| 操作 | 格式 |
| --- | --- |
| 读取 | ZIP、7z、RAR、TAR、CPIO、CAB、ISO、XAR、AR，以及 libarchive 支持的其他格式 |
| 创建与更新 | ZIP、7z、TAR、TAR.gz、TAR.bz2、TAR.xz、TAR.lzma、TAR.zst、TAR.lz4、TAR.lzip、TAR.Z、CPIO、AR |
| 单文件压缩 | gzip、bzip2、xz、LZMA、zstd、LZ4、lzip、compress |

实际格式与压缩算法支持取决于目标平台的 libarchive 和编解码依赖。RAR、CAB、ISO 等格式只提供读取；单文件压缩格式不支持添加多个文件。

## 使用

通过“文件”菜单打开或创建压缩包，也可以在 macOS Finder 中使用 HiZip 打开文件。需要修改默认打开方式时，在“设置 → 通用 → 文件关联”中进行配置。

双击文件会在外部应用中打开；修改后可选择写回压缩包。选择不保存的临时修改会在关闭压缩包后丢弃。右键菜单提供文件操作，信息侧栏支持打开和解压所选项目。

常用 macOS 快捷键：

| 快捷键 | 操作 |
| --- | --- |
| `⌘O` | 打开压缩包 |
| `⌘N` | 创建 ZIP |
| `⌘W` | 关闭当前标签或窗口 |
| `⌘,` | 打开设置 |
| `⌘C` / `⌘V` | 复制 / 粘贴 |
| `⌘A` | 全选 |
| `⌘⇧N` | 新建文件夹 |
| `⌘⌫` | 删除所选项目 |
| `Space` | 切换 Quick Look |
| `Alt+←` | 返回上一级浏览位置 |

图标视图支持在网格中使用方向键导航；Command 点击增减选择，Shift 点击连续选择。

## 开发与构建

使用符合 [pubspec.yaml](pubspec.yaml) 要求的 Flutter 和 Dart SDK。

### macOS

需要 Xcode 及其命令行工具。原生引擎链接系统 libarchive，无需另外安装该库。

```sh
git clone git@github.com:Hibanaw/HiZip.git
cd HiZip
flutter pub get
flutter run -d macos
```

构建桌面应用：

```sh
flutter build macos --release
```

### 其他平台

仓库包含 Windows、Linux、Android 和 iOS 工程，但平台集成与发布流程仍需完善。Web 当前提供界面，尚未接入压缩引擎。

Windows、Linux 和 Android 的原生引擎通过 CMake 编译仓库内的 libarchive 源码包；桌面构建需要 CMake 3.18+，额外编解码能力由目标平台依赖决定。平台相关配置见 [原生引擎说明](packages/hizip_native/README.md)。鸿蒙移植工具说明见 [tools/HARMONYOS.md](tools/HARMONYOS.md)。

## 测试

```sh
flutter analyze
flutter test
```

在 macOS 上运行真实压缩包读写测试：

```sh
xcrun clang -dynamiclib -Wall -Wextra -Werror -O2 \
  packages/hizip_native/src/hizip_native.c -larchive \
  -o /tmp/libhizip_native.dylib

HIZIP_NATIVE_LIBRARY=/tmp/libhizip_native.dylib \
  python3 test/native/archive_engine_test.py

HIZIP_NATIVE_LIBRARY=/tmp/libhizip_native.dylib flutter test
```

测试覆盖格式读写、文件编辑、缓存生命周期、编码、解压、任务队列及界面交互。`HIZIP_NATIVE_LIBRARY` 用于指定测试使用的原生动态库。

## 项目结构

```text
lib/models/                 压缩包条目、索引与偏好模型
lib/services/               文件会话、任务队列、压缩包操作与平台集成
lib/ui/                     浏览界面、设置、主题与控件
packages/hizip_native/       Dart FFI、C 引擎与原生平台接口
test/                       Flutter 与原生回归测试
tools/                      开发工具与平台移植说明
```

Flutter 负责界面与任务协调，libarchive 负责格式解析和压缩。耗时操作在后台执行；可写压缩包通过暂存文件校验和替换完成更新。第三方源码来源与许可见 [libarchive 依赖说明](packages/hizip_native/third_party/README.md)。

## 当前限制

- 暂不支持加密内容提取、分卷压缩包和压缩包内直接重命名。
- 不恢复链接或特殊文件，拒绝不安全路径和重复解压目标。
- 打开、解压、导入和写回不设应用层文件大小上限；实际能力受格式、磁盘空间与系统资源限制。
- 文本预览上限为 2 MiB，图片预览上限为 20 MiB；超出时显示预览提示，仍可打开或解压。单个压缩包条目数上限为 100,000。
- 重建压缩包不保证保留所有格式专有扩展、原始压缩参数或注释。
- 移动端文件授权、外部编辑与分享流程仍在适配中；Web 需要独立的压缩引擎后端。
