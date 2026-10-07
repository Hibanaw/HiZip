# HiZip

Flutter 自适应界面 + 原生 libarchive 插件的本地压缩包管理器。
当前交付是 **macOS 可运行的 v0.1**，其他原生平台共享 C ABI 与 Flutter UI，尚需对应设备验证。

## 运行

```sh
flutter pub get
flutter run -d macos
```

使用当前 Xcode，macOS 部署目标设为 12.0。无需安装 Homebrew libarchive：Apple 构建链接系统 libarchive。

已构建的开发应用：`build/macos/Build/Products/Debug/HiZip.app`。
真实测试压缩包：`test/fixtures/sample.zip`，含中文文本、PNG 图片、嵌套目录及空文件夹。

## 界面与任务执行

开发环境为 Flutter 3.47.6 / Dart 3.13.5。界面使用 Forui 0.21.3，统一按钮、搜索框、下拉选择、滑块、菜单、嵌套打开方式、对话框和进度反馈。桌面控件统一封装在 `lib/ui/desktop_widgets.dart`，共享字号、圆角及明暗主题；编码选择使用 Forui 菜单，支持方向键、Enter 和 Esc。桌面使用紧凑的中性色主题，保留 Finder 目录树、多栏视图、系统文件图标和即时双击操作。

桌面窗口使用 nativeapi_flutter 0.4.1 隐藏系统标题栏，工具栏中的标题区域支持拖动和双击最大化/还原。macOS 保留系统红黄绿窗口按钮、圆角、阴影与缩放边缘；Windows/Linux 在右侧提供最小化、最大化/还原、关闭按钮和边缘缩放。移动端与 Web 使用常规布局。当前 nativeapi 的 Linux 拖动接口尚未实现，Linux 需要设备验证与后续补齐。

压缩包读取、索引建立、哈希、输入目录扫描、导入计划、导出及批量解压在最多两个后台 isolate 中执行。macOS 暂存目录和原子替换在原生串行后台队列执行；UI 与 AppKit 窗口/Quick Look 操作留在主线程。搜索采用延迟合并和后台过滤，文本预览限制显示长度，目录浏览复用索引，避免每次刷新遍历全部条目。

## 功能

- 多压缩包标签页：打开第二个压缩包后显示标签栏，每个标签保留目录、搜索和选择；左侧显示所有压缩包根目录并同步标签切换。`⌘W` 关闭当前标签，关闭标签时释放对应临时缓存；切换标签保留缓存。
- Finder 风格目录树、面包屑、列表/图标/多栏视图、当前文件夹搜索、右侧预览；文件和文件夹行高统一。多栏视图单击目录向右展开，保留父目录；支持左右方向键导航。
- 左右侧栏分隔线可拖动调整宽度。右栏预览位于顶部，详细信息位于底部；窗口较矮时可滚动。右栏显示时隐藏文件列表下方的重复信息条。
- 文件右键菜单提供打开、快速查看、复制、粘贴、解压。macOS 的“打开方式”显示系统可用应用及图标，支持选择其他应用；自选应用打开的临时文件也参与修改检测和写回。
- 可写压缩包支持删除（含多选及文件夹子项）、新建文件夹和空白文档；入口位于右键菜单和系统文件菜单。`⌘⌫` 删除、`⌘⇧N` 新建文件夹；删除前确认，新建同名项目自动添加数字后缀。macOS 使用原生名称输入框，写入超过 0.1 秒显示进度，完成后反馈结果。
- 单击立即选中、双击立即打开，不等待点击动画；上下键切换选中项，搜索输入时不抢占方向键。
- macOS 使用系统文件图标，打开按钮显示默认软件名称及图标；查询不可用时显示通用打开按钮。
- 文件与文件夹支持复制粘贴、拖入和拖出。`⌘C` / `Ctrl+C` 复制，`⌘V` / `Ctrl+V` 粘贴到当前目录；`⌘A` / `Ctrl+A` 全选，Command/Ctrl 点击增减选择，Shift 点击连续选择。
- 可写压缩包内拖到文件夹行或左侧目录树默认移动；按住 Option（其他桌面平台按系统复制修饰键）拖拽复制。拖到 Finder 等外部应用时导出副本，保留压缩包内原文件；外部文件拖入时复制到当前压缩包。
- 粘贴或拖入支持递归文件夹与空目录；同名项目自动命名为 `文件 2.ext`，不覆盖已有条目。没有打开压缩包时拖入压缩包可直接打开，拖入普通文件则选择位置创建 ZIP。
- 传入、内部复制和移动支持未加密 ZIP、7z、TAR、压缩 TAR 和 CPIO。原包内容变化时中止写入；成功写入之前保留原包备份。文件剪贴板与通用拖拽使用 `super_clipboard` / `super_drag_and_drop`，macOS 拖出使用 AppKit 文件 URL 拖拽。
- 宽屏三栏；窄屏抽屉导航；所有内容区域支持滚动。
- 浏览 ZIP、TAR、gzip、7z、RAR 等 libarchive 可识别的格式。具体编码取决于系统库/构建包含的 codecs；不承诺所有变体。
- 图片预览：PNG/JPEG/GIF/WebP/BMP；UTF-8 文本预览（包括 Markdown、JSON 和代码）。其他编码暂按 UTF-8 容错显示。
- 双击文件在默认应用中打开：先解压到独立临时目录，保留原文件扩展名。
- 每 3 秒、应用恢复前台时检查已打开文件；内容变化后询问是否更新压缩包，仅提供“是 / 否”；提示选择“否”后，关闭压缩包标签会丢弃未保存修改。
- 可写压缩包写回：检查原包与编辑文件摘要、流式重建到暂存包、保留原包备份、原子替换。
- macOS 沙盒保持开启；文件选取授权，写回使用系统 item replacement directory 与 NSFileCoordinator。
- 全部解压/所选解压到用户选定目录中的新建子目录，不覆盖已有文件。
- 从选择的多个文件创建 ZIP、7z、TAR、TAR.gz/bz2/xz/lzma、CPIO；单文件可创建 gzip、bzip2、xz、LZMA。修改写回保留原格式及压缩过滤器；RAR、CAB、ISO 等格式只读。
- `⌘O` / `Ctrl+O` 打开、`Alt+←` 返回。macOS 空格打开/关闭系统 Quick Look，预览中上下键同步切换当前目录内可打开的文件；其他平台使用应用内预览。
- 系统预览中的文件也纳入修改检测，通过 Quick Look 的打开按钮编辑后可以提示写回压缩包。

