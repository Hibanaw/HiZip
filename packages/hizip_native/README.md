# hizip_native

HiZip 的原生压缩引擎，使用 libarchive 解析、解压和创建压缩包，RAR 读取使用内置官方 UnRAR 7.23。Dart 层提供 FFI 内存管理与后台执行接口。

## 接口

`NativeArchive` 提供 `list`、`extract`、`replace`、`update`、`create`、`rename`、`verify` 和 `capabilities`。

- Dart `ZipMetadata` 读取并编辑 ZIP 注释；`NativeArchive` 的重建接口保留压缩包和条目注释。直接调用 C ABI 重建不会自动保留 ZIP 注释。
- `NativeOperationControl` 在排空所有后台任务前保持有效；工作线程使用原生检查点暂停或取消，提交后拒绝中断。
- `commitNew` 使用排他发布，目标已存在时明确失败。
- C 接口返回由调用方拥有的 JSON 结果，使用 `hz_free` 释放。
- 提取目标必须是新文件，避免覆盖已有内容。
- 更新与重命名操作写入独立输出文件，不直接修改原包。应用服务层负责校验、冲突检查和提交替换。
- `verify` 读取全部条目数据并返回条目数与字节数，不生成解压文件；读取或校验失败时返回错误。
- 容器格式允许空源列表，单文件压缩格式仍要求一个源文件。
- 支持 ZIP、7z、TAR、压缩 TAR、CPIO 和 AR 的创建与更新，以及 gzip、bzip2、xz、LZMA、zstd、LZ4、lzip、compress 单文件压缩。
- 密码作为每次读操作的显式参数传入，原生线程配置在操作结束后清空；不写入应用设置。
- ZIP 创建支持 AES-256、Deflate/Store 和压缩等级；不支持加密包更新或文件名加密。
- `capabilities` 返回当前可配置的写入格式、ZIP AES 能力及明确不支持的加密更新/文件名加密标记。
- `capabilities` 还返回 `rarRead`、`rarEncryption`、`rarVolumes`；RAR 永远只读。
- RAR 按文件签名识别，支持 RAR4/RAR5、密码与文件名加密、固实压缩和原生分卷。使用 UnRAR 的测试模式通过数据回调写入应用指定的目标文件，不允许解码器自行创建路径、链接或覆盖文件。
- UnRAR 的全局错误处理器需要会话串行化；等待锁、条目和数据块检查点都响应取消/暂停，固实包只使用一个批量读取通道。
- 同一读取会话使用一个密码，具有多个不同文件密码的包暂不能整体解锁。链接/引用无法安全映射时标为不可提取。
- `setReadOnly` 给外部打开的临时文件设置系统只读权限；缓存清理前恢复权限。
- 其他格式与编解码能力由目标平台的 libarchive 构建决定，实际数据写入仍可能返回能力或资源错误。

## 平台集成

Apple 平台使用系统 libarchive。Windows、Linux 和 Android 通过 CMake 编译仓库内固定版本的上游源码；额外 codecs 由构建依赖决定。CMake 允许发现可选 OpenSSL，以启用 Linux 等平台的 AES；跨编译时应提供目标平台依赖，不能使用宿主库。

macOS 插件还提供系统文件图标、应用查询、Quick Look、文件拖拽、菜单和沙盒内文件替换接口。Quick Look 与外部打开复用临时文件，可写压缩包启用修改监控，只读压缩包锁定临时文件及其目录。

## 构建与测试

通过 Flutter 项目构建时，原生库随平台工程编译。也可以单独构建 C/C++ 引擎：

```sh
cmake -S packages/hizip_native/src -B build/native -DCMAKE_BUILD_TYPE=Release
cmake --build build/native --target hizip_native
```

以上命令在 HiZip 仓库根目录执行。测试时通过 `HIZIP_NATIVE_LIBRARY` 指向对应平台的动态库。

格式、使用方式和测试入口见 [项目 README](../../README.md)。源码来源与授权见 [third_party/README.md](third_party/README.md) 和 [libarchive LICENSE](src/vendor/LIBARCHIVE-LICENSE)。
