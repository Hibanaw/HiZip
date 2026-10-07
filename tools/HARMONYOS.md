# 鸿蒙开发工具

`tools/flutter-ohos` 为 HiZip 的鸿蒙移植工作提供独立 Flutter OH 启动环境。工具链、依赖缓存与构建输出存放在 Git 忽略的 `.toolchains/` 目录中，不修改系统 Flutter SDK。

## 环境要求

- 与项目 `pubspec.yaml` 要求兼容的 Flutter OH SDK。
- 与该 SDK 版本匹配的 DevEco Studio 或 Command Line Tools、HarmonyOS SDK、Java 和 Node。
- 平台代码、依赖插件和原生引擎的鸿蒙适配。
- 真机安装所需的设备连接与开发签名。

Flutter OH 工具链可用不代表项目已经完成鸿蒙适配；需要分别验证依赖解析、平台编译和设备运行。

## SDK 布局

```text
.toolchains/
  flutter-ohos/             Flutter OH SDK
  command-line-tools/       独立 DevEco 工具包（可选）
  pub-cache/                鸿蒙开发依赖缓存
```

Flutter OH SDK 安装到 `.toolchains/flutter-ohos`。使用的社区仓库与版本应匹配项目依赖和对应平台 SDK 的发布要求。

## 使用

在项目根目录运行：

```sh
tools/flutter-ohos --version
tools/flutter-ohos doctor -v
tools/flutter-ohos devices
tools/flutter-ohos precache --ohos
```

脚本优先使用 `.toolchains/command-line-tools`，否则使用 DevEco Studio 的工具目录。可以通过环境变量覆盖路径：

| 变量 | 用途 |
| --- | --- |
| `HIZIP_DEVECO_HOME` | DevEco 工具目录 |
| `HIZIP_JAVA_HOME` | Java 安装目录 |

启动脚本仅为自身及子进程配置环境，普通 `flutter` 命令仍使用系统原有 SDK。

## 适配范围

鸿蒙移植需要处理文件选择与授权、原生插件注册、libarchive 交叉编译、压缩依赖，以及桌面专用接口的替代实现。文件关联、外部编辑和拖拽应按目标平台能力实现。

构建前应确认项目已经具备对应的 `ohos/` 平台工程和可用插件。未签名构建可用于检查编译与打包；部署到设备仍需完成签名配置。