## 项目结构

```text
lib/models/archive_entry.dart        条目模型、目录合成、路径验证
lib/services/archive_service_io.dart 文件会话、预览、修改检测、写回事务
lib/services/archive_service_stub.dart Web 平台明确提示原生引擎不可用
lib/ui/archive_app.dart              自适应工作空间
packages/hizip_native/lib/           后台 isolate + FFI
packages/hizip_native/src/           共享 C ABI、流式 libarchive 封装
lib/services/desktop_integration.dart 系统图标、默认应用、Quick Look 通道
lib/services/file_transfer_clipboard.dart 原生文件剪贴板
lib/ui/file_drop_target.dart          拖入目标与高亮反馈
packages/hizip_native/macos/Classes/ macOS 系统预览、图标及原子文件替换接口
packages/hizip_native/third_party/   原版 libarchive 3.8.9 源码包及校验值
```

压缩算法没有用 Dart 重写。Apple 平台优先复用系统库；Windows/Linux/Android 的 CMake 编译仓库中固定版本的上游源代码。
原生依赖来源与授权见 [third_party/README.md](packages/hizip_native/third_party/README.md) 和 [libarchive LICENSE](packages/hizip_native/src/vendor/LIBARCHIVE-LICENSE)。

## 平台状态

| 平台 | 工程 / 引擎 | 验证状态 |
| --- | --- | --- |
| macOS | Flutter + FFI + 系统 libarchive + 沙盒文件替换 | 本机 debug 构建、原生读写测试与 UI 实测 |
| Windows | Flutter + FFI + CMake 上游 libarchive | 已提供工程，未在 Windows 编译或实测 |
| Linux | Flutter + FFI + CMake 上游 libarchive | 已提供工程，未在 Linux 编译或实测 |
| Android | Flutter + FFI + NDK/CMake 上游 libarchive | 已提供工程，未在设备实测；额外 codecs 需交叉编译 |
| iOS | Flutter + FFI + 系统 libarchive | 已提供工程，未验证设备构建、外部编辑和发布限制 |
| Web | Flutter 自适应界面 | 引擎尚未接入；需要 libarchive WebAssembly 后端 |

Linux/Windows 构建需要 Flutter 官方桌面工具链和 CMake 3.18+。
建议安装 zlib 与 liblzma 开发包（Windows 可通过 vcpkg/toolchain 提供），其他 codecs 由上游 CMake 检测。
CMake 本身不联网下载 libarchive；源码包随仓库保存。系统动态压缩依赖的分发仍需在目标平台打包验证。
Android 使用 NDK zlib，liblzma/bzip2/zstd 等需传入适配目标 ABI 的库。

移动端部分选择器（尤其保存位置、目录选择）和外部编辑应用的回传机制需要后续适配，不能把桌面流程视为已完成移动端功能。

## 验证

