# hizip_native

HiZip 的原生压缩引擎，使用 libarchive 解析、解压和创建压缩包。Dart 层提供 FFI 内存管理与后台执行接口。

## 接口

`NativeArchive` 提供 `list`、`extract`、`replace`、`update` 和 `create`。

- C 接口返回由调用方拥有的 JSON 结果，使用 `hz_free` 释放。
- 提取目标必须是新文件，避免覆盖已有内容。
- 更新操作写入独立输出文件，不直接修改原包。应用服务层负责校验、备份和提交替换。
- 支持 ZIP、7z、TAR、压缩 TAR、CPIO 和 AR 的创建与更新，以及 gzip、bzip2、xz、LZMA、zstd、LZ4、lzip、compress 单文件压缩。
- 格式与编解码能力由目标平台的 libarchive 构建决定。

## 平台集成

Apple 平台使用系统 libarchive。Windows、Linux 和 Android 通过 CMake 编译仓库内固定版本的上游源码；额外 codecs 由构建依赖决定。

macOS 插件还提供系统文件图标、应用查询、Quick Look、文件拖拽、菜单和沙盒内文件替换接口。Quick Look 与外部编辑复用受监控的临时文件。

## 构建与测试

通过 Flutter 项目构建时，原生库随平台工程编译。也可以单独构建 C 引擎：

```sh
cmake -S packages/hizip_native/src -B build/native -DCMAKE_BUILD_TYPE=Release
cmake --build build/native --target hizip_native
```

以上命令在 HiZip 仓库根目录执行。测试时通过 `HIZIP_NATIVE_LIBRARY` 指向对应平台的动态库。

格式、使用方式和测试入口见 [项目 README](../../README.md)。源码来源与授权见 [third_party/README.md](third_party/README.md) 和 [libarchive LICENSE](src/vendor/LIBARCHIVE-LICENSE)。
