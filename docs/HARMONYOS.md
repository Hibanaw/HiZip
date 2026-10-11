# HiZip HarmonyOS

`ohos` 分支合入主线的原生引擎、归档操作和统一界面。应用包名为
`com.hibanaw.hizip`，支持 2in1、平板和手机，使用主线的 HiZip 图标。

## 窗口与界面

鸿蒙只提供融合窗口模式。设置不显示窗口模式选择；即使旧设置保存了独立窗口，
读取时也固定使用融合窗口。创建、提取、重命名、属性等对话框沿用统一控件、边框
和背景处理；紧凑布局全屏显示。任务进度和结果始终留在底部状态栏。

图标大小范围、无数字滑条、亮色标签和高亮前景沿用主线。宽布局支持原文件名位置
重命名，紧凑布局使用对话框。列表、图标、分栏、图库、多标签、预览、搜索、排序、
属性、注释、队列及外部修改检测继续使用共享 Flutter 实现。

## 文件操作与系统集成

- 系统文件选择器支持文件多选和文件夹导入；创建压缩包可混合选择文件和文件夹。
- 文件先导入应用工作副本。创建和提取结果通过用户授权的保存位置导出；“文件 →
  保存副本…”导出当前归档。快速 ZIP 在鸿蒙需要选择保存位置。
- 分卷压缩额外选择输出目录，导出全部分卷。选择性解压允许直接导出所选内容。
- 外部打开使用隐式 `viewData` Want，遵循系统默认应用；可写条目附带 URI 写授权，
  只读条目只有读授权。修改检测与用户确认后写回归档工作副本的流程继续可用。
- 声明归档 MIME 类型和单实例 Ability，接收系统冷启动及运行中的文件打开请求。
- 文件图标使用 File Manager Service 的 `getFileIcon`，将 Base64 或系统命名资源
  转为 PNG；接口失败时保留 Flutter 图标。

系统文件的原始 URI 留在 ArkTS 层，FFI 只读取沙箱路径。导出前检查路径、符号链接
和已有目标；不会将未授权的用户路径直接传给 C 引擎。

### 平台限制

普通应用不能自行设置系统默认应用，也不能可靠读取实际默认应用的名字。界面使用
“系统默认应用”入口，默认关联交给系统管理。SDK 的 `GET_ABILITY_INFO` 定义要求
`system_basic` 权限且限定 2in1；平板模拟器实际返回权限拒绝，因此没有保留无效的
应用列表查询或“其他应用”按钮。隐式打开遵循用户默认设置，不强制显示选择器。

归档内条目的原位重命名及外部编辑写回工作副本已经支持。对系统源文件的自动原位
覆盖尚未提供，当前使用显式保存副本；应在关闭前导出需要保留的修改。公共目录与
已有目标冲突时会报告错误，跨公共 URI 的事务合并、覆盖和链接导出尚未实现。
系统文件剪贴板、桌面拖出和 macOS Quick Look 没有鸿蒙实现；使用添加、提取及
保存副本。RAR 创建、7z 加密和加密归档内部修改仍与主线一样不支持。

## 原生引擎

除 libarchive 与 UnRAR 外，鸿蒙构建从仓库内的固定源码交叉编译 XZ/liblzma 5.8.4、
bzip2 1.0.8 和 Mbed TLS 3.6.7。支持 7z、XZ/LZMA、BZip2、ZIP AES-256 等能力，
不会误链接主机上的 macOS 编解码库。构建不需要下载这些依赖。

额外修复了能力检测继承工作线程中旧加密配置的问题，避免打开加密包后创建格式
列表消失。能力探测完成后恢复操作配置；同时在 UTF-8 locale 中探测，避免鸿蒙默认
C locale 误报 ZIP 不可用。原生回归测试覆盖配置恢复及 C locale。

## 构建与模拟器测试

```sh
tools/flutter-ohos pub get
python3 tools/build-ohos-emulator.py
python3 tools/test-ohos-emulator.py --device 127.0.0.1:5555
```

模拟器脚本暂用仓库内的无签名模板，结束后恢复本机签名配置。生成的
`build/ohos/hap/entry-default-unsigned.hap` 可安装到模拟器；真机和发布需要为
`com.hibanaw.hizip` 配置对应的签名。签名文件、密码、SDK 和缓存不提交。

Flutter OH 的预编译 HAP 解析仍是未实现接口，测试脚本通过已安装应用的 VM 服务
运行官方 integration_test 驱动，并清理其自身的端口转发。关闭测试专用的原生
结果回报，避免 SDK 插件没有 Hypium 结果容器时在收尾阶段报错。

本轮验证使用 API 21 平板模拟器和 API 26 构建 SDK。测试覆盖主机服务、设置存储、
单窗口约束、系统 ZIP 图标、中文 ZIP 预览与重命名及提取、AES 密码校验、7z/XZ/
BZip2 的实际压缩读取、加密固实 RAR5，以及创建和设置界面与紧凑全屏对话框。
系统文件选择器的实际用户选择、第三方编辑器修改和公共目录冲突流程仍需交互验收。

## API 依据

以随官方 SDK 分发的声明及权限定义为准：

| 功能 | SDK 接口 |
| --- | --- |
| 文件选择/保存 | `@ohos.file.picker.d.ts`: DocumentViewPicker、MIXED |
| URI 打开和授权 | AbilityKit: Want、viewData、READ/WRITE URI flags |
| 系统文件图标 | `@hms.filemanagement.fileManagerService.d.ts`: getFileIcon |
| 命名资源与 PNG | ResourceManager、ImagePacker |
| 应用列表的权限限制 | `toolchains/lib/PermissionDefinitions.json`: GET_ABILITY_INFO |
| 默认应用边界 | `@ohos.bundle.defaultAppManager.d.ts` |