```sh
flutter analyze
flutter test

# macOS 原生测试（使用系统 libarchive）
xcrun clang -dynamiclib -Wall -Wextra -Werror -O2 \
  packages/hizip_native/src/hizip_native.c -larchive \
  -o /tmp/libhizip_native.dylib
python3 test/native/archive_engine_test.py
HIZIP_TEST_C_LOCALE=1 python3 test/native/archive_engine_test.py
HIZIP_NATIVE_LIBRARY=/tmp/libhizip_native.dylib flutter test

# 验证仓库内上游源码的独立 CMake 构建
cmake -S packages/hizip_native/src -B /tmp/hizip-native-cmake -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/hizip-native-cmake --target hizip_native -j 4
HIZIP_NATIVE_LIBRARY=/tmp/hizip-native-cmake/libhizip_native.dylib python3 test/native/archive_engine_test.py

flutter build macos --debug
flutter build web
```

原生用例覆盖 ZIP 创建、中文路径、内容提取、写回保留其他条目、无效包、加密 ZIP 只读、TAR/gzip、链接拒绝、路径穿越、大小限制及已有输出不被删除。文件传输测试覆盖文件夹传入、内部复制与移动、同名自动命名、空目录、导出内容、禁止自身/子目录移动，以及失败时原包保持不变。

## v0.1 的明确边界

- 加密包可列出条目，暂不输入密码、不提取；RAR/7z/TAR 等暂不写回。
- 不支持分卷、进度取消、压缩包内删除和直接重命名。右侧栏及底部信息栏支持解压多选项目，包括文件夹内容与空目录。
- 一次打开一个压缩包；macOS 最近打开使用系统文档记录，支持跨会话保留与清除。
- 不执行或恢复压缩包中的链接/特殊文件；拒绝路径穿越和重复目标路径。
- 打开、解压、拖拽、导入和写回不设置文件大小或总量上限。文本预览 2 MB、图片预览 20 MB；超出时仅在预览区域提示，不弹出错误窗口，仍可打开或解压。条目数上限 100,000。
- ZIP 重建保留条目内容与常规元数据，不保证保留所有专有 ZIP 扩展字段、原始压缩参数或包注释。
- 临时文件按压缩包隔离管理。关闭压缩包标签、关闭主窗口或正常退出时，等待缓存读取/导出完成，清理临时预览、预取导出和写回备份。已发布到系统剪贴板的导出保留到剪贴板被替换或应用退出，允许切换标签或关闭原标签后继续粘贴。用户主动解压到目标目录的文件不受影响。修改确认只提供“是 / 否”：选择“否”后关闭压缩包标签会删除临时文件、丢弃未保存修改。尚未回应保存提示或保存失败的文件保留在原临时路径，关闭后停止修改监控；异常强制退出遗留的旧缓存暂未自动回收。
- 用户选择“否”或保存失败后，不反复提示同一次修改；再次编辑后重新提示。
- 当前开发包没有做发行签名、公证或商店发布。
- macOS 双向文件剪贴板已实测；直接 AppKit 拖拽已编译，当前开发会话因 Mac 锁屏尚未完成最终拖拽实测。其他平台的文件传输需要设备验证；Web 当前只能构建界面，压缩引擎仍不可用。暂未处理其他应用提供的虚拟文件/文件承诺及 Android content URI 导入。

下一步：完成 macOS 拖拽实测、Windows/Linux CI、移动端文档导入与分享回传、密码/分卷支持、操作队列、会话恢复和 WebAssembly 后端。

## 操作窗口

桌面端使用 `desktop_multi_window 0.3.1`。打开压缩包、打开外部编辑器、创建、保存、复制、传入、移动和拖拽准备持续超过 100 ms 时显示独立进度窗口，完成后显示成功或失败结果；快速的主动操作也显示结果。搜索、预览及拖拽预备处理只在耗时超过 100 ms 时显示成功反馈，失败始终显示。解压显示真实字节进度；未提供进度数据的步骤显示不定进度。进度窗口约 480×260，短结果窗口约 480×200，长确认约 480×300；关闭进度窗口不会取消后台任务。原生拖拽开始时收起准备窗口，结束后显示完成或取消，内部拖入操作以实际写入结果为准。

解压窗口显示当前文件和全部文件两条进度条，使用 libarchive 每个输出块的真实字节数。并行解压的当前文件显示最近报告进度的工作线程，整体进度汇总所有线程；未知大小的条目使用不定进度。原生消息按约每秒 10 次合并。
移动端与 Web 使用主界面中央的同款提示面板；顶部进度条和底部操作消息已移除。Windows/Linux 的子窗口插件注册已接入，仍需在对应设备上验证。

## 解压性能与设置

