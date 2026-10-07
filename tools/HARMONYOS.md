# 鸿蒙 Flutter 工具链

本项目使用独立的 Flutter OH 工具链，不修改系统 PATH 或现有 Flutter SDK。

**当前状态：Flutter OH 与配套 API 26 已安装，独立空白工程未签名 HAP 构建通过。**

**当前 HiZip 还要求 Dart `^3.13.0`、Flutter `>=3.47.0`，与本工具链的
Dart 3.11.5 / Flutter OH 3.41 不兼容。** 本工具链可用于独立验证工程；
主项目需要匹配的 Flutter OH 3.47 版本，或另行评估移植分支的依赖与代码降级。
不能仅修改 SDK 下限来宣称兼容。本次没有修改主项目的 SDK 要求。

2026-10-07 查询社区远端：没有 3.47 发布 tag，仅发现 `br_3.47.0_bak` 和
`oh-3.47.0-dev_bak`。后者 commit 为 `1f36fc0ae74955c780646ac3c0916a2f0e4676a6`，
包含鸿蒙工具代码，但其 `engine.ohos.version` 对应的 Darwin ARM64 Dart SDK
在默认鸿蒙产物源返回 HTTP 404。因此本次没有把备份分支切换为日常工具链；
保留了可运行的 3.41 稳定 tag 用于独立验证。

## 固定版本

- 仓库：https://gitcode.com/CPF-Flutter/flutter_flutter.git
- 标签：`3.41.10-ohos-1.0.1`
- Git commit：`adaf911c35c9136a7d18fc424d714c9ec7724e60`
- SDK 目录：`.toolchains/flutter-ohos`
- Command Line Tools：`.toolchains/command-line-tools`，26.0.0 Beta2 / 26.0.0.621
- HarmonyOS SDK：独立 API 26 / 26.0.0.32；原 DevEco API 21 保留
- Java：DevEco 内置 JBR 21；Node：工具包内置 24.14.1
- 鸿蒙开发专用 Pub 缓存：`.toolchains/pub-cache`

## 已验证

- Flutter OH 启动成功，Dart 3.11.5。
- `precache --ohos` 完成。
- `doctor -v` 的 HarmonyOS toolchain 检查通过：API 26、ohpm 26.0.0.410、Node 24.14.1、hvigorw。
- 新检查日志：`.toolchains/doctor-api26.txt`。
- 当前未连接鸿蒙设备。
- 当前项目 C/libarchive 引擎成功交叉编译为 ARM64 ELF 动态库：
  `.toolchains/native-ohos-check/libhizip_native.so`，依赖 `libz.so`、`libc.so`。
  这仅验证编译与链接，尚未在鸿蒙设备加载或运行；lzma/bzip2/zstd 等可选 codecs 未接入。
- 检查日志：`.toolchains/doctor.txt`；独立空白工程：`.toolchains/hizip_ohos_smoke`。

固定社区 tag 会让 doctor 提示非标准 channel/remote；不应为消除提示切换到上游 Flutter。
本机 Xcode 模拟器运行时检查也有提示，独立于鸿蒙工具链检查。

## 配套平台 SDK

根据所安装 tag 的 `release-notes/Flutter 3.41.9-ohos 1.0.1 ReleaseNote.md`：

- DevEco Studio / Command Line Tools 要求 **26.0.0 Beta2，Build 26.0.0.621**。
- 应用目标 / 引擎构建 API 为 **26.0.0**；最低运行 API 为 17。

本机的 API 21 能通过 doctor 的路径检查，但无法编译此版本引擎的 ArkTS 层。
空白工程实测出现 `autoFillManager`、`CompetitionStrategy`、
`Window.isInFreeWindowMode` 等平台 API 缺失；完整日志为 `.toolchains/smoke-build.txt`。
不要通过删除引擎功能或修改类型声明掩盖该不兼容。

官方工具包下载入口：https://developer.huawei.com/consumer/cn/download/
2026-10-07 已完成华为账号登录。官方详情页提供 Mac ARM64
Command Line Tools 26.0.0 Release（Build 26.0.0.851，约 2 GB），
也提供发布说明配套的 26.0.0 Beta2（Build 26.0.0.621）。
2026-10-07 重试 Beta2 时浏览器下载地址出现 503；改用官网生成的地址通过
命令行下载成功，文件 `.toolchains/commandline-tools-mac-arm64-26.0.0.621.zip`，
大小 2,053,599,964 字节。SHA-256 与官方文件响应中的校验值一致：
`c5e71750eda7de50e906a22547d7844e7f60aaabed45cb5fa9a75944bc5cdb23`。
工具包独立解压到 `.toolchains/command-line-tools`。首次解压受磁盘空间限制，
在系统可用空间恢复后补齐完整组件。

独立空白工程已用 `build hap --release --no-codesign` 构建成功，产物为
`.toolchains/hizip_ohos_smoke/build/ohos/hap/entry-default-unsigned.hap`（20.6 MB），
HAP ZIP CRC 检查通过，包含 ARM64 `libflutter.so` 和 `libapp.so`。
日志：`.toolchains/smoke-build-api26.txt`。
普通签名构建因尚未配置签名而退出；未签名包不能直接部署真机。
详情页：https://developer.huawei.com/consumer/cn/download/command-line-tools-for-hmos

## 使用

在项目根目录运行：

```sh
tools/flutter-ohos --version
tools/flutter-ohos doctor -v
tools/flutter-ohos devices
tools/flutter-ohos precache --ohos
```

脚本默认优先使用独立 Command Line Tools。可用 `HIZIP_DEVECO_HOME` 覆盖工具包
目录（也兼容 DevEco app 的 `Contents`），用 `HIZIP_JAVA_HOME` 覆盖 Java 路径。
工具包中的 `tools/` 链接兼容 Flutter OH 的 Node 路径检测。
启动脚本只对子进程设置环境变量；普通 `flutter` 仍使用原有 SDK。
SDK、下载缓存和验证工程均放在 Git 忽略的 `.toolchains/` 中。

## 空白工程构建验证

```sh
cd .toolchains/hizip_ohos_smoke
../../tools/flutter-ohos build hap --release --no-codesign
```

## 重建安装

```sh
git clone --depth 1 --branch 3.41.10-ohos-1.0.1 \
  https://gitcode.com/CPF-Flutter/flutter_flutter.git .toolchains/flutter-ohos
tools/flutter-ohos --version
tools/flutter-ohos precache --ohos
tools/flutter-ohos doctor -v
```

## 边界

工具链准备与 HiZip 鸿蒙平台移植是两个步骤。主项目尚未添加 `ohos/`；
原生插件注册、插件依赖和文件授权仍需适配，不能直接在当前主项目执行 HAP 构建。
实际安装到真机还需要设备连接和开发签名。