设置窗口始终提供“外观”和“性能”分类边栏。macOS 设置与操作窗口使用系统标题栏、边框和红绿灯，⌘W 关闭当前窗口。选中控件采用淡中性色背景；文件选择高亮可在“外观”中选择蓝色或淡灰色，偏好自动保存，默认蓝色。多栏仅最右侧列使用所选高亮，左侧路径列始终灰色；多栏上级目录使用灰色高亮，右侧预览使用统一背景、大图标及多选汇总。

桌面工具栏齿轮打开独立设置窗口，macOS 系统 HiZip 菜单也提供“设置…”及 ⌘,（Windows/Linux 为 Ctrl+,）。设置可选择跟随系统、浅色或深色，偏好自动保存，主窗口与原生外观同步。macOS 系统“文件”菜单提供打开、最近打开、清除最近记录、创建多种格式的压缩包、解压和关闭当前标签页；保留系统编辑与窗口菜单。空格快速预览仅在文件区域获得焦点时生效，不拦截文本输入。 浏览习惯自动保存在本机，包括列表/图标/多栏视图、各视图独立的图标大小、预览栏开关，以及目录栏和预览栏宽度；启动时恢复，损坏或过期的设置回退到默认值。图标视图支持 32–256 的图标尺寸，列表支持 12–36，多栏支持 12–32；行距、条目边距及图标间距随尺寸调整。在“性能”中可选择自动、1、2、4 个解压线程，偏好保存在本机，下次解压生效。自动模式按 CPU 数量保留一个核心，最多 4 个工作线程；小于 8 MiB 的 ZIP 默认使用单线程。

ZIP 多文件解压按未压缩大小平衡工作量，每个工作线程拥有独立的 libarchive reader 和 256 KiB 输出缓冲区。每批只打开一次压缩包，通过排序查找分发文件，替代原来的逐文件重新打开和扫描。TAR/gzip、RAR、7z 等使用单批顺序读取，避免重复解码流式或固实数据。单个压缩条目仍由一个解码器处理。主界面与协调、解码工作分别运行在不同 isolate；进度消息合并到每秒最多约 10 次。

批量解压保留路径、链接、加密检查和单次 4 GiB 限制；所有工作线程结束后才清理失败输出，避免线程仍在写入时删除目录。独立文件预览和剪贴板导出仍走原有接口。

可重复原生性能测试（包含内容 SHA-256 校验，取三次中位数）：

```sh
HIZIP_NATIVE_LIBRARY=/tmp/libhizip_native.dylib python3 test/native/extraction_benchmark.py
```

设置中的“压缩包”分类可配置读取默认文件名编码（默认自动识别）、创建 ZIP 的文件名编码（默认 UTF-8）及压缩等级（0–9，默认 6）。支持 GB18030/GBK、Big5、Shift-JIS、CP949、CP437 和 Windows-1252。编码只影响压缩包文件名，不改变文件内容。自动读取先尝试 UTF-8 及格式中的 Unicode 声明，转换失败后依次尝试常用旧编码；未声明编码的文件名可能有歧义，可通过 macOS“文件 → 编码”重新读取当前压缩包。当前包的选择不改变下次打开的默认值，预览、导出和解压复用解析出的编码；修改写回使用 UTF-8 文件名。

画廊视图提供大预览和横向缩略图，可通过工具栏或 macOS“显示 → 画廊视图”切换，左右方向键浏览、回车打开文件或进入目录。关闭预览栏后仍保留画廊大预览，打开预览栏时显示文件信息。缩略图大小独立保存（32–160），按需读取并保持图片比例；缩略图最多缓存 64 张，同时最多读取两张，切换或关闭压缩包后停止排队读取。

“外观”中的语言设置支持简体中文、English 和跟随系统，默认保持简体中文。选择自动保存并立即同步主界面、设置窗口和菜单；跟随系统时，中文系统使用简体中文，其他系统语言使用英文。应用界面文字会切换语言，压缩包中的文件名和文本内容保持原样。

macOS 文件关联覆盖常见压缩格式，在 Finder“打开方式”中可选择 HiZip。安装应用后，可在“设置 → 通用 → 文件关联”点击“设为默认打开方式”；安装和启动不会自动覆盖已有默认程序。Finder 打开多个压缩包会进入各自标签页，冷启动接收的文件在界面准备好后依次打开。

复制、粘贴位于系统“编辑”菜单，文件名编码位于“文件 → 编码”。右侧信息栏在打开方式下提供解压操作；关闭右侧栏时，底部信息栏显示文件名或所选项目数量及打开、解压按钮。普通点击已选条目会恢复单选，修饰键仍支持多选。多标签栏从左侧目录栏右边开始。图标视图支持四个方向键按实际网格移动，左右选择相邻项目，上下保持同列；选中项自动滚动到可见区域。
